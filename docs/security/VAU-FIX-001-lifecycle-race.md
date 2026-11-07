# VAU-FIX-001 lifecycle race

Date: 2026-10-28
Compiler: RAD Studio 12 Athens, compiler 36.0

## Result

**PASS for the tested lifecycle scenarios.** The repeated-check timeout is fixed. The original VCL test passed ten consecutive isolated Win32 runs, and the final DUnitX suites passed on Win32 and Win64 (64/64 each).

## Original failure and root cause

Before the fix, the worker called SynchronizeCheckCompletion, which used TThread.Synchronize to execute terminal state and the completion callback on the main thread. The worker remained blocked until the main-thread action returned.

The VCL completion closure set FIsUpdating to False before queuing its presentation event. A repeated check could therefore be requested while the previous worker was still blocked in Synchronize. CheckForUpdate saw FCheckCompletionInProgress or a non-finished FCheckThread and returned without starting a new request. The component stayed idle with no callback to clear its busy state again. The reproduced Win32 test reported manifest=1, states=2, updating=True, engine-state=0.

Relevant prior source locations: Engine CheckForUpdate and SynchronizeCheckCompletion; VisualComponent CheckForUpdates; Integration test VclComponentSupportsDataModuleOwnershipAndRepeatedChecks.

## Corrected sequence

The engine now queues a terminal action associated with the check worker instead of synchronously blocking that worker. The queued action first establishes the terminal engine state, then invokes the completion callback on the main thread. If that callback immediately requests another check, the engine can safely wait for the old worker to finish because the worker no longer depends on main-thread execution.

```mermaid
sequenceDiagram
    participant UI as VCL caller
    participant E as Update engine
    participant W as Check worker
    participant Q as Main-thread queue

    UI->>E: CheckForUpdate
    E->>E: state = Checking
    E->>W: start request
    W->>W: fetch and verify result
    W->>Q: queue terminal action
    W-->>W: return and finish
    Q->>E: execute terminal action
    E->>E: set terminal state
    E->>UI: engine state callback queues VCL state event
    E->>UI: completion callback queues completion presentation
    Q->>UI: deliver terminal VCL state event on main thread
    UI->>E: immediate next CheckForUpdate
    E->>W: wait for completed prior worker
    E->>E: state = Checking; start next request
    Q->>UI: deliver prior completion presentation
    UI->>UI: discard it because its generation is stale
```

The engine state notification queues the visual event instead of dispatching it reentrantly inside the engine completion action. The internal check-completion callback then runs while the engine still has the terminal state and queues its presentation event. The visual queue preserves state-event-before-completion-event order. If the app starts another check from the terminal VCL state event, the older presentation event is discarded by generation. A next check is allowed from idle, available, failed, and cancelled states. Calls during active checking/downloading/applying states remain refused.

## State ownership and stale events

The VCL component increments an interlocked check generation for each accepted check. State and completion events carry that generation. The completion closure checks its captured generation before changing IsUpdating or queuing UI work. Dispatch ignores old check-state and completion events when a later check has started. This prevents an old queued completion from clearing the busy flag for a newer request.

The engine completion action is queued against its worker thread. Engine destruction waits for that worker and removes any still-queued completion action before freeing the thread object. The component marks itself as destroying, drops queued UI events, removes its UI dispatcher, detaches engine event handlers, cancels, and then frees the engine. A test-only bounded worker wait allowed the destruction test to establish that engine completion had been queued before freeing the form.

Each engine check also carries an interlocked operation generation. Cancellation advances it, so a completion already queued for the canceled check is discarded before it can publish a result. The engine rechecks the generation after its state notification, preventing a terminal-state handler that starts a newer operation from being followed by a stale completion callback.

No internal lock is held while VCL or application callbacks execute.

## Files changed

- VittixAutoUpdater.Engine.pas
  - Replaced synchronous completion synchronization with main-thread queued completion.
  - Removed the completion-in-progress rejection guard.
  - Allows a new check from idle, available, failed, or cancelled terminal states.
  - Waits for an earlier worker only after the queued completion no longer depends on the main thread.
  - Removes undelivered completion work during engine destruction.
  - Added a test-only worker wait helper under the loopback test define.
