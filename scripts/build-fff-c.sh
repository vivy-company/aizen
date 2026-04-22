#!/usr/bin/env bash
set -euo pipefail

FFF_REPO_URL="https://github.com/dmtrKovalenko/fff.nvim"
FFF_COMMIT="8298260c64e2bb517fd6624362673c64e0a05848"

if ! command -v cargo >/dev/null 2>&1; then
    echo "warning: cargo is not installed; skipping fff-c build" >&2
    exit 0
fi

if ! command -v git >/dev/null 2>&1; then
    echo "warning: git is not installed; skipping fff-c build" >&2
    exit 0
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

pushd "${SOURCE_DIR}" >/dev/null
cargo build -p fff-c $( [ "${PROFILE}" = "release" ] && printf '%s' "--release" )
popd >/dev/null

BUILT_DYLIB="${SOURCE_DIR}/target/${PROFILE}/libfff_c.dylib"
if [ ! -f "${BUILT_DYLIB}" ]; then
    echo "error: expected fff dylib not found at ${BUILT_DYLIB}" >&2
    exit 1
fi

install_name_tool -id "@rpath/libfff_c.dylib" "${BUILT_DYLIB}" 2>/dev/null || true

VENDOR_LIB_DIR="${SRCROOT:-$(pwd)}/Vendor/fff-c/lib"
mkdir -p "${VENDOR_LIB_DIR}"
cp "${BUILT_DYLIB}" "${VENDOR_LIB_DIR}/libfff_c.dylib"

if [ -n "${BUILT_PRODUCTS_DIR:-}" ] && [ -n "${PRODUCT_NAME:-}" ]; then
    FRAMEWORKS_DIR="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Frameworks"
    mkdir -p "${FRAMEWORKS_DIR}"
    cp "${BUILT_DYLIB}" "${FRAMEWORKS_DIR}/libfff_c.dylib"

    if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ] && [ "${CODE_SIGNING_ALLOWED:-NO}" = "YES" ]; then
        codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --timestamp=none "${FRAMEWORKS_DIR}/libfff_c.dylib"
    fi
fi
