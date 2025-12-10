#!/bin/bash
set -euo pipefail

# Build a universal archive and DMG without signing. Intended for local dry-runs
# and for the CI release workflow before signing/notarization.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MARKETING_VERSION="${MARKETING_VERSION:-${1:-0.0.0}}"
BUILD_VERSION="${BUILD_VERSION:-${2:-0}}"
RELEASE_NOTES="${RELEASE_NOTES:-${3:-Dry run}}"
SCHEME="${SCHEME:-aizen}"
CONFIGURATION="${CONFIGURATION:-Release}"

cd "${ROOT_DIR}"

# Ensure all tools are present (zig, swiftlint, create-dmg, awscli, sparkle)
if [ "${SKIP_INSTALL_DEPS:-0}" != "1" ]; then
  ./scripts/install-deps.sh
fi

# Clean and archive universal (arm64 + x86_64) without signing
xcodebuild clean archive \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -archivePath build/aizen.xcarchive \
  -arch arm64 -arch x86_64 \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

# Stage app for DMG
mkdir -p build/dmg
cp -R build/aizen.xcarchive/Products/Applications/aizen.app build/dmg/

# Create DMG (create-dmg may exit 2 even on success; tolerate that but ensure file exists)
create-dmg \
  --volname "aizen" \
  --window-pos 200 120 \
  --window-size 800 400 \
  --icon-size 100 \
  --icon "aizen.app" 200 190 \
  --hide-extension "aizen.app" \
  --app-drop-link 600 185 \
  "build/Aizen-${MARKETING_VERSION}.dmg" \
  "build/dmg/" || true

if [ ! -f "build/Aizen-${MARKETING_VERSION}.dmg" ]; then
  echo "Error: DMG creation failed" >&2
  exit 1
fi

echo "DMG ready: build/Aizen-${MARKETING_VERSION}.dmg"
echo "App staged at: build/dmg/aizen.app"
echo "Marketing version: ${MARKETING_VERSION} | Build version: ${BUILD_VERSION} | Notes: ${RELEASE_NOTES}"
