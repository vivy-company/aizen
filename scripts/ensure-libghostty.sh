#!/bin/bash
set -euo pipefail

# Ensure libghostty.a exists as a universal (arm64 + x86_64) binary at the
# version/tag specified by LIBGHOSTTY_REF or libghostty/VERSION. This runs as
# part of the Xcode build to make Intel builds reproducible.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB_DIR="${ROOT_DIR}/libghostty"
LIB_FILE="${LIB_DIR}/libghostty.a"
VERSION_FILE="${LIB_DIR}/VERSION"
BUILT_REF_FILE="${LIB_DIR}/.built-ref"
GHOSTTY_REPO="https://github.com/ghostty-org/ghostty"

# Optional persistent workdir to avoid recloning each build (set LIBGHOSTTY_WORKDIR=/path).
PERSIST_WORKDIR="${LIBGHOSTTY_WORKDIR:-}"
ZIG_JOBS="${ZIG_JOBS:-}"
ZIG_JOBS_FLAG=""

# Skip expensive work during Xcode index builds so SourceKit can resolve symbols.
if [ "${ACTION:-}" = "indexbuild" ] || [ "${INDEXBUILD:-}" = "YES" ]; then
    exit 0
fi

# Detect whether this Zig supports --jobs; older releases do not. Clear GREP_OPTIONS to
# avoid user env injecting unsupported flags.
if command -v zig >/dev/null 2>&1; then
    if zig build -h 2>&1 | env GREP_OPTIONS= grep -Fq -- "--jobs"; then
        if [ -n "${ZIG_JOBS}" ]; then
            ZIG_JOBS_FLAG="--jobs ${ZIG_JOBS}"
        fi
    else
        if [ -n "${ZIG_JOBS}" ]; then
            echo "Note: installed Zig does not support --jobs; ignoring ZIG_JOBS" >&2
        fi
    fi
fi

DESIRED_REF="${LIBGHOSTTY_REF:-}"
if [ -z "${DESIRED_REF}" ] && [ -f "${VERSION_FILE}" ]; then
    DESIRED_REF="$(cat "${VERSION_FILE}" | tr -d "\n" )"
fi
if [ -z "${DESIRED_REF}" ]; then
    DESIRED_REF="main"
fi

has_slice() {
    lipo -info "$1" 2>/dev/null | grep -q "${2}"
}

if [ -f "${LIB_FILE}" ] && has_slice "${LIB_FILE}" "arm64" && has_slice "${LIB_FILE}" "x86_64"; then
    CURRENT_REF=""
    [ -f "${BUILT_REF_FILE}" ] && CURRENT_REF="$(cat "${BUILT_REF_FILE}" | tr -d "\n")"
    [ -z "${CURRENT_REF}" ] && [ -f "${VERSION_FILE}" ] && CURRENT_REF="$(cat "${VERSION_FILE}" | tr -d "\n")"

    if [ "${CURRENT_REF}" = "${DESIRED_REF}" ]; then
        echo "libghostty.a already universal for ref ${DESIRED_REF}; skipping rebuild"
        exit 0
    fi
    echo "libghostty.a universal but ref mismatch (${CURRENT_REF} != ${DESIRED_REF}); rebuilding"
else
    echo "libghostty.a missing or not universal; rebuilding"
fi

if ! command -v git >/dev/null 2>&1; then
    echo "Error: git is required to build libghostty" >&2
    exit 1
fi
if ! command -v zig >/dev/null 2>&1; then
    echo "Error: zig is required to build libghostty (try 'brew install zig')" >&2
    exit 1
fi
if ! command -v lipo >/dev/null 2>&1; then
    echo "Error: lipo is required to combine architectures" >&2
    exit 1
fi

if [ -n "${PERSIST_WORKDIR}" ]; then
    mkdir -p "${PERSIST_WORKDIR}"
    WORKDIR="${PERSIST_WORKDIR}"
else
    WORKDIR="$(mktemp -d)"
    cleanup() { rm -rf "${WORKDIR}"; }
    trap cleanup EXIT
fi

if [ -d "${WORKDIR}/ghostty/.git" ]; then
    echo "Updating existing libghostty workdir at ${WORKDIR}/ghostty"
    (cd "${WORKDIR}/ghostty" && git fetch --depth 1 origin "${DESIRED_REF}" && git reset --hard "origin/${DESIRED_REF}" >/dev/null)
