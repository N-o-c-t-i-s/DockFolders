#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

CHECK_DIR="$(mktemp -d)"
trap 'rm -rf "$CHECK_DIR"' EXIT

xcrun swiftc \
    Sources/Shared/Shared.swift \
    Sources/Agent/FolderStore.swift \
    Sources/Agent/Dock.swift \
    Sources/Agent/FrozenTileAnchor.swift \
    Tests/FrozenTileAnchorSelfCheck.swift \
    -o "$CHECK_DIR/FrozenTileAnchorSelfCheck"

"$CHECK_DIR/FrozenTileAnchorSelfCheck"
