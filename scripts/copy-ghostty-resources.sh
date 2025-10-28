#!/bin/bash

# Copy Ghostty resources to app bundle with proper directory structure

set -e

# Build paths from environment variables provided by Xcode
BUNDLE_RESOURCES="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Resources"
SOURCE_GHOSTTY="${SRCROOT}/aizen/Resources/ghostty"
SOURCE_TERMINFO="/Applications/Ghostty.app/Contents/Resources/terminfo"

echo "Bundle resources path: ${BUNDLE_RESOURCES}"

# Remove any flattened ghostty files
rm -f "${BUNDLE_RESOURCES}/ghostty"*

# Create ghostty directory
mkdir -p "${BUNDLE_RESOURCES}/ghostty"

# Copy ghostty resources (shell-integration, doc, themes)
if [ -d "${SOURCE_GHOSTTY}" ]; then
    cp -r "${SOURCE_GHOSTTY}"/* "${BUNDLE_RESOURCES}/ghostty/"
    echo "Copied Ghostty resources to bundle"
fi

# Copy terminfo for sentinel file detection
if [ -d "${SOURCE_TERMINFO}" ]; then
    cp -r "${SOURCE_TERMINFO}" "${BUNDLE_RESOURCES}/"
    echo "Copied terminfo to bundle"
fi

echo "Ghostty resources bundle structure complete"
