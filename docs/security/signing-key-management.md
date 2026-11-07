# Signing key management

## Trust model

The application's embedded/provisioned ECDSA P-256 public key set is the trust anchor. The update manifest and detached signature are untrusted until the signature verifies against a configured key ID. No key is accepted from the update manifest, `.sig` endpoint, or another unauthenticated URL. Keep private keys outside the repository, build agents, application installs, and runtime component. Do not put private key data in logs or command-line arguments.

## Generation and provisioning

Generate a P-256 key on an offline signing workstation. Store it encrypted at rest with limited custodians and an offline backup. Provision the public `X||Y` key to clients through the application's authenticated release/build channel; never fetch it from the update host. Record its computed key ID alongside its owner, activation date, and status. The key ID is SHA-256 of raw X||Y bytes; the generator prints it as part of signature output.

## Rotation

1. Generate a new key offline and record its key ID.
2. Ship an application release that trusts both old and new public keys.
3. Confirm that installed clients have received the overlap release.
4. Publish metadata signed by the new key ID. Clients reject any ID not in their pre-provisioned trust set.
5. After the supported client population has migrated, release clients that remove the old key.

This implementation does not support key delegation or key updates conveyed by a manifest. Rotation cannot safely reach clients that do not already trust the new key; such clients need an application update through the existing trusted distribution channel.

## Revocation and compromise

If a private key is suspected compromised, stop signing with it, remove/revoke its public key in a new application release distributed through the trusted application channel, generate and provision a replacement key, and review recent signed releases. Since ordinary signed manifests cannot change the trust set, an update server cannot revoke its own signing key. Treat a key compromise as an application release incident; do not publish the replacement key only alongside a new manifest.

The repository contains only public test vectors and code. The private scalar behind the fixed test vector is deliberately a publicly known disposable test key and must never be trusted by production applications.
