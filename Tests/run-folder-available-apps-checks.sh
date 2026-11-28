#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

CHECK_DIR="$(mktemp -d)"
trap 'rm -rf "$CHECK_DIR"' EXIT

xcrun swiftc \
    Sources/Shared/Shared.swift \
    Sources/Agent/FolderStore.swift \
    Sources/Agent/AppBundleWatchDirectories.swift \
    Tests/FolderAvailableAppsSelfCheck.swift \
    -o "$CHECK_DIR/FolderAvailableAppsSelfCheck"

"$CHECK_DIR/FolderAvailableAppsSelfCheck"
