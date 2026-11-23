#!/usr/bin/env python3
"""
VittixAutoUpdater - Manifest Generator

This script generates update manifests for the VittixAutoUpdater component.
It calculates checksums, file sizes, and creates properly formatted JSON.

Usage:
    python generate_manifest.py --app MyApp --version 2.1.5 --file MyApp.zip
"""

import json
import hashlib
import os
import argparse
import base64
import getpass
from datetime import datetime, timezone
import re

def load_signing_key(path):
    try:
        from cryptography.hazmat.primitives.serialization import load_pem_private_key
    except ImportError as exc:
        raise RuntimeError("Signing requires: python -m pip install cryptography") from exc
    with open(path, 'rb') as key_file:
        key_bytes = key_file.read()
    try:
        return load_pem_private_key(key_bytes, password=None)
    except TypeError:
        password = getpass.getpass('Signing key passphrase: ').encode('utf-8')
        return load_pem_private_key(key_bytes, password=password)

def public_key_xy_hex(private_key):
    from cryptography.hazmat.primitives.asymmetric import ec
    if not isinstance(private_key, ec.EllipticCurvePrivateKey) or \
            not isinstance(private_key.curve, ec.SECP256R1):
        raise ValueError("Signing key must be ECDSA P-256 (prime256v1)")
    numbers = private_key.public_key().public_numbers()
    return f"{numbers.x:064x}{numbers.y:064x}"

def signing_key_id(public_key_hex):
    """Stable identifier: lowercase SHA-256 hex of the raw 64-byte X||Y key."""
    public_bytes = bytes.fromhex(public_key_hex)
    if len(public_bytes) != 64:
        raise ValueError("Public key must contain exactly 64 X||Y bytes")
    return hashlib.sha256(public_bytes).hexdigest()

def sign_manifest_file(manifest_file, private_key_path):
    try:
        from cryptography.hazmat.primitives import hashes
        from cryptography.hazmat.primitives.asymmetric import ec
        from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
    except ImportError as exc:
        raise RuntimeError("Signing requires: python -m pip install cryptography") from exc

    private_key = load_signing_key(private_key_path)
    if not isinstance(private_key, ec.EllipticCurvePrivateKey) or \
            not isinstance(private_key.curve, ec.SECP256R1):
        raise ValueError("Signing key must be ECDSA P-256 (prime256v1)")
    with open(manifest_file, 'rb') as manifest:
        manifest_bytes = manifest.read()
    der_signature = private_key.sign(manifest_bytes, ec.ECDSA(hashes.SHA256()))
    r, s = decode_dss_signature(der_signature)
    raw_signature = r.to_bytes(32, 'big') + s.to_bytes(32, 'big')
    key_id = signing_key_id(public_key_xy_hex(private_key))
    signature_file = manifest_file + '.sig'
    with open(signature_file, 'wb') as output:
        envelope = (f"VAU-ECDSA-P256-SHA256-v1:{key_id}:".encode('ascii')
                    + base64.b64encode(raw_signature) + b'\n')
        output.write(envelope)
    print(f"  Signature: {signature_file} (ECDSA P-256/SHA-256, key {key_id})")
    print(f"  Public key (provision independently): {public_key_xy_hex(private_key)}")

def calculate_sha256(filepath):
    """Calculate SHA256 checksum of a file"""
    sha256 = hashlib.sha256()
    
    with open(filepath, 'rb') as f:
        while True:
            chunk = f.read(8192)
            if not chunk:
                break
            sha256.update(chunk)
    
    return sha256.hexdigest()

def get_file_size(filepath):
    """Get file size in bytes"""
    return os.path.getsize(filepath)

def validate_version(version, field_name):
    """Validate the decimal version components accepted by the Delphi updater."""
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,3}", version):
        raise ValueError(f"{field_name} must have one to four decimal parts")
    for part in version.split("."):
        significant = part.lstrip("0") or "0"
        if len(significant) > 5 or int(significant) > 65535:
            raise ValueError(f"{field_name} parts must be between 0 and 65535")


