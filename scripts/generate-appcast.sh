#!/bin/bash
set -e

# Script to generate appcast.xml for Sparkle updates
# This script should be run after building and signing a new release
# Usage: ./generate-appcast.sh <dmg-path> <build-version> <marketing-version> <release-notes>

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
    echo "Error: Missing required arguments"
    echo "Usage: $0 <dmg-path> <build-version> <marketing-version> [release-notes]"
    echo "Example: $0 build/Aizen-1.0.1.dmg 10001 1.0.1 'Bug fixes and improvements'"
    exit 1
fi

DMG_PATH="$1"
BUILD_VERSION="$2"
MARKETING_VERSION="$3"
RELEASE_NOTES="${4:-New release}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APPCAST_FILE="$PROJECT_ROOT/appcast.xml"
PRIVATE_KEY="${SPARKLE_PRIVATE_KEY_FILE:-$PROJECT_ROOT/.sparkle-keys/eddsa_priv.pem}"

# Check if DMG exists
if [ ! -f "$DMG_PATH" ]; then
    echo "Error: DMG file not found at $DMG_PATH"
    exit 1
fi

# Check if private key exists
if [ ! -f "$PRIVATE_KEY" ]; then
    echo "Error: Private key not found at $PRIVATE_KEY"
    echo ""
    echo "Please run ./scripts/generate-sparkle-keys.sh first"
    echo "Or set SPARKLE_PRIVATE_KEY_FILE environment variable"
    exit 1
fi

echo "Generating appcast for version $MARKETING_VERSION (build $BUILD_VERSION)..."

# Get DMG file size
DMG_SIZE=$(stat -f%z "$DMG_PATH")

# Sign the DMG with EdDSA key
echo "Signing DMG..."
SIGNATURE=$(sign_update "$DMG_PATH" "$PRIVATE_KEY" 2>/dev/null || echo "")

if [ -z "$SIGNATURE" ]; then
    echo "Error: Failed to sign DMG"
    echo "Trying alternative signing method..."

    # Alternative: use openssl directly if sign_update fails
    if command -v openssl &> /dev/null; then
        SIGNATURE=$(openssl dgst -sha256 -sign "$PRIVATE_KEY" "$DMG_PATH" | base64)
    else
        echo "Error: Could not sign the update"
        exit 1
    fi
fi

# Determine R2 or download URL
# In CI, this will be set by the workflow
if [ -z "$R2_PUBLIC_URL" ]; then
    echo "Error: R2_PUBLIC_URL environment variable not set"
    exit 1
fi
DOWNLOAD_URL="${R2_PUBLIC_URL}/Aizen-${MARKETING_VERSION}.dmg"

# Create or update appcast.xml
if [ ! -f "$APPCAST_FILE" ]; then
    echo "Creating new appcast.xml..."
    cat > "$APPCAST_FILE" << EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>Aizen Updates</title>
        <description>Updates for Aizen</description>
        <language>en</language>
    </channel>
</rss>
EOF
fi

# Add new item to appcast
# Note: In production, use Sparkle's generate_appcast tool with a releases directory
# For now, we'll create a basic entry

ITEM_TEMPLATE="
    <item>
        <title>Version $MARKETING_VERSION</title>
        <description><![CDATA[$RELEASE_NOTES]]></description>
        <pubDate>$(date -R)</pubDate>
        <sparkle:version>$BUILD_VERSION</sparkle:version>
        <sparkle:shortVersionString>$MARKETING_VERSION</sparkle:shortVersionString>
        <enclosure url=\"$DOWNLOAD_URL\"
                   length=\"$DMG_SIZE\"
                   type=\"application/octet-stream\"
                   sparkle:edSignature=\"$SIGNATURE\" />
        <sparkle:minimumSystemVersion>13.5</sparkle:minimumSystemVersion>
    </item>"

# Insert the new item into appcast (before closing </channel>)
perl -i -pe "s|</channel>|$ITEM_TEMPLATE\n    </channel>|" "$APPCAST_FILE"

echo "✅ Appcast generated successfully!"
echo ""
echo "Appcast location: $APPCAST_FILE"
echo "Download URL: $DOWNLOAD_URL"
echo "Build Version: $BUILD_VERSION"
echo "Marketing Version: $MARKETING_VERSION"
echo "Signature: $SIGNATURE"
echo ""
echo "Next steps:"
echo "  1. Upload appcast.xml to R2 bucket root"
echo "  2. Upload DMG to R2 bucket as Aizen-$VERSION.dmg"
echo "  3. Set SPARKLE_FEED_URL in Xcode to point to appcast.xml on R2"