else
    echo "Fetching libghostty @ ${DESIRED_REF} into ${WORKDIR}/ghostty"
    git clone --depth 1 --branch "${DESIRED_REF}" "${GHOSTTY_REPO}" "${WORKDIR}/ghostty" >/dev/null
fi

# Patch build.zig to always install libs on macOS (upstream skips install on darwin)
perl -0pi -e 's/if \(!config.target.result.os.tag.isDarwin\(\)\) \{/if (true) {/' "${WORKDIR}/ghostty/build.zig"

# Patch macos package to link Metal frameworks (needed for cimgui metal symbols)
perl -0pi -e 's/lib\.linkFramework\("IOSurface"\);/lib.linkFramework("IOSurface");\n    lib.linkFramework("Metal");\n    lib.linkFramework("MetalKit");/g' "${WORKDIR}/ghostty/pkg/macos/build.zig"
perl -0pi -e 's/module\.linkFramework\("IOSurface", \.\{\}\);/module.linkFramework("IOSurface", .{});\n        module.linkFramework("Metal", .{});\n        module.linkFramework("MetalKit", .{});/g' "${WORKDIR}/ghostty/pkg/macos/build.zig"

ZIG_COMMON_FLAGS=(
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
)

build_arch() {
    local arch="$1"
    local target="${arch}-macos"
    local outdir="${WORKDIR}/zig-out-${arch}"
    echo "Building libghostty for ${arch}" >&2

    local attempts=0
    local max_attempts=3
    local last_err=0
    local logfile="${WORKDIR}/build-${arch}.log"
    while [ $attempts -lt $max_attempts ]; do
        echo "Logging to ${logfile}" >&2
        : > "${logfile}"
        if (cd "${WORKDIR}/ghostty" && zig build ${ZIG_JOBS_FLAG:+${ZIG_JOBS_FLAG}} "${ZIG_COMMON_FLAGS[@]}" -Doptimize=ReleaseFast -Dstrip -Dtarget="${target}" -p "${outdir}" > >(tee "${logfile}") 2>&1); then
            if [ -f "${outdir}/lib/libghostty.a" ]; then
                echo "${outdir}/lib/libghostty.a"
                return 0
            fi
            echo "Error: ${outdir}/lib/libghostty.a missing after successful build; see ${logfile}" >&2
            last_err=1
            break
        fi
        last_err=$?
        attempts=$((attempts + 1))
        echo "Retry ${attempts}/${max_attempts} for ${arch} after failure (see ${logfile})" >&2
        sleep 2
    done

    echo "Error: failed to build libghostty for ${arch} after ${max_attempts} attempts." >&2
    echo "See log: ${logfile}" >&2
    echo "Common causes: transient GitHub download failure (try VPN or rerun), missing Xcode command line tools, or missing Metal frameworks." >&2
    return $last_err
}

if ! ARM64_LIB=$(build_arch "aarch64"); then
    echo "Error: aarch64 build failed; aborting universal lipo" >&2
    exit 1
fi

if ! X64_LIB=$(build_arch "x86_64"); then
    echo "Error: x86_64 build failed; aborting universal lipo" >&2
    exit 1
fi

UNIVERSAL_TMP="${WORKDIR}/libghostty-universal.a"

echo "Creating universal libghostty.a"
lipo -create "${ARM64_LIB}" "${X64_LIB}" -output "${UNIVERSAL_TMP}"

INCLUDE_SRC="${WORKDIR}/ghostty/include"
if [ ! -d "${INCLUDE_SRC}" ]; then
    echo "Error: expected headers at ${INCLUDE_SRC} are missing; check build logs" >&2
    exit 1
fi

mkdir -p "${LIB_DIR}/include"
rsync -a --delete "${INCLUDE_SRC}/" "${LIB_DIR}/include/"
mv "${UNIVERSAL_TMP}" "${LIB_FILE}"
printf "%s\n" "${DESIRED_REF}" > "${BUILT_REF_FILE}"
printf "%s\n" "${DESIRED_REF}" > "${VERSION_FILE}"

echo "Updated libghostty.a to ${DESIRED_REF} with slices: $(lipo -info "${LIB_FILE}" | sed 's/.*are: //')"
