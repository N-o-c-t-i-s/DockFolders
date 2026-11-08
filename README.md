# Dock Folders

iPhone-style app folders for the macOS Dock (macOS 26 Tahoe).

A folder sits in the Dock like an app. Its icon shows its first four apps (2×2), hovering shows its
name, and a dot appears under it while any app inside is running. Click it to open a Liquid Glass
popup: icons at the Dock's size and spacing, 3×3 per page, page dots when there's more than one
page. The popup sits exactly where the Dock's name label would, rides up and down with the tile as
the Dock magnifies, and closes on its own once you've moved off it for a moment (riding down and
shrinking into its tile when the Dock hides). Inside, icons magnify like the Dock; drag one to
rearrange. While you're in the popup an auto-hiding Dock stays up; it hides again when the folder
closes. Right-click an app inside a folder for its Dock menu (its name, its windows, Options, Show
All Windows, Hide, Quit, and ⌥ for Force Quit).

There's no menu bar item. It starts at login and runs in the background; its only window is
Settings, which opens from a folder's right-click menu or when you open the app again. Quit it from
Settings or Activity Monitor.

## Using it

| To | Do this |
| --- | --- |
| Make a folder | Drag an app onto another app in the Dock and hold it until **Create Folder** appears, then let go; or ⇧ Shift-right-click any app → **New Folder with “App”…** |
| Move a Dock app into a folder | Drag it onto the folder and hold it there until the folder opens, then let go (on the folder or inside it), or ⇧ Shift-right-click it → **Move “App” to Folder ▸** |
| Move an app from a folder to the Dock | Drag it out of the open folder and drop it on the Dock where you want it |
| Add any app | Drag it from Finder or the Apps window onto the folder in the Dock, or use **+** above the app list in Settings |
| Open / close a folder | Click it. Move off its sides or top (it closes at once, like moving off the Dock), move away for a moment, click outside, or launch an app to close it |
| Turn pages | Two-finger swipe, or click the dots |
| Rearrange apps in a folder | Drag an icon; hold it near the left/right edge to change pages |
| Name a folder, add/remove/reorder its apps, show/hide it in the Dock, delete it | Right-click the folder → **Open Settings…** (or open Dock Folders from Spotlight) |
| Take an app out | Right-click it in the folder → Options → **Remove from Folder** or **Move to Dock** |
| Apps per page (3, 6, 9 or 16), names or running dots under apps, icon size, magnification | Settings → ⚙︎ General → **Inside Folders** |
| Rearrange folders in the Dock | Drag them like any other Dock icon |

The first launch asks for **Accessibility** access (System Settings → Privacy & Security →
Accessibility). Dock Folders needs it to see clicks on folder tiles and to keep the Dock open.

## Building

```bash
./build.sh            # builds build/Dock Folders.app
./build.sh install    # also copies it to /Applications and launches it
```

Requires Xcode 26+ command-line tools. The build signs with your "Apple Development" identity
when one exists, so the Accessibility permission survives rebuilds.

## How it works

No screen capturing and no Dock code injection; everything uses system mechanisms.

- **Folder tiles.** Each folder is a tiny app bundle in
  `~/Library/Application Support/Dock Folders/Folders/`, added to the Dock's own app list.
  Its icon is drawn by a **Dock tile plug-in** (`NSDockTilePlugIn`, the mechanism Calendar uses for
  its date), so the 2×2 icon updates live. The agent renders the tile image; the plug-in shows it.
  macOS only loads a third-party Dock plug-in after the app has been launched once, so each new
  stub is launched once, invisibly, with `--register`.
- **Clicks.** A Quartz event tap sees clicks on folder tiles before the Dock does and opens the
  popup instead of launching the stub. Drags are replayed to the Dock, so rearranging still works.
  If Dock Folders isn't running, clicking a folder launches its stub, which starts Dock Folders and
  opens the folder.
- **Popup.** A non-activating panel (your current app stays frontmost) with SwiftUI's
  `glassEffect` in a custom callout shape, so it matches the Dock's light, dark or tinted glass.
- **Keeping the Dock up.** While the pointer is in the popup (or on its way there), the Dock is
  put into its keyboard-focus state through Accessibility. That holds an auto-hiding Dock on
  screen without turning auto-hide off, which would resize full-screen and tiled windows. Back on
  the Dock the hold is released, so the Dock's own hover and magnification carry on.
