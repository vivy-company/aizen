#!/usr/bin/env bash
set -euo pipefail

packages=(
  Core
  Wire
  Client
  Features
  Design
  Host
  Storage
  Security
  Transport
  MacPlatform
  TestSupport
)

for package in "${packages[@]}"; do
  swift test --package-path "Packages/$package"
done

swift build --package-path Packages/Core --triple arm64-apple-ios17.0
swift build --package-path Packages/Wire --triple arm64-apple-ios17.0
