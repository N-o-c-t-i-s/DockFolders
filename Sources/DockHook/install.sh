#!/bin/sh
# Installs Dock Folders' Dock helper. Dock Folders runs this as root, after asking for your
# password, when you turn on "Open apps only in their folders" (System Integrity Protection must
# be partly off for it to do anything). $1 is the app's Contents/Resources/DockHook folder.
set -eu
SRC="$1"
LABEL="com.mylesdean.DockFolders.helper"
SUPPORT="/Library/Application Support/Dock Folders"
HELPER="/Library/PrivilegedHelperTools/$LABEL"
PLIST="/Library/LaunchDaemons/$LABEL.plist"

launchctl bootout "system/$LABEL" 2>/dev/null || true
mkdir -p "$SUPPORT" /Library/PrivilegedHelperTools
install -m 644 -o root -g wheel "$SRC/DockFoldersHook.dylib" "$SUPPORT/DockFoldersHook.dylib"
install -m 755 -o root -g wheel "$SRC/DockFoldersHelper" "$HELPER"
install -m 644 -o root -g wheel "$SRC/$LABEL.plist" "$PLIST"
launchctl bootstrap system "$PLIST"
