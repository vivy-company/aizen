#!/bin/bash
set -e

# Script to generate appcast.xml for Sparkle updates
# This script should be run after building and signing a new release
# Usage: ./generate-appcast.sh <dmg-path> <build-version> <marketing-version> [release-notes] [minimum-system-version]

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
    echo "Error: Missing required arguments"
    echo "Usage: $0 <dmg-path> <build-version> <marketing-version> [release-notes] [minimum-system-version]"
    echo "Example: $0 build/Aizen-1.0.1.dmg 10001 1.0.1 'Bug fixes and improvements' 14.0"
    exit 1
fi

DMG_PATH="$1"
BUILD_VERSION="$2"
MARKETING_VERSION="$3"
RELEASE_NOTES="${4:-New release}"
MIN_SYSTEM_VERSION="${5:-${SPARKLE_MIN_SYSTEM_VERSION:-}}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APPCAST_FILE="$PROJECT_ROOT/appcast.xml"
PRIVATE_KEY="${SPARKLE_PRIVATE_KEY_FILE:-$PROJECT_ROOT/.sparkle-keys/eddsa_priv.pem}"

resolve_min_system_version() {
    if [ -n "$MIN_SYSTEM_VERSION" ]; then
        echo "$MIN_SYSTEM_VERSION"
        return 0
    fi

    local derived_info_plist=""
    local dmg_dir
    dmg_dir="$(dirname "$DMG_PATH")"

    for candidate in \
        "$dmg_dir/dmg"/*.app/Contents/Info.plist \
        "$PROJECT_ROOT/build/dmg"/*.app/Contents/Info.plist \
        "$PROJECT_ROOT/aizen/Info.plist" \
        "$PROJECT_ROOT/aizen nightly-Info.plist"
    do
        if [ -f "$candidate" ]; then
            derived_info_plist="$candidate"
            break
        fi
    done

    if [ -z "$derived_info_plist" ]; then
        return 1
    fi

    /usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$derived_info_plist" 2>/dev/null
}

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

# Get signature for the DMG
if [ -n "$SPARKLE_SIGNATURE" ]; then
    echo "Using pre-generated signature from environment..."
    SIGNATURE="$SPARKLE_SIGNATURE"
else
    echo "Generating EdDSA signature for DMG..."

    # Find sign_update binary
    SIGN_UPDATE=""
    if command -v sign_update &> /dev/null; then
        SIGN_UPDATE="sign_update"
    else
        # Try to find in Homebrew Sparkle installation
        SIGN_UPDATE=$(find /opt/homebrew/Caskroom/sparkle -name sign_update -type f 2>/dev/null | grep -v old_dsa | grep -v dSYM | head -1)
    fi

    if [ -z "$SIGN_UPDATE" ]; then
        echo "Error: sign_update tool not found"
        echo "Please install Sparkle: brew install sparkle"
        exit 1
    fi

    SIGNATURE=$("$SIGN_UPDATE" --ed-key-file "$PRIVATE_KEY" -p "$DMG_PATH" 2>/dev/null || echo "")

    if [ -z "$SIGNATURE" ]; then
        echo "Error: Failed to generate EdDSA signature for DMG"
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
MIN_SYSTEM_VERSION="$(resolve_min_system_version || true)"

if [ -z "$MIN_SYSTEM_VERSION" ]; then
    echo "Error: Failed to determine minimum system version for appcast"
    echo "Pass it as the 5th argument or set SPARKLE_MIN_SYSTEM_VERSION"
    exit 1
fi

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
        <sparkle:minimumSystemVersion>$MIN_SYSTEM_VERSION</sparkle:minimumSystemVersion>
    </item>"

# Insert the new item into appcast (before closing </channel>)
perl -i -pe "s|</channel>|$ITEM_TEMPLATE\n    </channel>|" "$APPCAST_FILE"

echo "✅ Appcast generated successfully!"
echo ""
echo "Appcast location: $APPCAST_FILE"
echo "Download URL: $DOWNLOAD_URL"
echo "Build Version: $BUILD_VERSION"
echo "Marketing Version: $MARKETING_VERSION"
echo "Minimum System Version: $MIN_SYSTEM_VERSION"
echo "Signature: $SIGNATURE"
echo ""
echo "Next steps:"
echo "  1. Upload appcast.xml to R2 bucket root"
echo "  2. Upload DMG to R2 bucket as Aizen-$MARKETING_VERSION.dmg"
echo "  3. Set SPARKLE_FEED_URL in Xcode to point to appcast.xml on R2"
