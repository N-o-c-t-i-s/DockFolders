#!/bin/sh
# Removes Dock Folders' Dock helper (run as root by Dock Folders, after asking for your password).
# The Dock keeps the helper's code until it restarts; Dock Folders restarts it afterwards.
LABEL="com.mylesdean.DockFolders.helper"
SUPPORT="/Library/Application Support/Dock Folders"
launchctl bootout "system/$LABEL" 2>/dev/null || true
rm -f "/Library/PrivilegedHelperTools/$LABEL" "/Library/LaunchDaemons/$LABEL.plist" "$SUPPORT/DockFoldersHook.dylib"
rmdir "$SUPPORT" 2>/dev/null || true
exit 0
