#!/bin/bash
set -euo pipefail

# Build (or rebuild) libghostty as a universal (arm64 + x86_64) static library.
# Usage: ./scripts/build-libghostty.sh [ref]
# - ref (optional): tag/branch/commit to build. Defaults to libghostty/VERSION or main.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENSURE_SCRIPT="${ROOT_DIR}/scripts/ensure-libghostty.sh"

REF="${1:-}"
if [ -n "$REF" ]; then
    echo "Building libghostty @ ${REF}"
    LIBGHOSTTY_REF="$REF" "$ENSURE_SCRIPT"
else
    echo "Building libghostty @ default ref (libghostty/VERSION or main)"
    "$ENSURE_SCRIPT"
fi

echo "Done. Current libghostty slices:"
lipo -info "${ROOT_DIR}/libghostty/libghostty.a"
