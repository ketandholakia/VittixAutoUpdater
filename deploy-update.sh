#!/bin/bash
###############################################################################
# VittixAutoUpdater - Deployment Script
#
# This script automates the build and deployment process for application updates
# using the VittixAutoUpdater component.
# 
# Usage:
#   ./deploy-update.sh <version> <app-name> [options]
#
# Example:
#   ./deploy-update.sh 2.1.5 MyApp --severity critical
#
###############################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default configuration
SERVER_USER="deploy"
SERVER_HOST="updates.example.com"
SERVER_PATH="/var/www/updates"
BUILD_DIR="./build"
RELEASE_DIR="./releases"

# Parse arguments
VERSION=${1:-}
APP_NAME=${2:-}
SEVERITY=${3:-recommended}
MIN_VERSION=${4:-}

# Validate arguments
if [ -z "$VERSION" ] || [ -z "$APP_NAME" ]; then
    echo "Usage: $0 <version> <app-name> [severity] [min-version]"
    echo "Example: $0 2.1.5 MyApp critical 2.0.0"
    exit 1
fi

# Full version with build number
FULL_VERSION="${VERSION}.$(date +%Y%m%d)"
ZIP_FILE="${APP_NAME}_v${VERSION}.zip"
MANIFEST_FILE="manifest.json"

echo -e "${GREEN}=== VittixAutoUpdater Deployment ===${NC}"
echo "Version: $FULL_VERSION"
echo "App: $APP_NAME"
echo "Severity: $SEVERITY"
echo ""

###############################################################################
# Step 1: Build Application
###############################################################################

echo -e "${YELLOW}[1/7]${NC} Building application..."

if [ ! -f "${APP_NAME}.dpr" ]; then
    echo -e "${RED}Error: ${APP_NAME}.dpr not found${NC}"
    exit 1
fi

# Create build directory
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR" || exit

# Build with Delphi compiler (adjust for your compiler)
# Uncomment and modify based on your build system:
# dcc32 -B "../${APP_NAME}.dpr"
# OR for Free Pascal:
# fpc -B "../${APP_NAME}.dpr"
# OR for MSBuild:
# msbuild "../${APP_NAME}.dproj" /p:Configuration=Release

echo -e "${GREEN}✓${NC} Build complete"

###############################################################################
# Step 2: Create Update Package
###############################################################################

echo -e "${YELLOW}[2/7]${NC} Creating update package..."

cd ..
mkdir -p "$RELEASE_DIR"

# Create ZIP with application files
# Customize this based on your application structure
zip -r "${RELEASE_DIR}/${ZIP_FILE}" \
    "${BUILD_DIR}/${APP_NAME}.exe" \
    "${BUILD_DIR}/libs/" \
    -x "*.pdb" "*.map" "*.dcu" "*.o"

echo -e "${GREEN}✓${NC} Package created: ${ZIP_FILE}"

###############################################################################
# Step 3: Calculate Checksum
###############################################################################

echo -e "${YELLOW}[3/7]${NC} Calculating checksum..."

if command -v sha256sum &> /dev/null; then
    CHECKSUM=$(sha256sum "${RELEASE_DIR}/${ZIP_FILE}" | cut -d' ' -f1)
elif command -v shasum &> /dev/null; then
    CHECKSUM=$(shasum -a 256 "${RELEASE_DIR}/${ZIP_FILE}" | cut -d' ' -f1)
else
    echo -e "${RED}Error: sha256sum or shasum not found${NC}"
    exit 1
fi

FILE_SIZE=$(stat -f%z "${RELEASE_DIR}/${ZIP_FILE}" 2>/dev/null || stat -c%s "${RELEASE_DIR}/${ZIP_FILE}")

echo "  Checksum: $CHECKSUM"
echo "  Size: $FILE_SIZE bytes"
echo -e "${GREEN}✓${NC} Checksum calculated"

###############################################################################
# Step 4: Generate Manifest
###############################################################################

echo -e "${YELLOW}[4/7]${NC} Generating manifest..."