- **Following the tile.** Every frame the popup reads the folder tile's frame and places its
  pointer where the Dock draws that tile's name label (measured: 5 pt pointer, tip 7.5 pt inside
  the tile's top). That keeps it clear of the Dock and hides the Dock's own label behind it; a
  frosted strip along the bottom edge stops that label showing through the glass.
- **Empty folders stay out of the Dock.** A new folder joins the Dock when its first app is added,
  and leaves it if its last app is removed (unless you turned **Show in Dock** off, which is
  remembered).
- **Changing the Dock without restarting it.** Restarting the Dock redraws the wallpaper and the
  menu bar, so Dock Folders avoids it. It changes the Dock through the Dock's own right-click menu
  instead (**Options ▸ Keep in Dock / Remove from Dock**, pressed through Accessibility, in the
  Mac's language); the menu shows for a moment. Folder tiles come and go silently: the folder's
  little app runs for a moment, so its tile is an ordinary running app's, which can be kept or let
  go without the Dock's "poof". An app's own tile leaving the Dock gets the Dock's usual poof.
  New folders appear at the end of the Dock's apps.
- **Dragging an app into a folder.** The Dock owns drags of its tiles (and slides tiles aside to
  make room), so Dock Folders watches the drag through its event tap and remembers where each
  folder sat when it started. Hold the app there for a moment and the folder springs open,
  outlined; let go on the folder or inside it and the app goes in (the Dock removes its tile). A
  quick pass over a folder doesn't count, so rearranging the Dock works as usual.
- **Making a folder by dragging.** Holding a dragged app over another app shows a **Create
  Folder** tag above it, drawn like the Dock's own name tags. Let go and the new folder is pinned
  (silently), slid to where you let go with a drag sent only to the Dock (the Dock drops dragged
  tiles under the real pointer, so this only runs while the pointer is still on the Dock), and the
  two apps' tiles leave the Dock.
- **Folder names.** New folders are named after their apps' App Store categories
  (`LSApplicationCategoryType`), like iOS: two games make "Games"; related categories get a group
  name ("Creativity", "Productivity & Finance", "Utilities"…); otherwise the category of the app
  it was dropped onto. Apps that don't declare one give "Folder".
- **Dragging an app out of a folder.** Once the icon is carried past the folder's edge it becomes
  a real drag of the app, like one from Finder, so the Dock makes room and adds it where you let go.
  It's offered only as a link, and only over the Dock: let go anywhere else and it slides back.
- **Saved for a quiet moment.** A few changes still need a restart: new names (the Dock only reads
  names when it starts), moving a new folder into the spot of the app it was made from, and putting
  an app that isn't running back in the Dock. They wait until your Mac locks or its display sleeps,
  so you never see the restart; **Update Now** in Settings does it straight away. If Dock Folders
  quits first, it picks pending names up again from the Dock.
- **Glass finish.** System glass alone renders softer and lighter than the Dock's, so the popup,
  labels and menus add the Dock's crisp 1 pt rim (brightest along the top) and, in Dark Mode, its
  deeper tone.
- **Menus.** Right-click menus are drawn in Liquid Glass rather than with `NSMenu`, because a
  native menu takes keyboard focus away from the Dock, which then slides away.

## Limitations

- Apple doesn't let other apps add items to the Dock's own right-click menu (it would need
  SIP disabled). That's why creating a folder is ⇧ Shift-right-click.
- Running apps still appear in the Dock's running-apps section; macOS shows every running app
  there, and only the app itself (or code running inside the Dock, which needs SIP disabled) can
  change that.
- Apple's own call for adding items to the Dock (`CoreDockAddFileToDock`) is reserved for Finder and
  Safari, so live changes go through the Dock's menu instead, which shows for a moment.
- The Dock draws its running dots only for running apps, so a folder's dot is drawn inside the
  folder's own icon, a few points higher than the Dock's other dots.
- App-specific Dock menu items (e.g. Music's playback controls) aren't available to other apps,
  so the in-folder menu has the standard items only.

## Layout

```
Sources/Agent/       the background app (event tap, popup, menus, Dock + folder management)
Sources/Stub/        the per-folder app that sits in the Dock
Sources/TilePlugin/  the Dock tile plug-in that draws a folder's icon
Sources/Shared/      constants shared by all three
Resources/           Info.plists
build.sh             builds, signs and (optionally) installs
```

Folder data lives in `~/Library/Application Support/Dock Folders/folders.json`.
