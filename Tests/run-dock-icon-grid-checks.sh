#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

CHECK_DIR="$(mktemp -d)"
trap 'rm -rf "$CHECK_DIR"' EXIT

xcrun swiftc \
    Sources/Agent/DockIconGridLayout.swift \
    Tests/DockIconGridLayoutSelfCheck.swift \
    -o "$CHECK_DIR/DockIconGridLayoutSelfCheck"

"$CHECK_DIR/DockIconGridLayoutSelfCheck"
