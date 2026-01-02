#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

CONFIGURATION="Release"
ARCH="arm64 x86_64"
CLEAN=false
SCHEME="aizen"

while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--debug)
            CONFIGURATION="Debug"
            shift
            ;;
        -r|--release)
            CONFIGURATION="Release"
            shift
            ;;
        -n|--nightly)
            SCHEME="aizen nightly"
            shift
            ;;
        -c|--clean)
            CLEAN=true
            shift
            ;;
        --arm64)
            ARCH="arm64"
            shift
            ;;
        --x86_64|--intel)
            ARCH="x86_64"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -d, --debug     Build Debug configuration (default: Release)"
            echo "  -r, --release   Build Release configuration"
            echo "  -n, --nightly   Build nightly version"
            echo "  -c, --clean     Clean before building"
            echo "  --arm64         Build for Apple Silicon only"
            echo "  --x86_64        Build for Intel only"
            echo "  -h, --help      Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                         # Build universal (arm64 + x86_64)"
            echo "  $0 --debug                 # Build Debug universal"
            echo "  $0 --nightly               # Build nightly universal"
            echo "  $0 --arm64                 # Build for Apple Silicon only"
            echo "  $0 --x86_64                # Build for Intel only"
            echo "  $0 --release --clean       # Clean and build Release"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

if [[ "$SCHEME" == "aizen nightly" ]]; then
    VERSION_TYPE="nightly"
    APP_NAME="aizen nightly.app"
else
    VERSION_TYPE="release"
    APP_NAME="aizen.app"
fi

if [[ "$ARCH" == "arm64 x86_64" ]]; then
    ARCH_DISPLAY="universal (arm64 + x86_64)"
else
    ARCH_DISPLAY="$ARCH"
fi

echo -e "${GREEN}=== Building aizen ===${NC}"
echo "Version: $VERSION_TYPE"
echo "Configuration: $CONFIGURATION"
echo "Architecture: $ARCH_DISPLAY"
echo ""

if [ "$CLEAN" = true ]; then
    echo -e "${YELLOW}Cleaning build folder...${NC}"
    xcodebuild clean -scheme "$SCHEME" -configuration "$CONFIGURATION" 2>/dev/null
    echo ""
fi

echo -e "${YELLOW}Building...${NC}"
BUILD_CMD=(xcodebuild -scheme "$SCHEME" -configuration "$CONFIGURATION")
for arch in $ARCH; do
    BUILD_CMD+=(-arch "$arch")
done
BUILD_CMD+=(build)

"${BUILD_CMD[@]}" 2>&1 | grep -E "error:|warning:|BUILD SUCCEEDED|BUILD FAILED" || true

BUILD_STATUS=${PIPESTATUS[0]}
if [ $BUILD_STATUS -eq 0 ]; then
    # Find the most recently modified build
    DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"
    APP_PATH=$(ls -dt "$DERIVED_DATA"/aizen-*/Build/Products/"$CONFIGURATION"/"$APP_NAME" 2>/dev/null | head -1)
    echo ""
    echo -e "${GREEN}Build succeeded${NC}"
    if [ -n "$APP_PATH" ]; then
        echo -e "Output: ${YELLOW}$APP_PATH${NC}"
        echo ""
        echo "To run: open \"$APP_PATH\""
    fi
else
    echo ""
    echo -e "${RED}Build failed${NC}"
    exit 1
fi
