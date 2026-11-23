# 04 — Delphi code quality

## Findings

The code has an explicit state enum and lock around key state transitions (`Engine.pas`), exception cleanup around stream/archive objects, a queued VCL event mechanism, and interfaces for cross-thread progress cancellation (`VisualComponent.pas:26-41,220+`). These are sound foundations.

Key concerns:

* **Thread ownership:** UI component starts anonymous workers for download/install and dispatches queued UI records. Destruction waits for workers (`VisualComponent.pas:290+`), which can block the UI until HTTP timeout. Check path also runs asynchronously in engine; owner destruction and callback lifetime require the manual checklist's GUI scenarios. Not executed.
* **Shared mutable transport state:** `TUpdateNetworkManager` stores callback, cancellation flag, offset, expected size, and progress state on the instance (`Network.pas:16-39`). Concurrent check/download or two downloads on one engine can race; engine state gating reduces but does not prove all entry points serialize.
* **Callback thread affinity:** Engine calls `FOnStateChange` directly in worker-sensitive methods; correctness relies on UI wrapper to queue. Direct consumers of engine must marshal their own VCL callbacks.
* **Cancellation:** network cancellation sets a shared Boolean (`Network.pas:772-775`) and is sampled from receive callbacks; a stalled request depends on response timeout. No cancellation during extraction/apply.
* **Exception handling:** worker methods convert exceptions to state/error text; useful cleanup exists. Some asynchronous callback failures may be logged/suppressed and some failure states return without guaranteed temp cleanup. Audit individual paths and test destructor races.
* **Object lifetime:** streams, HTTP clients, ZIP archive, and strings lists generally use `try/finally`; CNG/crypto handles need careful checked cleanup. `TUpdateManifest.Empty` uses `FillChar` on a record with managed strings (`Types.pas:350+`): this is only safe for a fresh uninitialized result record, and is a maintainability hazard if reused on an already initialized value.
* **State API:** state is set directly under lock in some paths and via setter elsewhere; callbacks may observe state updates asynchronously or not consistently. No formal transition table/invariant enforcement.
* **Configuration:** record-based config is convenient but not validated centrally; zero/negative timeout, retry and interval values can produce surprising behavior. Design-time editor exposes only a subset of security-critical options.
* **Version parsing:** numeric 1-4 components, each 0..65535; no SemVer prerelease/build metadata.
* **VCL coupling:** visual component and settings dependencies live alongside core package, limiting service/headless use and automated isolation.
* **Compatibility:** modern Delphi APIs are used; the advertised legacy compiler support is not demonstrated by builds. Conditional `VER150` does not establish XE7 support.

## API/maintenance assessment

Separate a transport-neutral engine package from VCL adapter/design package; provide an explicit immutable configuration validation result and stable error codes; document thread affinity and callback guarantees; make engine operations serialized/cancellable with owned task lifetime; centralize transitions and ensure all terminal paths clean or preserve files by policy. Keep source compatibility consciously versioned.

No code was modified and no build was run. Delphi compiler availability was not established in this audit.
