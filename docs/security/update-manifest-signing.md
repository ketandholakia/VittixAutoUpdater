# Update manifest signing

## Protocol

* Algorithm: ECDSA over NIST P-256 (`prime256v1`) with SHA-256.
* Trusted key representation: 128 lowercase/uppercase hex characters containing the 32-byte big-endian X coordinate followed by the 32-byte big-endian Y coordinate (`X||Y`). It is provisioned in application configuration using `ManifestPublicKey` or `ManifestTrustedPublicKeys`.
* Key ID: lowercase hexadecimal SHA-256 of the 64 raw `X||Y` bytes. IDs are deterministic; unknown IDs are rejected.
* Detached signature: `<manifest path>.sig`, UTF-8/ASCII text in the form `VAU-ECDSA-P256-SHA256-v1:<64-hex-key-id>:<base64>`. Base64 decodes to exactly 64 bytes: big-endian 32-byte `r` followed by big-endian 32-byte `s`.
* Signed bytes: every byte in the manifest file as published, including whitespace, encoding marker, and final newline if present. The generator reads the file as binary after JSON serialization and signs those bytes. The verifier signs/verifies the downloaded response bytes without decoding or reserializing JSON.
* Canonicalization: none. The exact byte file is the canonical artifact; changing JSON formatting requires creating a new detached signature.
* Signature envelope and `key-id` are not included in the signed bytes; the selected ID must resolve to a key already provisioned in the client. The manifest cannot add or replace keys.

The verifier checks a 1 MiB manifest body limit, verifies the detached signature and trusted key, then decodes UTF-8 and parses required fields. Signed mode requires `issued_at`, rejects invalid/future timestamps, and applies `MaxManifestAgeDays`. Package download is a separate later engine operation; a failed check never returns `ucrUpdateAvailable`.

A UTF-8 BOM is part of the signed bytes when present. The client verifies the
signature before removing the BOM for JSON parsing. For a manifest at
`https://updates.example.test/manifest.json?channel=stable`, serve the signature
at `https://updates.example.test/manifest.json.sig?channel=stable`. Redirects
retain only the final response body for verification and parsing.


## Signed test example

The repository includes a [signed sample manifest](../../manifest.json), its
[detached signature](../../manifest.json.sig), a [test public key](../../tests/vectors/manifest-test-public-key.txt)
in `X||Y` format, and the [payload fixture](../../tests/vectors/sample-payload.zip)
whose SHA-256 and size appear in the manifest. The Python generator signed the
sample with a disposable P-256 key. Trust the public key only in tests.

The sample demonstrates exact-byte signature verification and the manifest
format. Its reserved `.test` URL and data-only ZIP are fixture inputs. For a
live test, use a fresh signed manifest with your own disposable key, test HTTPS
endpoint, and an installable test payload. The sample's `issued_at` will age out
under the updater's freshness policy.

## Developer workflow

1. Install the Python `cryptography` package on an offline signing workstation.
2. Generate a P-256 private key outside the source tree. For OpenSSL, use `openssl ecparam -name prime256v1 -genkey -noout -aes256 -out update-signing-private.pem`; keep the encrypted key on offline protected storage and restrict access. The command prompts for a passphrase.
3. Obtain the public key with `python generate_manifest.py --signing-key update-signing-private.pem --print-public-key`. The tool prompts for encrypted key passphrase when needed. Provision the printed `X||Y` value into the shipped application's `ManifestPublicKey` or trusted key array through a signed build/configuration process independent of the update service.
4. Build the update ZIP and generate/sign the manifest:

   ```powershell
   python generate_manifest.py --app MyApp --version 2.4.0.0 --file .\MyApp.zip --url https://updates.example.com --output .\manifest.json --signing-key E:\OfflineKeys\update-signing-private.pem
   ```

5. Publish the package at the manifest `download_url`, then publish `manifest.json` and `manifest.json.sig` at the configured manifest URL and its `.sig` sibling. Keep both files immutable for a release.
6. Configure the application before checking updates:

   ```pascal
   Config := TUpdaterConfig.Default;
   Config.AppName := 'MyApp';
   Config.ManifestUrls := ['https://updates.example.com/manifest.json'];
   Config.ManifestPublicKey := '<provisioned 128-character X||Y key>';
   // Signed mode is already enabled by Default.
   ```

7. Validate the generated `.sig` format and test a release using the disposable vectors in `tests/vectors/manifest-signature-vector.json`. Do not use a production private key in tests.

## Signing a manifest saved by the GUI

The GUI writes a whole-second UTC `issued_at` timestamp and provides a
**Copy signing command** button after save. Run the command against the saved
manifest from a trusted signing environment.

```powershell
python generate_manifest.py --signing-key 'C:\path\to\private-key.pem' --sign-existing 'C:\path\to\manifest.json'
```

The CLI creates `manifest.json.sig` alongside the manifest and preserves the
original file bytes. Re-sign after changing the JSON. The GUI warns about missing
`issued_at` or a missing detached signature on a saved file. The updater
performs cryptographic verification at fetch time.


## Migration and compatibility

Existing detached signatures containing only Base64 raw signature bytes are rejected. Regenerate the `.sig` file using the versioned envelope. Existing applications must set a trusted key; checks fail closed without one. `ManifestPublicKey` remains supported. For rotation, provision both old and new public keys in `ManifestTrustedPublicKeys` before the first release signed by the new key. `AllowInsecureUnsignedManifests` is an explicit migration-only escape hatch; it must remain `False` in production.

Adding fields to public `TUpdaterConfig` changes its record size. Rebuild applications and packages from source; this is not binary-compatible with an already compiled runtime package/application.
