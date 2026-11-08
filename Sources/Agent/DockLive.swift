import AppKit
import os

private let log = Logger(subsystem: "com.mylesdean.DockFolders", category: "DockLive")

// MARK: - Changing the Dock while it runs

/// Changes the Dock through its own right-click menus (Options ▸ Keep in Dock / Remove from Dock),
/// instead of rewriting its settings and restarting it: a restart redraws the wallpaper and the
/// menu bar, which everyone sees. The Dock's menu shows for a moment while an item is pressed.
///
/// Folder tiles come and go silently: the folder's own little app runs for a moment, so its tile
/// is an ordinary running app's, which can be kept or let go without the Dock's "poof".
enum DockLive {
    private static let dockBundle = Bundle(path: "/System/Library/CoreServices/Dock.app")

    /// The Dock's own menu titles, in the Mac's language.
    private static func localized(_ key: String, _ english: String) -> String {
        dockBundle?.localizedString(forKey: key, value: english, table: "DockMenus") ?? english
    }

    private static let optionsTitle = localized("OPTIONS", "Options")
    private static let keepTitle = localized("KEEP_IN_DOCK", "Keep in Dock")
    private static let removeTitle = localized("REMOVE_FROM_DOCK", "Remove from Dock")

    private static func children(_ element: AXUIElement) -> [AXUIElement] { AX.value(element, kAXChildrenAttribute) ?? [] }
    private static func role(_ element: AXUIElement) -> String? { AX.value(element, kAXRoleAttribute) }
    private static func title(_ element: AXUIElement) -> String? { AX.value(element, kAXTitleAttribute) }

    /// Opens a tile's Dock menu and finds its Options submenu. Closes the menu again if there's none.
    private static func openOptions(_ tile: DockItem) -> (menu: AXUIElement, options: [AXUIElement])? {
        let shown = AXUIElementPerformAction(tile.element, kAXShowMenuAction as CFString)
        guard shown == .success else { log.error("AXShowMenu failed: \(shown.rawValue) on \(tile.title, privacy: .public)"); return nil }
        var menu: AXUIElement?
        for _ in 0..<60 {
            menu = children(tile.element).first { role($0) == kAXMenuRole }
            if menu != nil { break }
            usleep(5_000)
        }
        guard let menu else { log.error("no menu appeared on \(tile.title, privacy: .public)"); return nil }
        let titles = children(menu).compactMap(title)
        log.debug("menu on \(tile.title, privacy: .public): \(titles, privacy: .public)")
        if let item = children(menu).first(where: { title($0) == optionsTitle }),
           let submenu = children(item).first(where: { role($0) == kAXMenuRole }) {
            return (menu, children(submenu))
        }
        log.error("no \(optionsTitle, privacy: .public) submenu on \(tile.title, privacy: .public); items: \(titles, privacy: .public)")
        close(menu)
        return nil
    }

    private static func close(_ menu: AXUIElement) {
        AXUIElementPerformAction(menu, kAXCancelAction as CFString)
    }

