# 08 — Component API and developer experience

The registered VCL control `TVittixAutoUpdaterUI` is a form-oriented visual panel, not a minimal nonvisual updater component. It exposes config and UI properties plus check/download/install/cancel methods and events (`VisualComponent.pas:126-212`). Registration is in `ComponentReg.pas:12-21`; an additional `Register` appears in `VisualComponent.pas` and can complicate package registration. Property editor exposes a subset of settings (`PropertyEditors.pas`); security fields such as signature requirements/key and Authenticode pins are not all surfaced in that dialog.

The current flow is reasonably discoverable for a VCL demo: configure `TUpdaterConfig`, check, inspect release notes, download with progress, then install/restart. Docs reference methods/features that may not match current public API, and install failure reporting from background batch is not observable.

For service, console, and nonvisual apps, a headless API is valuable: core should not require VCL; expose structured results and cancellation tokens; keep the VCL component as an adapter. Document event thread affinity, config validation, supported manifest schema, signing setup, and safe installation requirements. RAD Studio 12 design-time install is unverified: no compiler/IDE build evidence exists.