def generate_manifest(app_name, version, zip_file, base_url, severity='recommended', 
                     release_notes='', min_version=''):
    """
    Generate update manifest entry
    
    Args:
        app_name: Application name (e.g., 'MyApp')
        version: Version string (e.g., '2.1.5.100')
        zip_file: Path to update ZIP file
        base_url: Base URL for downloads (e.g., 'https://cdn.example.com')
        severity: Update severity ('optional', 'recommended', or 'critical')
        release_notes: Release notes text
        min_version: Minimum version that can update to this version
    
    Returns:
        Dictionary with manifest data
    """
    
    validate_version(version, "Version")
    if min_version:
        validate_version(min_version, "Minimum version")

    if not os.path.exists(zip_file):
        raise FileNotFoundError(f"Update file not found: {zip_file}")
    
    # Calculate checksum
    checksum = calculate_sha256(zip_file)
    
    # Get file size
    file_size = get_file_size(zip_file)
    
    # Build download URL
    filename = os.path.basename(zip_file)
    download_url = f"{base_url.rstrip('/')}/releases/{filename}"
    
    # Create manifest entry
    issued_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace('+00:00', 'Z')
    manifest_entry = {
        'version': version,
        'download_url': download_url,
        'file_size': file_size,
        'checksum': f'sha256:{checksum}',
        'issued_at': issued_at,
        'release_date': issued_at,
        'severity': severity
    }
    
    # Optional fields
    if release_notes:
        manifest_entry['release_notes'] = release_notes
    
    if min_version:
        manifest_entry['min_version'] = min_version
    
    return {app_name: manifest_entry}

def update_manifest_file(manifest_file, app_name, manifest_entry):
    """
    Update existing manifest file or create new one
    
    Args:
        manifest_file: Path to manifest.json
        app_name: Application name
        manifest_entry: New manifest entry dict
    """
    
    # Load existing manifest if it exists
    if os.path.exists(manifest_file):
        with open(manifest_file, 'r', encoding='utf-8') as f:
            manifest = json.load(f)
    else:
        manifest = {}
    
    # Update entry
    manifest.update(manifest_entry)
    
    # Save manifest
    with open(manifest_file, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(manifest, f, indent=2, sort_keys=False, ensure_ascii=False)
    
    print(f"Updated {manifest_file}")

def main():
    parser = argparse.ArgumentParser(description='Generate update manifest')
    
    parser.add_argument('--app', help='Application name')
    parser.add_argument('--version', help='Version string (e.g., 2.1.5.100)')
    parser.add_argument('--file', help='Path to update ZIP file')
    parser.add_argument('--url', default='https://updates.example.com', 
                       help='Base URL for downloads')
    parser.add_argument('--severity', default='recommended', 
                       choices=['optional', 'recommended', 'critical'],
                       help='Update severity')
    parser.add_argument('--notes', default='', help='Release notes')
    parser.add_argument('--min-version', default='', help='Minimum version requirement')
    parser.add_argument('--output', default='manifest.json', help='Output manifest file')
    parser.add_argument('--signing-key', help='PEM ECDSA P-256 private key; never distribute')
    parser.add_argument('--print-public-key', action='store_true',
                        help='Print the configured-format public key and exit')
    
    args = parser.parse_args()

    if args.print_public_key:
        if not args.signing_key:
            parser.error('--print-public-key requires --signing-key')
        private_key = load_signing_key(args.signing_key)
        print(public_key_xy_hex(private_key))
        print('Key ID: ' + signing_key_id(public_key_xy_hex(private_key)))
        return

    missing = [name for name in ('app', 'version', 'file') if not getattr(args, name)]
    if missing:
        parser.error('required for manifest generation: ' + ', '.join('--' + name for name in missing))
    
    print(f"Generating manifest for {args.app} v{args.version}...")
    print(f"  File: {args.file}")
    
    # Generate manifest
    try:
        manifest_entry = generate_manifest(
            args.app,
            args.version,
            args.file,
            args.url,
            args.severity,
            args.notes,
            args.min_version
        )
    except ValueError as error:
        parser.error(str(error))

    # Display info
    entry = manifest_entry[args.app]
    print(f"  Size: {entry['file_size']:,} bytes")
    print(f"  Checksum: {entry['checksum']}")
    print(f"  Severity: {entry['severity']}")
    
    # Update manifest file
    update_manifest_file(args.output, args.app, manifest_entry)

    if args.signing_key:
        sign_manifest_file(args.output, args.signing_key)
    else:
        print("WARNING: manifest was not signed; clients requiring signatures will reject it")
    
    print(f"\nManifest generation complete!")
    print(f"  Upload {args.file} to: {entry['download_url']}")
    print(f"  Upload {args.output} to your update server")

if __name__ == '__main__':
    main()
