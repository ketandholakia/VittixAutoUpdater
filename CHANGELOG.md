# Changelog

This project follows the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format.

## [1.0.0-rc1]

### Security

- Require signed update manifests by default and enforce HTTPS and package SHA-256 verification.
- Persist a per-installation anti-rollback floor for accepted signed metadata.
- Apply ZIP entry count, expanded size, compression ratio, and free-space limits before extraction.
- Stage updates in private directories and back up changed files before applying the update. Restore replaced files and remove newly added files when a copy fails.
- Check install locations before network and staging work. Refuse UNC paths, mapped network drives, and locations the updater cannot write to.