- VittixAutoUpdater.VisualComponent.pas
  - Added a check generation to queued UI events.
  - Rejects stale check callbacks and stale queued state/completion events.
  - Allows a recheck when the engine is already in a terminal state, even if an older presentation event has not yet been dispatched.
- Test.VittixAutoUpdater.Integration.pas
  - Changed the repeated VCL check test to recheck from the first terminal state callback and send a burst of additional requests while that check is active.
  - Added immediate engine recheck after a signature failure, recovery after cancellation, exactly-once completion checks, and callback thread checks.
  - Added concurrent independent engine checks.
  - Added deterministic component destruction after the worker queues completion but before main-thread dispatch.

## Test evidence

The original VCL test is VclComponentSupportsDataModuleOwnershipAndRepeatedChecks. Its observer records the terminal state sequence and verifies all VCL state callbacks execute on the main thread. The test rechecks from the first usIdle callback, confirms two requests complete, then issues three rapid requests while the next request is held by a loopback gate and confirms only one request was accepted.

Win32 isolated repetitions: **10/10 passed**, each 1/1 with 0 errors.

Focused lifecycle tests passed **6/6 on Win32 and 6/6 on Win64**:

- VCL immediate repeated check: passed.
- Engine immediate recheck after malformed signature: passed.
- Check after cancellation: passed; the canceled operation delivered no stale completion, and the later accepted check completed once.
- Cancellation after completion was queued but before main-thread dispatch: passed; the engine remained cancelled and did not invoke the queued callback.
- Independent updater instances: passed; both callbacks completed on the main thread.
- Form destruction with engine completion queued: passed; no observer callback occurred after destruction.
- Existing active-request cancel/destruction test: passed.

Full DUnitX suites:

| Target | Found | Passed | Failed | Errored |
|---|---:|---:|---:|---:|
| Win32 | 64 | 64 | 0 | 0 |
| Win64 | 64 | 64 | 0 | 0 |

Runtime Win32, runtime Win64, and design-time Win32 packages built successfully with compiler 36.0. Python manifest-generator tests passed 4/4. git diff --check passed.

## Commands used

Run from the repository root in PowerShell with BDS set to C:\Program Files (x86)\Embarcadero\Studio\23.0 and MSBuild at C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe.

- Test Win32 build: MSBuild TestCompilation.dproj /t:Build /p:Config=Debug /p:Platform=Win32 /p:DCC_Define=DELPHIXE_UP%3BVITTIX_TEST_LOOPBACK%3BVITTIX_TEST_REGISTRY%3BVITTIX_TEST_STAGING /v:quiet
- Original Win32 test repeated 10 times: TestCompilation.exe --run:Test.VittixAutoUpdater.Integration.TVittixAutoUpdaterIntegrationTests.VclComponentSupportsDataModuleOwnershipAndRepeatedChecks --exitbehavior:Continue --consolemode:Quiet
- Full Win32 suite: TestCompilation.exe --exitbehavior:Continue --consolemode:Quiet
- Test Win64 build: same MSBuild command with Platform=Win64
- Full Win64 suite: Win64 TestCompilation.exe --exitbehavior:Continue --consolemode:Quiet
- Runtime Win32: MSBuild VittixAutoUpdaterRuntime.dproj /t:Build /p:Config=Debug /p:Platform=Win32 /p:DCC_Define=DELPHIXE_UP /v:minimal
- Runtime Win64: same runtime command with Platform=Win64
- Design-time Win32: MSBuild VittixAutoUpdaterDesign.dproj /t:Build /p:Config=Debug /p:Platform=Win32 /p:DCC_Define=DELPHIXE_UP /v:minimal
- Python tests: rtk pytest -q tests/test_generate_manifest_signing.py
- Whitespace check: rtk git diff --check

All executed build commands returned exit code 0. The test suite commands returned exit code 0. The ten isolated Win32 invocations each returned exit code 0.

## Remaining limitations

- Component destruction is supported and tested on the VCL/main thread. Cross-thread destruction of VCL components remains unsupported.
- A check requested while the engine is actively checking or downloading is ignored by the existing void-returning API; no explicit busy callback was added. Terminal-state rechecks are accepted and verified.
- The tests cover deterministic reentry, cancellation, queued-completion destruction, and separate engines. They are not a formal proof of all scheduler interleavings.

