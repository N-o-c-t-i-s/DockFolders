#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

CHECK_DIR="$(mktemp -d)"
trap 'rm -rf "$CHECK_DIR"' EXIT

xcrun swiftc \
    Sources/Agent/AppIconResolver.swift \
    Tests/AppIconResolverSelfCheck.swift \
    -o "$CHECK_DIR/AppIconResolverSelfCheck"

"$CHECK_DIR/AppIconResolverSelfCheck"