    private static func press(_ item: AXUIElement) -> Bool {
        AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    private static func isChecked(_ item: AXUIElement) -> Bool {
        !((AX.value(item, kAXMenuItemMarkCharAttribute) as String?) ?? "").isEmpty
    }

    /// Sets "Keep in Dock" on a running app's tile. Silent either way.
    @discardableResult
    static func setKept(_ keep: Bool, tile: DockItem) -> Bool {
        guard let opened = openOptions(tile) else { return false }
        let (menu, options) = opened
        guard let item = options.first(where: { title($0) == keepTitle }) else { close(menu); return false }
        if isChecked(item) == keep { close(menu); return true }
        return press(item)
    }

    /// Takes an app's tile out of the Dock. Not running: "Remove from Dock" (with the Dock's poof).
    /// Running: it just stops being kept, and its tile goes when the app quits.
    @discardableResult
    static func unpinApp(at url: URL) -> Bool {
        guard let tile = DockAX.shared.item(for: url), let opened = openOptions(tile) else { return false }
        let (menu, options) = opened
        if let remove = options.first(where: { title($0) == removeTitle }) { return press(remove) }
        if let keep = options.first(where: { title($0) == keepTitle }) {
            if !isChecked(keep) { close(menu); return true }
            return press(keep)
        }
        close(menu)
        return false
    }

    /// Keeps a running app in the Dock (silent). It stays where it is, with the running apps.
    @discardableResult
    static func pinRunningApp(at url: URL) -> Bool {
        guard let tile = DockAX.shared.item(for: url) else { return false }
        return setKept(true, tile: tile)
    }

    // MARK: Moving a tile

    /// Slides a tile to the real pointer by dragging it with mouse events sent only to the Dock
    /// (the pointer itself doesn't move). The Dock puts a dragged tile under the actual pointer,
    /// whatever the events say, so this only runs while the pointer is on the Dock; if it leaves
    /// part-way, the drag is cancelled (Esc) and the tile stays where it was.
    static func moveTileToPointer(_ url: URL, completion: @escaping (Bool) -> Void) {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first,
              let tile = DockAX.shared.item(for: url), let pointer = pointerOnDock() else { completion(false); return }
        let start = CGPoint(x: tile.frame.midX, y: tile.frame.midY)
        if abs(start.x - pointer.x) < tile.frame.width, abs(start.y - pointer.y) < tile.frame.height {
            completion(true)   // already there
            return
        }
        let pid = dock.processIdentifier
        func post(_ type: CGEventType, _ p: CGPoint) {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.postToPid(pid)
        }
        let steps = 12
        func step(_ i: Int) {
            guard i <= steps else {
                if let now = pointerOnDock() {
                    post(.leftMouseUp, now)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { completion(true) }
                } else {
                    // Letting go off the Dock would drop the tile off it: cancel instead.
                    for down in [true, false] {
                        CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down)?.postToPid(pid)
                    }
                    post(.leftMouseUp, start)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { completion(false) }
                }
                return
            }
            let t = CGFloat(i) / CGFloat(steps)
            let target = pointerOnDock() ?? pointer
            // A small lift at the start, as a hand-made drag has.
            let lift: CGFloat = i < 3 ? CGFloat(i) * 3 : 6
            post(.leftMouseDragged, CGPoint(x: start.x + (target.x - start.x) * t,
                                            y: start.y + (target.y - start.y) * t - lift))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { step(i + 1) }
        }
        post(.leftMouseDown, start)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { step(1) }
    }

    /// The real pointer, if it's on the Dock (global, top-left origin).
    static func pointerOnDock() -> CGPoint? {
        guard let list = DockAX.shared.list else { return nil }
        let frame = AX.frame(list)
        let mouse = NSEvent.mouseLocation
        let point = CGPoint(x: mouse.x, y: (NSScreen.screens.first?.frame.height ?? 0) - mouse.y)
        return frame.width > 0 && frame.insetBy(dx: -4, dy: -4).contains(point) ? point : nil
    }

    // MARK: Folder tiles

    /// Puts a folder's tile in the Dock: its stub runs, so the Dock shows it like any open app,
    /// and "Keep in Dock" keeps it. Lands at the end of the Dock's apps.
    static func pinFolder(_ folder: Folder, completion: @escaping (Bool) -> Void) {
        withStub(at: folder.stubURL, folder: folder, quitAfter: false, completion: completion) { tile in
            setKept(true, tile: tile)
        }
    }

    /// Takes a folder's tile out of the Dock without the poof: its stub runs, stops being kept,
    /// and quits, and the tile slides away like any app that quits.
    static func unpinFolder(_ folder: Folder, tileURL: URL, completion: @escaping (Bool) -> Void) {
        withStub(at: tileURL, folder: folder, quitAfter: true, completion: completion) { tile in
            setKept(false, tile: tile)
        }
    }

