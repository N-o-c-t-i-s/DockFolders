#!/bin/bash
# Builds "Dock Folders.app" into ./build.
#   ./build.sh           build only
#   ./build.sh install   build, copy to /Applications and (re)launch
set -euo pipefail
cd "$(dirname "$0")"

BUILD="$PWD/build"
APP="$BUILD/Dock Folders.app"
STUB="$APP/Contents/Resources/FolderStub.app"
PLUGIN="$STUB/Contents/PlugIns/FolderTile.docktileplugin"
SWIFTC=(xcrun swiftc -target arm64-apple-macos26.0 -O -swift-version 5 ${DF_SWIFT_FLAGS:-})

# A stable signing identity keeps the Accessibility permission across rebuilds.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')}"
IDENTITY="${IDENTITY:--}"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" \
         "$STUB/Contents/MacOS" "$STUB/Contents/Resources" "$PLUGIN/Contents/MacOS"

# Changes to the stub or plug-in make the agent rebuild existing folder stubs on next launch
# (which restarts the Dock, so only real changes should). Bump STUB_BUILD when the way they're
# built changes; other edits to this script don't count.
STUB_BUILD=1
TEMPLATE_HASH=$( (cat Sources/Shared/*.swift Sources/Stub/*.swift Sources/TilePlugin/*.swift \
                    Resources/Stub-Info.plist Resources/TilePlugin-Info.plist; echo "$STUB_BUILD") | shasum -a 256 | cut -c1-16)

echo "→ Dock tile plug-in"
# The Dock only loads Mach-O bundles (MH_BUNDLE), not dylibs.
"${SWIFTC[@]}" -emit-executable -Xlinker -bundle -module-name FolderTile \
    Sources/Shared/*.swift Sources/TilePlugin/*.swift -o "$PLUGIN/Contents/MacOS/FolderTile"
cp Resources/TilePlugin-Info.plist "$PLUGIN/Contents/Info.plist"

echo "→ Folder stub"
"${SWIFTC[@]}" -module-name FolderStub Sources/Shared/*.swift Sources/Stub/main.swift -o "$STUB/Contents/MacOS/FolderStub"
cp Resources/Stub-Info.plist "$STUB/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :DFTemplateHash string $TEMPLATE_HASH" "$STUB/Contents/Info.plist"

echo "→ Dock Folders agent"
"${SWIFTC[@]}" -module-name DockFolders Sources/Shared/*.swift Sources/Agent/*.swift -o "$APP/Contents/MacOS/Dock Folders"
cp Resources/Agent-Info.plist "$APP/Contents/Info.plist"

echo "→ Icons"
"$APP/Contents/MacOS/Dock Folders" --render-icon "$APP/Contents/Resources/AppIcon.icns"
cp "$APP/Contents/Resources/AppIcon.icns" "$STUB/Contents/Resources/AppIcon.icns"

echo "→ Signing ($IDENTITY)"
codesign --force --sign - --timestamp=none "$PLUGIN"
codesign --force --sign - --timestamp=none "$STUB"
codesign --force --sign "$IDENTITY" --timestamp=none "$APP"

echo "✓ Built $APP"

if [[ "${1:-}" == "install" ]]; then
    echo "→ Installing to /Applications"
    pkill -x "Dock Folders" 2>/dev/null || true
    sleep 0.5
    rm -rf "/Applications/Dock Folders.app"
    ditto "$APP" "/Applications/Dock Folders.app"
    # Only the installed copy should handle dockfolders:// links.
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$APP" 2>/dev/null || true
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/Dock Folders.app"
    open "/Applications/Dock Folders.app"
    echo "✓ Installed and launched"
fi
