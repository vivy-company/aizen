#!/usr/bin/env bash
set -euo pipefail

FFF_REPO_URL="https://github.com/dmtrKovalenko/fff.nvim"
FFF_COMMIT="8298260c64e2bb517fd6624362673c64e0a05848"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SRCROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
VENDOR_LIB_DIR="${PROJECT_ROOT}/Vendor/fff-c/lib"
VENDOR_DYLIB="${VENDOR_LIB_DIR}/libfff_c.dylib"

# Xcode run scripts do not inherit the interactive shell PATH, so Cargo installed
# through rustup is usually invisible unless we add the standard locations here.
if [ -n "${HOME:-}" ]; then
    export PATH="${HOME}/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:${PATH:-/usr/bin:/bin}"
else
    export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH:-/usr/bin:/bin}"
fi

copy_to_app_bundle() {
    local source_dylib="$1"

    if [ -z "${BUILT_PRODUCTS_DIR:-}" ] || [ -z "${PRODUCT_NAME:-}" ]; then
        return 0
    fi

    local frameworks_dir="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Frameworks"
    mkdir -p "${frameworks_dir}"
    cp "${source_dylib}" "${frameworks_dir}/libfff_c.dylib"

    if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ] && [ "${CODE_SIGNING_ALLOWED:-NO}" = "YES" ]; then
        codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --timestamp=none "${frameworks_dir}/libfff_c.dylib"
    fi
}

use_vendored_dylib() {
    local reason="$1"

    if [ -f "${VENDOR_DYLIB}" ]; then
        echo "${reason}; using vendored libfff_c.dylib" >&2
        copy_to_app_bundle "${VENDOR_DYLIB}"
        exit 0
    fi

    echo "error: ${reason}, and ${VENDOR_DYLIB} does not exist" >&2
    exit 1
}

if [ "${AIZEN_REBUILD_FFF_C:-0}" != "1" ]; then
    use_vendored_dylib "AIZEN_REBUILD_FFF_C is not set"
fi

if ! command -v cargo >/dev/null 2>&1; then
    use_vendored_dylib "cargo is not installed"
fi

if ! command -v git >/dev/null 2>&1; then
    use_vendored_dylib "git is not installed"
fi

BUILD_ROOT="${PROJECT_TEMP_ROOT:-${TMPDIR:-/tmp}/aizen-fff-c}"
SOURCE_DIR="${BUILD_ROOT}/src"
PROFILE="debug"
if [ "${CONFIGURATION:-Debug}" = "Release" ]; then
    PROFILE="release"
fi

mkdir -p "${BUILD_ROOT}"

if [ ! -d "${SOURCE_DIR}/.git" ]; then
    rm -rf "${SOURCE_DIR}"
    git clone --filter=blob:none "${FFF_REPO_URL}" "${SOURCE_DIR}"
fi

git -C "${SOURCE_DIR}" fetch --depth 1 origin "${FFF_COMMIT}"
git -C "${SOURCE_DIR}" checkout --force "${FFF_COMMIT}"

BUILD_ARGS=(-p fff-c)
if [ "${PROFILE}" = "release" ]; then
    BUILD_ARGS+=(--release)
fi

pushd "${SOURCE_DIR}" >/dev/null
cargo build "${BUILD_ARGS[@]}"
popd >/dev/null

BUILT_DYLIB="${SOURCE_DIR}/target/${PROFILE}/libfff_c.dylib"
if [ ! -f "${BUILT_DYLIB}" ]; then
    echo "error: expected fff dylib not found at ${BUILT_DYLIB}" >&2
    exit 1
fi

install_name_tool -id "@rpath/libfff_c.dylib" "${BUILT_DYLIB}" 2>/dev/null || true

mkdir -p "${VENDOR_LIB_DIR}"
cp "${BUILT_DYLIB}" "${VENDOR_DYLIB}"
copy_to_app_bundle "${BUILT_DYLIB}"
