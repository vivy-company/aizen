#!/usr/bin/env bash
set -euo pipefail

# Organize Ghostty resources from Xcode's flattened copy into proper directory structure
#
# Expected input: Flattened resources in ${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Resources/
# - Theme files (no extension): Catppuccin Mocha, Gruvbox Dark, etc.
# - Shell integration: ghostty.bash, ghostty-integration, etc.
# - Terminfo: ghostty, xterm-ghostty
#
# Output structure:
# - ghostty/themes/
# - ghostty/shell-integration/{bash,elvish,fish,zsh}/
# - terminfo/{67,78}/

RESOURCES_DIR="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Resources"

# Validate environment
if [ -z "${BUILT_PRODUCTS_DIR}" ] || [ -z "${PRODUCT_NAME}" ]; then
    echo "Error: Required environment variables not set" >&2
    exit 1
fi

if [ ! -d "${RESOURCES_DIR}" ]; then
    echo "Error: Resources directory not found: ${RESOURCES_DIR}" >&2
    exit 1
fi

echo "Organizing Ghostty resources in ${RESOURCES_DIR}"

# Move terminfo files FIRST (before creating any directories)
# The 'ghostty' file must be moved before we can create a 'ghostty' directory
mkdir -p "${RESOURCES_DIR}/terminfo/67" "${RESOURCES_DIR}/terminfo/78"

if [ -f "${RESOURCES_DIR}/ghostty" ]; then
    mv "${RESOURCES_DIR}/ghostty" "${RESOURCES_DIR}/terminfo/67/" || {
        echo "Warning: Failed to move terminfo ghostty file" >&2
    }
fi

if [ -f "${RESOURCES_DIR}/xterm-ghostty" ]; then
    mv "${RESOURCES_DIR}/xterm-ghostty" "${RESOURCES_DIR}/terminfo/78/" || {
        echo "Warning: Failed to move xterm-ghostty file" >&2
    }
fi

# Now create ghostty directory structure (safe after moving ghostty file)
mkdir -p "${RESOURCES_DIR}/ghostty/themes"
mkdir -p "${RESOURCES_DIR}/ghostty/shell-integration"/{bash,elvish,fish,zsh}

# Copy shell integration files from source directory
# These files are not in Xcode's Copy Bundle Resources, so we copy them directly
SHELL_INTEGRATION_SRC="${SRCROOT}/aizen/Resources/ghostty/shell-integration"

if [ -d "${SHELL_INTEGRATION_SRC}" ]; then
    # Copy zsh integration (including hidden .zshenv)
    if [ -d "${SHELL_INTEGRATION_SRC}/zsh" ]; then
        cp -a "${SHELL_INTEGRATION_SRC}/zsh/." "${RESOURCES_DIR}/ghostty/shell-integration/zsh/" || {
            echo "Warning: Failed to copy zsh shell integration" >&2
        }
    fi

    # Copy other shell integrations if they exist
    for shell in bash elvish fish; do
        if [ -d "${SHELL_INTEGRATION_SRC}/${shell}" ]; then
            cp -a "${SHELL_INTEGRATION_SRC}/${shell}/." "${RESOURCES_DIR}/ghostty/shell-integration/${shell}/" || {
                echo "Warning: Failed to copy ${shell} shell integration" >&2
            }
        fi
    done

    echo "Shell integration files copied from source"
else
    # Fallback: try to move from flattened Resources (legacy behavior)
    move_shell_file() {
        local src_name="$1"
        local rel_dst="$2"
        local src_path="${RESOURCES_DIR}/${src_name}"
        local dst_path="${RESOURCES_DIR}/ghostty/shell-integration/${rel_dst}"

        if [ -f "${src_path}" ]; then
            mkdir -p "$(dirname "${dst_path}")"
            mv "${src_path}" "${dst_path}" || {
                echo "Warning: Failed to move ${src_name}" >&2
            }
        fi
    }

    move_shell_file "ghostty.bash" "bash/ghostty.bash"
    move_shell_file "bash-preexec.sh" "bash/bash-preexec.sh"
    move_shell_file "ghostty-integration.elv" "elvish/ghostty-integration.elv"
    move_shell_file "ghostty-shell-integration.fish" "fish/ghostty-shell-integration.fish"
    move_shell_file "ghostty-integration" "zsh/ghostty-integration"
    move_shell_file ".zshenv" "zsh/.zshenv"
