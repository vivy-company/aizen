#!/bin/bash
set -euo pipefail

# Build libghostty as universal (arm64 + x86_64) static library.
# Usage: ./scripts/build-libghostty.sh [commit]
#   - commit: ghostty commit/tag/branch (default: main HEAD)

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="${ROOT_DIR}/Vendor/libghostty"
GHOSTTY_REPO="https://github.com/ghostty-org/ghostty"

REF="${1:-}"
if [ -z "${REF}" ]; then
    echo "Fetching ghostty main HEAD..."
    REF="$(git ls-remote "${GHOSTTY_REPO}" HEAD | awk '{print $1}')"
fi

echo "Building libghostty @ ${REF}"

# Check dependencies
for cmd in git zig lipo; do
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

# Patch build.zig to install libs on macOS
perl -0pi -e 's/if \(!config\.target\.result\.os\.tag\.isDarwin\(\)\) \{/if (true) {/' "${WORKDIR}/ghostty/build.zig"

# Patch to link Metal frameworks
perl -0pi -e 's/lib\.linkFramework\("IOSurface"\);/lib.linkFramework("IOSurface");\n    lib.linkFramework("Metal");\n    lib.linkFramework("MetalKit");/g' "${WORKDIR}/ghostty/pkg/macos/build.zig"
perl -0pi -e 's/module\.linkFramework\("IOSurface", \.\{\}\);/module.linkFramework("IOSurface", .{});\n        module.linkFramework("Metal", .{});\n        module.linkFramework("MetalKit", .{});/g' "${WORKDIR}/ghostty/pkg/macos/build.zig"

ZIG_FLAGS=(
    -Dapp-runtime=none
    -Demit-xcframework=false
    -Demit-macos-app=false
    -Demit-exe=false
    -Demit-docs=false
    -Demit-webdata=false
    -Demit-helpgen=false
    -Demit-terminfo=true
    -Demit-termcap=false
    -Demit-themes=false
    -Doptimize=ReleaseFast
    -Dstrip
)

build_arch() {
    local arch="$1"
    local outdir="${WORKDIR}/zig-out-${arch}"
    echo "Building for ${arch}..." >&2
    (cd "${WORKDIR}/ghostty" && zig build "${ZIG_FLAGS[@]}" -Dtarget="${arch}-macos" -p "${outdir}")
    if [ ! -f "${outdir}/lib/libghostty.a" ]; then
        echo "Error: build failed - ${outdir}/lib/libghostty.a not found" >&2
        exit 1
    fi
    echo "${outdir}/lib/libghostty.a"
}

ARM64_LIB="$(build_arch aarch64)"
X64_LIB="$(build_arch x86_64)"

# Create universal binary
echo "Creating universal binary..."
mkdir -p "${VENDOR_DIR}/lib" "${VENDOR_DIR}/include"
lipo -create "${ARM64_LIB}" "${X64_LIB}" -output "${VENDOR_DIR}/lib/libghostty.a"

# Copy headers
if [ -d "${WORKDIR}/ghostty/include" ]; then
    rsync -a --delete "${WORKDIR}/ghostty/include/" "${VENDOR_DIR}/include/"
fi

# Record version
printf "%s\n" "${REF}" > "${VENDOR_DIR}/VERSION"

echo "Done: $(lipo -info "${VENDOR_DIR}/lib/libghostty.a")"
