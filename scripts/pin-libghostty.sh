#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="${ROOT_DIR}/libghostty/VERSION"
BUILT_REF_FILE="${ROOT_DIR}/libghostty/.built-ref"
LIB_FILE="${ROOT_DIR}/libghostty/libghostty.a"
GHOSTTY_REPO="https://github.com/ghostty-org/ghostty"
WORKDIR="${LIBGHOSTTY_WORKDIR:-}"

REF="${1:-}"
if [ -z "${REF}" ]; then
    if [ -f "${VERSION_FILE}" ] && REF_CONTENT=$(cat "${VERSION_FILE}" | tr -d "\n"); then
        if [ -n "${REF_CONTENT}" ]; then
            REF="${REF_CONTENT}"
            echo "No ref provided; reusing ${VERSION_FILE} (${REF})." >&2
        fi
    fi
fi

if [ -z "${REF}" ]; then
    echo "No ref provided and ${VERSION_FILE} is empty. Fetching ghostty main HEAD..." >&2
    if ! REF=$(git ls-remote --heads "${GHOSTTY_REPO}" main | awk '{print $1}' | head -n1); then
        echo "Error: unable to resolve ghostty main HEAD." >&2
        exit 1
    fi
    if [ -z "${REF}" ]; then
        echo "Error: ghostty main HEAD not found." >&2
        exit 1
    fi
fi

echo "Pinning libghostty to ${REF}" >&2
printf "%s\n" "${REF}" > "${VERSION_FILE}"
rm -f "${BUILT_REF_FILE}"
rm -f "${LIB_FILE}"

if [ -n "${WORKDIR}" ] && [ -d "${WORKDIR}/ghostty" ]; then
    echo "Removing cached workdir at ${WORKDIR}/ghostty to force ref ${REF} on next build" >&2
    rm -rf "${WORKDIR}/ghostty"
fi

echo "Updated ${VERSION_FILE}, cleared cached artifacts, and will rebuild libghostty.a on next build." >&2
echo "Next: run ./scripts/release-package.sh (or build in Xcode)." >&2
