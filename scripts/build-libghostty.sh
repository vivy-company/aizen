#!/bin/bash
set -euo pipefail

# Build GhosttyKit as a macOS xcframework.
# Usage: ./scripts/build-libghostty.sh [commit]
#   - commit: ghostty commit/tag/branch
#             default: Vendor/libghostty/VERSION when present, otherwise main HEAD

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="${ROOT_DIR}/Vendor/libghostty"
GHOSTTY_REPO="https://github.com/ghostty-org/ghostty"

REF="${1:-}"
if [ -z "${REF}" ] && [ -f "${VENDOR_DIR}/VERSION" ]; then
    REF="$(tr -d '\r\n' < "${VENDOR_DIR}/VERSION")"
    echo "Using pinned ghostty version from Vendor/libghostty/VERSION: ${REF}"
fi

if [ -z "${REF}" ]; then
    echo "No pinned ghostty version found, fetching ghostty main HEAD..."
    REF="$(git ls-remote "${GHOSTTY_REPO}" HEAD | awk '{print $1}')"
fi

echo "Building GhosttyKit @ ${REF}"

# Check dependencies
for cmd in git zig; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: $cmd required (try 'brew install $cmd')" >&2
        exit 1
    fi
done

# Setup temp dir
WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

# Clone ghostty
echo "Cloning ghostty..."
git clone --filter=blob:none --no-checkout --depth 1 "${GHOSTTY_REPO}" "${WORKDIR}/ghostty"
(cd "${WORKDIR}/ghostty" && git fetch --depth 1 origin "${REF}" && git checkout FETCH_HEAD)

# Patch bundle ID to use Aizen's instead of Ghostty's so the embedded core
# doesn't collide with the standalone Ghostty app's config/runtime identifiers.
sed -i '' 's/com\.mitchellh\.ghostty/win.aizen.app/g' "${WORKDIR}/ghostty/src/build_config.zig"

ZIG_FLAGS=(
    -Demit-macos-app=false
    -Demit-exe=false
    -Demit-docs=false
    -Demit-webdata=false
    -Demit-helpgen=false
    -Demit-terminfo=true
    -Demit-termcap=false
    -Demit-themes=false
    -Dxcframework-target=native
    -Doptimize=ReleaseFast
    -Dstrip
)

OUTDIR="${WORKDIR}/ghostty/macos/GhosttyKit.xcframework"
echo "Building native GhosttyKit.xcframework..."
(cd "${WORKDIR}/ghostty" && zig build "${ZIG_FLAGS[@]}")
if [ ! -d "${OUTDIR}" ]; then
    echo "Error: build failed - ${OUTDIR} not found" >&2
    exit 1
fi

# Copy built framework
mkdir -p "${VENDOR_DIR}"
rm -rf "${VENDOR_DIR}/GhosttyKit.xcframework" "${VENDOR_DIR}/include" "${VENDOR_DIR}/lib"
rsync -a "${OUTDIR}/" "${VENDOR_DIR}/GhosttyKit.xcframework/"

ARCHIVE_PATH="${VENDOR_DIR}/GhosttyKit.xcframework/macos-arm64/libghostty-fat.a"
if [ -f "${ARCHIVE_PATH}" ]; then
    echo "Stripping static archive for GitHub size limits..."
    chmod u+w "${ARCHIVE_PATH}"
    strip -S -x "${ARCHIVE_PATH}"
    ranlib "${ARCHIVE_PATH}"
    ls -lh "${ARCHIVE_PATH}"
fi

# Record version
printf "%s\n" "${REF}" > "${VENDOR_DIR}/VERSION"

echo "Done: built GhosttyKit.xcframework"
