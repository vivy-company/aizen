#!/bin/bash
set -euo pipefail

# End-to-end helper: ensure libghostty universal at a specific ref, then build aizen universal (arm64 + x86_64).
# Usage (no args): ./scripts/build-universal.sh
# - libghostty ref is read from libghostty/VERSION (deterministic); override by passing a ref
#   as the first arg if you need to temporarily build a different version.
# - Config defaults to Release; optionally pass Debug/Release as the second arg.
# - Code signing is disabled for convenience; adjust if you need a signed build.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENSURE_SCRIPT="${ROOT_DIR}/scripts/ensure-libghostty.sh"
REF=${1:-}
CONFIG=${2:-Release}
JOBS=${JOBS:-4}

if [ -z "${REF}" ]; then
    if [ -s "${ROOT_DIR}/libghostty/VERSION" ]; then
        REF=$(cat "${ROOT_DIR}/libghostty/VERSION" | tr -d "\n")
        echo "Using libghostty ref from libghostty/VERSION: ${REF}"
    else
        echo "Error: libghostty ref is required; set it in libghostty/VERSION (or pass as arg)." >&2
        exit 1
    fi
fi

echo "Ensuring build dependencies"
"${ROOT_DIR}/scripts/install-deps.sh"

echo "Ensuring libghostty universal @ ${REF}"
LIBGHOSTTY_REF="${REF}" "${ENSURE_SCRIPT}"

echo "Building aizen (${CONFIG}) universal (arm64 + x86_64)"
cd "${ROOT_DIR}"
xcodebuild \
  -scheme aizen \
  -configuration "${CONFIG}" \
  -arch arm64 -arch x86_64 \
    -jobs "${JOBS}" \
  -skipPackagePluginValidation -skipMacroValidation \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" \
  build

APP_PATH="${ROOT_DIR}/build/${CONFIG}/aizen.app"
if [ -d "${APP_PATH}" ]; then
    echo "Build complete: ${APP_PATH}"
else
    echo "Build finished; check xcodebuild output for the app location (may be in DerivedData)."
fi