# Use Python script to generate manifest
if [ -f "generate_manifest.py" ]; then
    python3 generate_manifest.py \
        --app "$APP_NAME" \
        --version "$FULL_VERSION" \
        --file "${RELEASE_DIR}/${ZIP_FILE}" \
        --url "https://${SERVER_HOST}" \
        --severity "$SEVERITY" \
        --min-version "$MIN_VERSION" \
        --output "${RELEASE_DIR}/${MANIFEST_FILE}"
else
    # Fallback: Manual manifest creation
    cat > "${RELEASE_DIR}/${MANIFEST_FILE}" <<EOF
{
  "${APP_NAME}": {
    "version": "${FULL_VERSION}",
    "download_url": "https://${SERVER_HOST}/releases/${ZIP_FILE}",
    "file_size": ${FILE_SIZE},
    "checksum": "sha256:${CHECKSUM}",
    "release_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "severity": "${SEVERITY}"$([ -n "$MIN_VERSION" ] && echo ",
    \"min_version\": \"${MIN_VERSION}\"" || echo "")
  }
}
EOF
fi

echo -e "${GREEN}✓${NC} Manifest generated"

###############################################################################
# Step 5: Create Release Notes
###############################################################################

echo -e "${YELLOW}[5/7]${NC} Creating release notes..."

cat > "${RELEASE_DIR}/RELEASE_NOTES_v${VERSION}.txt" <<EOF
Release Notes for ${APP_NAME} v${VERSION}
========================================

Released: $(date +%Y-%m-%d)

What's New:
-----------
- [Add your release notes here]

Bug Fixes:
----------
- [Add bug fixes here]

Known Issues:
-------------
- [Add known issues here]

EOF

echo -e "${GREEN}✓${NC} Release notes created"

###############################################################################
# Step 6: Upload to Server
###############################################################################

echo -e "${YELLOW}[6/7]${NC} Uploading to update server..."

# Create remote directory
ssh "${SERVER_USER}@${SERVER_HOST}" "mkdir -p ${SERVER_PATH}/releases"

# Upload ZIP file
echo "  Uploading ${ZIP_FILE}..."
scp "${RELEASE_DIR}/${ZIP_FILE}" \
    "${SERVER_USER}@${SERVER_HOST}:${SERVER_PATH}/releases/"

# Upload manifest
echo "  Uploading manifest..."
scp "${RELEASE_DIR}/${MANIFEST_FILE}" \
    "${SERVER_USER}@${SERVER_HOST}:${SERVER_PATH}/"

# Upload release notes
echo "  Uploading release notes..."
scp "${RELEASE_DIR}/RELEASE_NOTES_v${VERSION}.txt" \
    "${SERVER_USER}@${SERVER_HOST}:${SERVER_PATH}/releases/"

echo -e "${GREEN}✓${NC} Files uploaded"

###############################################################################
# Step 7: Verify Deployment
###############################################################################

echo -e "${YELLOW}[7/7]${NC} Verifying deployment..."

# Check if manifest is accessible
MANIFEST_URL="https://${SERVER_HOST}/manifest.json"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$MANIFEST_URL")

if [ "$HTTP_CODE" -eq 200 ]; then
    echo -e "${GREEN}✓${NC} Manifest accessible at: $MANIFEST_URL"
else
    echo -e "${RED}✗${NC} Manifest not accessible (HTTP $HTTP_CODE)"
    exit 1
fi

# Check if ZIP is accessible
ZIP_URL="https://${SERVER_HOST}/releases/${ZIP_FILE}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$ZIP_URL")

if [ "$HTTP_CODE" -eq 200 ]; then
    echo -e "${GREEN}✓${NC} Update package accessible at: $ZIP_URL"
else
    echo -e "${RED}✗${NC} Update package not accessible (HTTP $HTTP_CODE)"
    exit 1
fi

###############################################################################
# Deployment Complete
###############################################################################

echo ""
echo -e "${GREEN}=== Deployment Complete ===${NC}"
echo ""
echo "Version: $FULL_VERSION"
echo "Severity: $SEVERITY"
echo "Manifest: $MANIFEST_URL"
echo "Download: $ZIP_URL"
echo ""
echo "Next Steps:"
echo "1. Test the update on a staging environment"
echo "2. Monitor user feedback after rollout"
echo "3. Update release notes if needed"
echo ""
echo -e "${GREEN}✓ All done!${NC}"
