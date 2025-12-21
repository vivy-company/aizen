#!/usr/bin/env bash
set -e

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
    declare -A SHELL_FILES=(
        ["ghostty.bash"]="bash/ghostty.bash"
        ["bash-preexec.sh"]="bash/bash-preexec.sh"
        ["ghostty-integration.elv"]="elvish/ghostty-integration.elv"
        ["ghostty-shell-integration.fish"]="fish/ghostty-shell-integration.fish"
        ["ghostty-integration"]="zsh/ghostty-integration"
        [".zshenv"]="zsh/.zshenv"
    )

    for src in "${!SHELL_FILES[@]}"; do
        if [ -f "${RESOURCES_DIR}/${src}" ]; then
            mv "${RESOURCES_DIR}/${src}" "${RESOURCES_DIR}/ghostty/shell-integration/${SHELL_FILES[$src]}" || {
                echo "Warning: Failed to move ${src}" >&2
            }
        fi
    done
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
        ((THEME_COUNT++))
    else
        echo "Warning: Failed to move theme file: $filename" >&2
    fi
done

echo "Resource organization complete: ${THEME_COUNT} themes moved"
exit 0
