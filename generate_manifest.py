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
from datetime import datetime

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
    manifest_entry = {
        'version': version,
        'download_url': download_url,
        'file_size': file_size,
        'checksum': f'sha256:{checksum}',
        'release_date': datetime.utcnow().isoformat() + 'Z',
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
        with open(manifest_file, 'r') as f:
            manifest = json.load(f)
    else:
        manifest = {}
    
    # Update entry
    manifest.update(manifest_entry)
    
    # Save manifest
    with open(manifest_file, 'w') as f:
        json.dump(manifest, f, indent=2, sort_keys=False)
    
    print(f"✓ Updated {manifest_file}")

def main():
    parser = argparse.ArgumentParser(description='Generate update manifest')
    
    parser.add_argument('--app', required=True, help='Application name')
    parser.add_argument('--version', required=True, help='Version string (e.g., 2.1.5.100)')
    parser.add_argument('--file', required=True, help='Path to update ZIP file')
    parser.add_argument('--url', default='https://updates.example.com', 
                       help='Base URL for downloads')
    parser.add_argument('--severity', default='recommended', 
                       choices=['optional', 'recommended', 'critical'],
                       help='Update severity')
    parser.add_argument('--notes', default='', help='Release notes')
    parser.add_argument('--min-version', default='', help='Minimum version requirement')
    parser.add_argument('--output', default='manifest.json', help='Output manifest file')
    
    args = parser.parse_args()
    
    print(f"Generating manifest for {args.app} v{args.version}...")
    print(f"  File: {args.file}")
    
    # Generate manifest
    manifest_entry = generate_manifest(
        args.app,
        args.version,
        args.file,
        args.url,
        args.severity,
        args.notes,
        args.min_version
    )
    
    # Display info
    entry = manifest_entry[args.app]
    print(f"  Size: {entry['file_size']:,} bytes")
    print(f"  Checksum: {entry['checksum']}")
    print(f"  Severity: {entry['severity']}")
    
    # Update manifest file
    update_manifest_file(args.output, args.app, manifest_entry)
    
    print(f"\n✓ Manifest generation complete!")
    print(f"  Upload {args.file} to: {entry['download_url']}")
    print(f"  Upload {args.output} to your update server")

if __name__ == '__main__':
    main()
