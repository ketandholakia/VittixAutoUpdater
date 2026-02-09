# VittixAutoUpdater

**Version:** 1.0.0  
**Author:** Vittix  
**License:** MIT  
**Language:** Delphi/Pascal (compatible with Free Pascal)  

## Project Structure

```
VittixAutoUpdater/
├── Source/
│   ├── VittixAutoUpdater.Types.pas       - Core types and version management
│   ├── VittixAutoUpdater.Network.pas     - HTTP operations and downloads
│   └── VittixAutoUpdater.Engine.pas      - Main update orchestration engine
│
├── Demo/
│   └── VittixAutoUpdaterDemo.dpr         - Console demo application
│
├── Tools/
│   ├── generate_manifest.py              - Python manifest generator
│   └── deploy-update.sh                  - Bash deployment script
│
├── Documentation/
│   ├── VittixAutoUpdater_Design.md       - Complete architecture design
│   └── README.md                          - Usage guide and examples
│
└── Examples/
    └── manifest.json                      - Sample update manifest
```

## Quick Installation

1. Add the three `.pas` files to your Delphi/FPC project
2. Add to uses clause: `VittixAutoUpdater.Types, VittixAutoUpdater.Engine`
3. Configure and use as shown in README.md

## Compatibility

- ✅ Delphi 10.x and newer
- ✅ Free Pascal (FPC) with -Mdelphi mode
- ✅ Windows, macOS, Linux

## Features

- Semantic versioning
- Multi-mirror fallback URLs
- SHA256 checksum verification
- Progress tracking
- Automatic retry with exponential backoff
- Safe file replacement
- Rollback mechanism
- Async operations
- Beta/stable channels

## Dependencies

### Delphi
- System.Net.HttpClient
- System.Net.URLClient
- System.Hash
- System.JSON
- System.Zip

### Free Pascal
- fphttpclient (requires -dUseFPHTTPClient define)
- Alternative: Use Indy or Synapse

## Support

For issues, questions, or contributions, please refer to the documentation.

---

**VittixAutoUpdater** - Making software updates simple and reliable.