fi

# Move theme files (files without extensions, not directories, excluding known patterns)
# Only process potential theme files to avoid iterating over all resources
THEME_COUNT=0
shopt -s nullglob
for file in "${RESOURCES_DIR}"/*; do
    [ -f "$file" ] || continue

    filename=$(basename "$file")

    # Skip files with extensions
    [[ "$filename" =~ \. ]] && continue

    # Skip already-moved files and known non-themes
    case "$filename" in
        ghostty|xterm-ghostty|ghostty-*|Info|Assets)
            continue
            ;;
    esac

    # Move to themes directory
    if mv "$file" "${RESOURCES_DIR}/ghostty/themes/"; then
        THEME_COUNT=$((THEME_COUNT + 1))
    else
        echo "Warning: Failed to move theme file: $filename" >&2
    fi
done

# Copy KaTeX resources for math rendering
KATEX_SRC="${SRCROOT}/aizen/Resources/katex"
if [ -d "${KATEX_SRC}" ]; then
    mkdir -p "${RESOURCES_DIR}/katex"
    cp -a "${KATEX_SRC}/." "${RESOURCES_DIR}/katex/" || {
        echo "Warning: Failed to copy KaTeX resources" >&2
    }
    echo "KaTeX resources copied"
fi

# Copy KaTeX fonts
FONTS_SRC="${SRCROOT}/aizen/Resources/fonts"
if [ -d "${FONTS_SRC}" ]; then
    mkdir -p "${RESOURCES_DIR}/fonts"
    for font in "${FONTS_SRC}"/KaTeX_*; do
        [ -f "$font" ] || continue
        cp "$font" "${RESOURCES_DIR}/fonts/" || {
            echo "Warning: Failed to copy font: $(basename "$font")" >&2
        }
    done
    echo "KaTeX fonts copied"
fi

# Copy Mermaid resources for diagram rendering
MERMAID_SRC="${SRCROOT}/aizen/Resources/mermaid"
if [ -d "${MERMAID_SRC}" ]; then
    mkdir -p "${RESOURCES_DIR}/mermaid"
    cp -a "${MERMAID_SRC}/." "${RESOURCES_DIR}/mermaid/" || {
        echo "Warning: Failed to copy Mermaid resources" >&2
    }
    echo "Mermaid resources copied"
fi

# Build and bundle VVDevKit tree-sitter grammar dylibs.
# VVHighlighting loads these at runtime via dlopen.
bundle_vvdevkit_grammar_dylibs() {
    local frameworks_dir="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Frameworks"
    local grammar_dir="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Resources"
    mkdir -p "${grammar_dir}"

    # Start clean so the app doesn't carry stale grammar binaries across rebuilds.
    find "${grammar_dir}" -maxdepth 1 -type f -name "libTreeSitter*.dylib" -delete

    local vvdevkit_dir=""
    if [ -n "${VVDEVKIT_SOURCE_PATH:-}" ] && [ -d "${VVDEVKIT_SOURCE_PATH}" ]; then
        vvdevkit_dir="${VVDEVKIT_SOURCE_PATH}"
    elif [ -n "${SOURCEPACKAGES_DIR_PATH:-${SOURCE_PACKAGES_DIR_PATH:-}}" ]; then
        local packages_dir="${SOURCEPACKAGES_DIR_PATH:-${SOURCE_PACKAGES_DIR_PATH:-}}"
        if [ -d "${packages_dir}/checkouts/VVDevKit" ]; then
            vvdevkit_dir="${packages_dir}/checkouts/VVDevKit"
        elif [ -d "${packages_dir}/checkouts/vvdevkit" ]; then
            vvdevkit_dir="${packages_dir}/checkouts/vvdevkit"
        fi
    elif [ -n "${BUILD_DIR:-}" ]; then
        local derived_data_dir=""
        derived_data_dir="$(cd "${BUILD_DIR}/../.." 2>/dev/null && pwd -P || true)"
        if [ -n "${derived_data_dir}" ]; then
            if [ -d "${derived_data_dir}/SourcePackages/checkouts/VVDevKit" ]; then
                vvdevkit_dir="${derived_data_dir}/SourcePackages/checkouts/VVDevKit"
            elif [ -d "${derived_data_dir}/SourcePackages/checkouts/vvdevkit" ]; then
                vvdevkit_dir="${derived_data_dir}/SourcePackages/checkouts/vvdevkit"
            fi
        fi
    elif [ -n "${PROJECT_TEMP_ROOT:-}" ]; then
        local derived_data_dir=""
        derived_data_dir="$(cd "${PROJECT_TEMP_ROOT}/../.." 2>/dev/null && pwd -P || true)"
        if [ -n "${derived_data_dir}" ]; then
            if [ -d "${derived_data_dir}/SourcePackages/checkouts/VVDevKit" ]; then
                vvdevkit_dir="${derived_data_dir}/SourcePackages/checkouts/VVDevKit"
            elif [ -d "${derived_data_dir}/SourcePackages/checkouts/vvdevkit" ]; then
                vvdevkit_dir="${derived_data_dir}/SourcePackages/checkouts/vvdevkit"
            fi
        fi
    fi

    # Developer-local fallback path.
    if [ -z "${vvdevkit_dir}" ] && [ -d "${HOME}/vivy/experiments/vvdevkit/VVDevKit" ]; then
        vvdevkit_dir="${HOME}/vivy/experiments/vvdevkit/VVDevKit"
    fi

    # Remove stale grammar dylibs from Frameworks to avoid startup overhead.
    if [ -d "${frameworks_dir}" ]; then
        find "${frameworks_dir}" -maxdepth 1 -type f -name "libTreeSitter*.dylib" -delete
    fi

    local config_lower
    config_lower="$(echo "${CONFIGURATION:-Debug}" | tr '[:upper:]' '[:lower:]')"
    if [ "${config_lower}" != "release" ]; then
        config_lower="debug"
    fi

    local arch_hint="${NATIVE_ARCH_ACTUAL:-${ARCHS%% *}}"
    local derived_data_dir=""
    if [ -n "${BUILD_DIR:-}" ]; then
        case "${BUILD_DIR}" in
            */Build/Products/*)
                derived_data_dir="${BUILD_DIR%%/Build/Products/*}"
                ;;
            */Build/Intermediates.noindex/ArchiveIntermediates/*/BuildProductsPath/*)
                derived_data_dir="${BUILD_DIR%%/Build/Intermediates.noindex/ArchiveIntermediates/*}"
                ;;
            */Build/Intermediates.noindex/ArchiveIntermediates/*/BuildProductsPath)
                derived_data_dir="${BUILD_DIR%%/Build/Intermediates.noindex/ArchiveIntermediates/*}"
                ;;
        esac
    fi

    local -a candidate_dirs=()
    add_candidate_dir() {
        local dir="$1"
        if [ -n "${dir}" ] && [ -d "${dir}" ]; then
            candidate_dirs+=("${dir}")
        fi
    }

    # Xcode-built products first (typically the linked subset).
    add_candidate_dir "${BUILT_PRODUCTS_DIR}"
    add_candidate_dir "${BUILD_DIR:-}"

    # Archive builds place package outputs under ArchiveIntermediates/.../BuildProductsPath.
    if [ -n "${BUILD_DIR:-}" ]; then
        case "${BUILD_DIR}" in
            */Build/Intermediates.noindex/ArchiveIntermediates/*/BuildProductsPath/*)
                add_candidate_dir "${BUILD_DIR%%/BuildProductsPath/*}/BuildProductsPath/${CONFIGURATION:-Debug}"
                ;;
            */Build/Intermediates.noindex/ArchiveIntermediates/*/BuildProductsPath)
                add_candidate_dir "${BUILD_DIR}/${CONFIGURATION:-Debug}"
                ;;
        esac
    fi

    # VVDevKit checkout outputs (local/source checkout).
    if [ -n "${vvdevkit_dir}" ]; then
        add_candidate_dir "${vvdevkit_dir}/.build"
        add_candidate_dir "${vvdevkit_dir}/.build/${arch_hint}-apple-macosx/${config_lower}"
        add_candidate_dir "${vvdevkit_dir}/.build/${config_lower}"
        add_candidate_dir "${vvdevkit_dir}/.build/debug"
        add_candidate_dir "${vvdevkit_dir}/.build/release"
        add_candidate_dir "${vvdevkit_dir}/build/Build/Products/${CONFIGURATION:-Debug}"
    fi

    # Also probe a known developer checkout path if it exists.
    local local_vvdevkit_dir=""
    if [ -n "${HOME:-}" ] && [ -d "${HOME}/vivy/experiments/vvdevkit/VVDevKit" ]; then
        local_vvdevkit_dir="${HOME}/vivy/experiments/vvdevkit/VVDevKit"
    elif [ -n "${USER:-}" ] && [ -d "/Users/${USER}/vivy/experiments/vvdevkit/VVDevKit" ]; then
        local_vvdevkit_dir="/Users/${USER}/vivy/experiments/vvdevkit/VVDevKit"
    fi
    if [ -n "${local_vvdevkit_dir}" ]; then
        add_candidate_dir "${local_vvdevkit_dir}/.build"
        add_candidate_dir "${local_vvdevkit_dir}/build/Build/Products/${CONFIGURATION:-Debug}"
    fi

    # DerivedData package products (if available).
    if [ -n "${derived_data_dir}" ]; then
        add_candidate_dir "${derived_data_dir}/Build/Products/${CONFIGURATION:-Debug}"
    fi

    if [ "${#candidate_dirs[@]}" -eq 0 ]; then
        echo "Warning: No candidate directories found for VVDevKit grammar dylibs" >&2
    fi

    local copied_count=0
    local unique_count=0
    local signed_count=0
    local source_path=""
    local dylib=""
    local destination_path=""
    local sign_identity="${EXPANDED_CODE_SIGN_IDENTITY:-}"
    local should_sign=0
    local manifest_file=""
    local unique_manifest_file=""

    manifest_file="$(mktemp "${TMPDIR:-/tmp}/vvdevkit-dylibs-XXXXXX")"
    unique_manifest_file="$(mktemp "${TMPDIR:-/tmp}/vvdevkit-dylibs-unique-XXXXXX")"

    if [ "${CODE_SIGNING_ALLOWED:-NO}" = "YES" ] && [ -n "${sign_identity}" ] && [ "${sign_identity}" != "-" ]; then
        should_sign=1
    fi

    for source_dir in "${candidate_dirs[@]}"; do
        while IFS= read -r source_path; do
            [ -f "${source_path}" ] || continue
            dylib="$(basename "${source_path}")"
            destination_path="${grammar_dir}/${dylib}"
            cp -f "${source_path}" "${destination_path}" || {
                echo "Warning: Failed to copy ${dylib}" >&2
                continue
            }
            echo "${dylib}" >> "${manifest_file}"
            copied_count=$((copied_count + 1))
        done < <(find "${source_dir}" -type f -name "libTreeSitter*.dylib" -not -path "*.dSYM/*" 2>/dev/null)
    done

    if [ -s "${manifest_file}" ]; then
        sort -u "${manifest_file}" > "${unique_manifest_file}"
        unique_count="$(wc -l < "${unique_manifest_file}" | tr -d ' ')"

        if [ "${should_sign}" -eq 1 ]; then
            while IFS= read -r dylib; do
                destination_path="${grammar_dir}/${dylib}"
                /usr/bin/codesign --force --sign "${sign_identity}" --timestamp=none "${destination_path}" >/dev/null 2>&1 || {
                    echo "Warning: Failed to sign ${dylib}" >&2
                    continue
                }
                signed_count=$((signed_count + 1))
            done < "${unique_manifest_file}"
        fi
    fi

    rm -f "${manifest_file}" "${unique_manifest_file}"

    if [ "${unique_count}" -eq 0 ]; then
        echo "Warning: No VVDevKit grammar dylibs were found in known build locations" >&2
    else
        echo "Bundled ${unique_count} VVDevKit grammar dylibs"
        if [ "${should_sign}" -eq 1 ]; then
            echo "Signed ${signed_count}/${unique_count} VVDevKit grammar dylibs"
        fi
    fi
}

bundle_vvdevkit_grammar_dylibs

echo "Resource organization complete: ${THEME_COUNT} themes moved"
exit 0