    /// Runs the stub at `url` until the Dock shows it as a running app, does `work` on its tile,
    /// then lets it quit (or keep running as the folder's running indicator).
    private static func withStub(at url: URL, folder: Folder, quitAfter: Bool,
                                 completion: @escaping (Bool) -> Void, work: @escaping (DockItem) -> Bool) {
        guard FileManager.default.fileExists(atPath: url.path) else { completion(false); return }
        // A brand-new stub is still on its registration run: wait for it to finish.
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        if StubManager.registering.contains(path) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withStub(at: url, folder: folder, quitAfter: quitAfter, completion: completion, work: work)
            }
            return
        }
        StubManager.busy.insert(folder.id)
        func finish(_ ok: Bool) {
            StubManager.busy.remove(folder.id)
            if quitAfter {
                stubs(at: url, folder).forEach { $0.terminate() }
            } else {
                StubManager.syncIndicator(folder, running: StubManager.hasRunningApp(folder))
            }
            completion(ok)
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.addsToRecentItems = false
        config.arguments = ["--indicator"]
        NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
            DispatchQueue.main.async {
                guard let app, error == nil else {
                    log.error("couldn't launch stub \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
                    finish(false); return
                }
                waitForRunningTile(url: url, app: app, deadline: Date().addingTimeInterval(5)) { tile in
                    guard let tile else { log.error("stub tile never showed as running: \(url.path, privacy: .public)"); finish(false); return }
                    var ok = work(tile)
                    if !ok {
                        // The Dock may still have been settling; one more try.
                        usleep(300_000)
                        if let tile = DockAX.shared.item(for: url) { ok = work(tile) }
                    }
                    log.info("\(quitAfter ? "unpin" : "pin", privacy: .public) \(url.lastPathComponent, privacy: .public): \(ok ? "ok" : "failed", privacy: .public)")
                    // Let the Dock finish with its menu before the stub quits.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { finish(ok) }
                }
            }
        }
    }

    private static func stubs(at url: URL, _ folder: Folder) -> [NSRunningApplication] {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return NSRunningApplication.runningApplications(withBundleIdentifier: folder.bundleIdentifier).filter {
            $0.bundleURL?.standardizedFileURL.resolvingSymlinksInPath().path == path
        }
    }

    private static func waitForRunningTile(url: URL, app: NSRunningApplication, deadline: Date,
                                           settle: TimeInterval = 0.25, then: @escaping (DockItem?) -> Void) {
        if app.isFinishedLaunching, let tile = DockAX.shared.item(for: url),
           (AX.value(tile.element, "AXIsApplicationRunning") as Bool?) == true {
            // A moment for the Dock to switch the tile to its running-app menu.
            DispatchQueue.main.asyncAfter(deadline: .now() + settle) { then(DockAX.shared.item(for: url)) }
            return
        }
        guard Date() < deadline, !app.isTerminated else { then(nil); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            waitForRunningTile(url: url, app: app, deadline: deadline, settle: settle, then: then)
        }
    }

    // MARK: A new folder right where you are

    /// Puts a folder's tile in the Dock right under the pointer (which must be on the Dock): its
    /// stub runs, so the Dock adds it like any app that opens, and it's slid under the pointer at
    /// once. Moving an open app's tile also keeps it in the Dock, so no menu is needed.
    /// `completion(false)` (with nothing changed) if the pointer isn't on the Dock.
    static func placeFolderAtPointer(_ folder: Folder, completion: @escaping (Bool) -> Void) {
        let url = folder.stubURL
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        guard pointerOnDock() != nil, FileManager.default.fileExists(atPath: url.path) else { completion(false); return }
        if StubManager.registering.contains(path) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { placeFolderAtPointer(folder, completion: completion) }
            return
        }
        StubManager.busy.insert(folder.id)
        func finish(_ ok: Bool) {
            StubManager.busy.remove(folder.id)
            StubManager.syncIndicator(folder, running: StubManager.hasRunningApp(folder))
            completion(ok)
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.addsToRecentItems = false
        config.arguments = ["--indicator"]
        NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
            DispatchQueue.main.async {
                guard let app, error == nil else { finish(false); return }
                waitForRunningTile(url: url, app: app, deadline: Date().addingTimeInterval(5), settle: 0.05) { tile in
                    guard tile != nil else { finish(false); return }
                    moveTileToPointer(url) { moved in
                        if moved {
                            confirmKept(url, deadline: Date().addingTimeInterval(6)) { finish(true) }
                        } else {
                            // The pointer left the Dock: keep it where it landed instead.
                            if let tile = DockAX.shared.item(for: url) { setKept(true, tile: tile) }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { finish(false) }
                        }
                    }
                }
            }
        }
    }

    /// Once the Dock has saved the moved tile as kept, done; if it hasn't after a few seconds,
    /// keep it from its menu.
    private static func confirmKept(_ url: URL, deadline: Date, then: @escaping () -> Void) {
        if DockPrefs.savedContains(url) { then(); return }
        guard Date() < deadline else {
            if let tile = DockAX.shared.item(for: url) { setKept(true, tile: tile) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { then() }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { confirmKept(url, deadline: deadline, then: then) }
    }
}

// MARK: - Changes saved for a quiet moment

/// Dock changes that need a restart (new names, exact positions, apps that aren't running) are
/// saved up and applied when nobody can see the Dock restart: when the Mac locks or its display
/// sleeps. "Update Now" in Settings applies them straight away.
enum DockSettle {
    static let didChange = Notification.Name("DockFoldersSettleDidChange")

    private static var defaults: UserDefaults { .standard }

    /// Folder id → where in the Dock's apps it should end up.
    private static var placements: [String: Int] {
        get { defaults.dictionary(forKey: "pendingPlacements") as? [String: Int] ?? [:] }
        set { defaults.set(newValue, forKey: "pendingPlacements") }
    }

    /// App path → the folder whose tile it goes next to ("" for the end of the Dock's apps).
    private static var appsToAdd: [String: String] {
        get { defaults.dictionary(forKey: "pendingDockApps") as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: "pendingDockApps") }
    }

    static var hasPending: Bool { FolderActions.hasPendingRenames || !placements.isEmpty || !appsToAdd.isEmpty }

    static func place(_ folderID: String, at index: Int) {
        placements[folderID] = index
        changed()
    }

    static func addApp(_ url: URL, near folderID: String) {
        appsToAdd[url.path] = folderID
        changed()
    }

    /// A folder left the Dock (or was deleted): nothing to place, and its apps go at the end.
    static func forget(_ folderID: String) {
        placements.removeValue(forKey: folderID)
        appsToAdd = appsToAdd.mapValues { $0 == folderID ? "" : $0 }
        changed()
    }

    static func changed() {
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    static func startObserving() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { _ in applyIfPending() }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in applyIfPending() }
        }
    }

    static func applyIfPending() {
        if hasPending { apply() }
    }

    /// Everything waiting, in one restart.
    static func apply() {
        let renames = FolderActions.takePendingRenames()
        let places = placements
        let adds = appsToAdd
        placements = [:]
        appsToAdd = [:]
        let store = FolderStore.shared
        DockPrefs.modify(then: {
            FolderActions.finishRenames(renames)
            EventInterceptor.shared.update(folders: store.folders)
            changed()
            NotificationCenter.default.post(name: FolderStore.didChange, object: nil)
        }) { tiles in
            for (id, old) in renames {
                guard let folder = store.folder(id: id), let index = DockPrefs.index(of: old, in: tiles) else { continue }
                tiles[index] = DockPrefs.folderTile(folder)
            }
            for (id, target) in places {
                guard let folder = store.folder(id: id), let index = DockPrefs.index(of: folder.stubURL, in: tiles) else { continue }
                let tile = tiles.remove(at: index)
                tiles.insert(tile, at: min(max(target, 0), tiles.count))
            }
            for (path, id) in adds {
                let url = URL(fileURLWithPath: path)
                guard FileManager.default.fileExists(atPath: path), DockPrefs.index(of: url, in: tiles) == nil else { continue }
                let tile = DockPrefs.appTile(for: url)
                if let folder = store.folder(id: id), let index = DockPrefs.index(of: folder.stubURL, in: tiles) {
                    tiles.insert(tile, at: index + 1)
                } else {
                    tiles.append(tile)
                }
            }
        }
    }
}
