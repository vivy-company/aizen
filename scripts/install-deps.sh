#!/bin/bash
set -euo pipefail

# Install required build dependencies if missing.
# Ensures all local/CI tools used by build, lint, packaging, and release.

REQUIRED=(
    zig
    swiftlint
    create-dmg
    awscli
    sparkle
)

if ! command -v brew >/dev/null 2>&1; then
    echo "Error: Homebrew is required to install dependencies. Install from https://brew.sh and rerun." >&2
    exit 1
fi

for dep in "${REQUIRED[@]}"; do
    if command -v "$dep" >/dev/null 2>&1; then
        echo "$dep already installed"
    else
        echo "Installing $dep via Homebrew..."
        brew install "$dep"
    fi
done

echo "All required dependencies are installed."
