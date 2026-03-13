#!/bin/bash
set -euo pipefail

# Download libghostty from R2
# Usage: ./scripts/download-libghostty.sh
# Requires: R2_PUBLIC_URL environment variable (or uses default)

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="${ROOT_DIR}/Vendor/libghostty"

R2_PUBLIC_URL="${R2_PUBLIC_URL:-https://cdn.aizen.app}"
DOWNLOAD_URL="${R2_PUBLIC_URL}/libghostty.tar.gz"

echo "Downloading libghostty from R2..."
echo "URL: ${DOWNLOAD_URL}"

curl -fsSL "${DOWNLOAD_URL}" -o "${ROOT_DIR}/libghostty.tar.gz"

echo "Extracting to ${VENDOR_DIR}..."
mkdir -p "${VENDOR_DIR}"
rm -rf "${VENDOR_DIR}/include" "${VENDOR_DIR}/lib"
tar -xzf "${ROOT_DIR}/libghostty.tar.gz" -C "${VENDOR_DIR}"
rm "${ROOT_DIR}/libghostty.tar.gz"
rm -f "${VENDOR_DIR}/include/module.modulemap"

for required_path in \
    "${VENDOR_DIR}/VERSION" \
    "${VENDOR_DIR}/include/ghostty.h" \
    "${VENDOR_DIR}/lib/libghostty.a"
do
    if [ ! -f "${required_path}" ]; then
        echo "Error: Missing expected libghostty payload file: ${required_path}" >&2
        exit 1
    fi
done

echo "Ghostty version: $(cat "${VENDOR_DIR}/VERSION")"
echo "Done: $(lipo -info "${VENDOR_DIR}/lib/libghostty.a" 2>/dev/null || echo "libghostty.a extracted")"
