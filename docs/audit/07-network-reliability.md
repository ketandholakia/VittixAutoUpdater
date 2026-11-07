# 07 — Network and download reliability

Transport is Delphi `System.Net.HttpClient`/`System.Net.URLClient`, not Indy/WinHTTP/WinINet/BITS (`VittixAutoUpdater.Network.pas` implementation uses). Indy appears only in the loopback test server.

## Implemented controls

* Connection timeout configured; response timeout is ten times that value (`Network.pas:719-731`).
* HTTPS required by default and URL/redirect helper checks exist (`297-355,893-910`). Platform TLS validation is delegated to `THTTPClient`; no bypass found.
* Mirror fallback and retries; retry delay helper supports backoff (`858-961`, helper at `387+`).
* HEAD then GET; Range resume is conditional on matching ETag, URL, remote size and expected size (`963+`).
* Progress callback can abort; size cap allows a limited margin over manifest file size (`734-775`).
* Disk free-space check against expected download size (`995-1005`).
* SHA-256 verification and expected-size checks are used before successful completion; inspect remaining `DownloadFile` body at `Network.pas:1020+` for all failure branches.

## Gaps and risks

Manifest GET buffers full response in `TMemoryStream` before parsing; no clear maximum manifest byte limit. Package temp path and `.part-N` names are predictable, and initial path is deleted if already present (`1015+`); collision/TOCTOU and parallel operation risk. Expected size is optional at manifest level and may be missing/invalid; then size cap and disk check do not protect. Cancellation is callback-driven and may wait for response timeout. Proxy configuration appears host + fixed port only, with no proxy credentials. No bandwidth limit or configurable retry policy per HTTP status. Resume correctness relies on server HEAD/range metadata and merits mock-server execution. A truncated response should fail size/checksum if metadata is supplied, but runtime cases are not executed.

No tests were executed. DUnitX source includes loopback cases for redirects, retries/resume, dropped connections, manifest parsing/signatures, and size/cancellation; see `Test.VittixAutoUpdater.pas:104-285,480+`. This is source coverage, not passing evidence.
