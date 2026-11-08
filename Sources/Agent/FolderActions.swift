import AppKit
import UniformTypeIdentifiers

/// Everything that creates, edits or removes folders (and the matching Dock tiles).
enum FolderActions {
    private static var store: FolderStore { .shared }

    // MARK: Creating

    /// New folders start out called "Folder"; you can name them in Settings.
    static let folderName = "Folder"

    static func newFolder(with appURL: URL) {
        let folder = store.create(name: folderName, apps: [appURL])
        do {
            try StubManager.install(folder)
        } catch {
            store.delete(folder.id)
            Prompt.error("Couldn’t create the folder.", error)
            return
        }
        EventInterceptor.shared.update(folders: store.folders)
        DockPrefs.modify { apps in
            let tile = DockPrefs.folderTile(folder)
            if let index = DockPrefs.index(of: appURL, in: apps) { apps[index] = tile } else { apps.append(tile) }
        }
    }

    /// Creates a folder and adds its tile to the end of the Dock's app section.
    static func createFolder(apps: [URL]) {
        let folder = store.create(name: folderName, apps: apps.filter { $0.pathExtension == "app" })
        do {
            try StubManager.install(folder)
        } catch {
            store.delete(folder.id)
            Prompt.error("Couldn’t create the folder.", error)
            return
        }
        EventInterceptor.shared.update(folders: store.folders)
        DockPrefs.modify { $0.append(DockPrefs.folderTile(folder)) }
    }

    /// Re-adds folders whose tiles were dragged out of the Dock (their contents were kept).
    static func putBackInDock(_ folderIDs: [String]) {
        // Only folders with something in them belong in the Dock.
        let folders = folderIDs.compactMap(store.folder(id:))
            .filter { !$0.apps.isEmpty && !DockPrefs.containsTile(for: dockURL(for: $0)) }
        guard !folders.isEmpty else { return }
        for folder in folders where !FileManager.default.fileExists(atPath: folder.stubURL.path) {
            try? StubManager.install(folder)
        }
        DockPrefs.modify { tiles in
            tiles.append(contentsOf: folders.map(DockPrefs.folderTile))
        }
    }

    // MARK: Adding / removing apps

    static func add(_ appURLs: [URL], to folderID: String, removeFromDock: Bool) {
        let apps = appURLs.filter { $0.pathExtension == "app" }
        guard !apps.isEmpty, let before = store.folder(id: folderID),
              let folder = store.update(folderID, { $0.apps += apps.map(\.path) }) else { return }
        StubManager.refreshTile(folder)
        FolderPanelController.shared.reload()

        // A folder joins the Dock once it has its first app (unless you turned Show in Dock off).
        let joinDock = before.apps.isEmpty && !folder.apps.isEmpty && folder.keepOutOfDock != true
            && !DockPrefs.containsTile(for: dockURL(for: folder))
        let leavingDock = removeFromDock ? apps.filter(DockPrefs.containsTile(for:)) : []
        guard joinDock || !leavingDock.isEmpty else { return }
        FolderPanelController.shared.close()
        if joinDock, !FileManager.default.fileExists(atPath: folder.stubURL.path) { try? StubManager.install(folder) }
        DockPrefs.modify { tiles in
            for url in leavingDock {
                if let index = DockPrefs.index(of: url, in: tiles) { tiles.remove(at: index) }
            }
            if joinDock { tiles.append(DockPrefs.folderTile(folder)) }
        }
    }

    static func chooseApps(for folderID: String) {
        guard let folder = store.folder(id: folderID) else { return }
        let previous = NSWorkspace.shared.frontmostApplication
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.title = "Add Apps to “\(folder.name)”"
        panel.prompt = "Add"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let response = panel.runModal()
        if !SettingsController.shared.isVisible { previous?.activate() }
        if response == .OK { add(panel.urls, to: folderID, removeFromDock: false) }
    }

    static func removeApp(_ url: URL, from folderID: String) {
        guard let folder = store.update(folderID, { $0.apps.removeAll { $0 == url.path } }) else { return }
        StubManager.refreshTile(folder)
        FolderPanelController.shared.reload()
        // Nothing left to show: the folder leaves the Dock until an app is added again.
        if folder.apps.isEmpty { removeFromDock(folderID) }
    }

    static func moveAppToDock(_ url: URL, from folderID: String) {
        guard let folder = store.update(folderID, { $0.apps.removeAll { $0 == url.path } }) else { return }
        StubManager.refreshTile(folder)
        FolderPanelController.shared.close()
        let tileURL = dockURL(for: folder)
        let addApp = !DockPrefs.containsTile(for: url)
        // Its last app: the app takes the folder's place in the Dock.
        let emptied = folder.apps.isEmpty && DockPrefs.containsTile(for: tileURL)
        guard addApp || emptied else { return }
        if emptied { StubManager.stopIndicator(folder) }
        let oldStub = emptied ? pendingRenames.removeValue(forKey: folderID) : nil
        DockPrefs.modify(then: {
            if let oldStub, oldStub.path != folder.stubURL.path { removeStub(at: oldStub) }
        }) { tiles in
            if addApp {
                let tile = DockPrefs.appTile(for: url)
                if let index = DockPrefs.index(of: tileURL, in: tiles) { tiles.insert(tile, at: index + 1) } else { tiles.append(tile) }
            }
            if emptied, let index = DockPrefs.index(of: tileURL, in: tiles) { tiles.remove(at: index) }
        }
    }

    /// Empty folders have nothing to show, so they're kept out of the Dock.
    static func removeEmptyFoldersFromDock() {
        let empty = store.folders.filter { $0.apps.isEmpty && DockPrefs.containsTile(for: dockURL(for: $0)) }
        guard !empty.isEmpty else { return }
        empty.forEach(StubManager.stopIndicator)
        DockPrefs.modify { tiles in
            for folder in empty {
                if let index = DockPrefs.index(of: dockURL(for: folder), in: tiles) { tiles.remove(at: index) }
            }
        }
    }

    // MARK: Folder-level

    // MARK: Renaming (from Settings)

    /// Renames waiting to reach the Dock: folder id → the stub its Dock tile still points at.
    /// The Dock only reads names when it starts, so they're applied together, in one restart,
    /// when Settings closes.
    private static var pendingRenames: [String: URL] = [:]

    static func hasPendingRename(_ folderID: String) -> Bool { pendingRenames[folderID] != nil }

    /// The stub the folder's Dock tile currently points at.
    static func dockURL(for folder: Folder) -> URL { pendingRenames[folder.id] ?? folder.stubURL }

    static func rename(_ folderID: String, to newName: String) {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let folder = store.folder(id: folderID), name != folder.name else { return }
        let tileURL = dockURL(for: folder)
        let inDock = DockPrefs.containsTile(for: tileURL)
        let previousStub = folder.stubURL
        let stubName = store.uniqueStubName(for: name, excluding: folderID)
        // Record which stub the Dock tile still uses *before* the store announces the change,
        // so anything refreshing right then (Settings) still sees the folder as in the Dock.
        let newStubPath = DFShared.stubsDirectory.appendingPathComponent(stubName, isDirectory: true).path
        if inDock, tileURL.path != newStubPath {
            pendingRenames[folderID] = tileURL
        } else {
            pendingRenames.removeValue(forKey: folderID)   // back to the name the Dock already shows
        }
        guard let renamed = store.update(folderID, { $0.name = name; $0.stubName = stubName }) else { return }
        do {
            try StubManager.install(renamed)
        } catch {
            Prompt.error("Couldn’t rename the folder.", error)
            return
        }
        // A stub from an earlier rename that never reached the Dock can go right away.
        if previousStub.path != tileURL.path, previousStub.path != renamed.stubURL.path {
            removeStub(at: previousStub)
        }
        if !inDock, tileURL.path != renamed.stubURL.path {
            removeStub(at: tileURL)
        }
        EventInterceptor.shared.update(folders: store.folders)
        FolderPanelController.shared.close()
        NotificationCenter.default.post(name: FolderStore.didChange, object: nil)
    }

    /// Picks up renames that never reached the Dock (Dock Folders quit before Settings closed):
    /// the tile still points at the folder's old stub, so send the new name now.
    static func recoverPendingRenames() {
        for folder in store.folders where pendingRenames[folder.id] == nil {
            guard !DockPrefs.containsTile(for: folder.stubURL),
                  let tileURL = DockPrefs.tileURL(bundleID: folder.bundleIdentifier),
                  tileURL.deletingLastPathComponent().resolvingSymlinksInPath().path
                    == DFShared.stubsDirectory.resolvingSymlinksInPath().path else { continue }
            pendingRenames[folder.id] = tileURL
        }
        guard !pendingRenames.isEmpty else { return }
        EventInterceptor.shared.update(folders: store.folders)
        applyPendingRenames()
    }

    /// Sends pending names to the Dock (one restart, once the Dock has slid out of sight).
    static func applyPendingRenames() {
        guard !pendingRenames.isEmpty else { return }
        let changes = pendingRenames
        pendingRenames.removeAll()
        let currentStubs = Set(store.folders.map { $0.stubURL.path })
        DockPrefs.modify(restartWhenHidden: true, then: {
            for old in changes.values where !currentStubs.contains(old.path) { removeStub(at: old) }
            EventInterceptor.shared.update(folders: store.folders)
        }) { tiles in
            for (id, old) in changes {
                guard let folder = store.folder(id: id), let index = DockPrefs.index(of: old, in: tiles) else { continue }
                tiles[index] = DockPrefs.folderTile(folder)
            }
        }
    }

    private static func removeStub(at url: URL) {
        LSRegisterURL(url as CFURL, false)
        try? FileManager.default.removeItem(at: url)
    }

    /// Takes a folder's tile out of the Dock but keeps the folder (it can be put back from Settings).
    static func removeFromDock(_ folderID: String) {
        guard let folder = store.folder(id: folderID) else { return }
        let tileURL = dockURL(for: folder)
        guard DockPrefs.containsTile(for: tileURL) else { return }
        FolderPanelController.shared.close()
        StubManager.stopIndicator(folder)
        if let old = pendingRenames.removeValue(forKey: folderID), old.path != folder.stubURL.path {
            DockPrefs.modify(then: { removeStub(at: old) }) { tiles in
                if let index = DockPrefs.index(of: tileURL, in: tiles) { tiles.remove(at: index) }
            }
            return
        }
        DockPrefs.modify { tiles in
            if let index = DockPrefs.index(of: tileURL, in: tiles) { tiles.remove(at: index) }
        }
    }

    /// Deletes a folder entirely (its apps stay installed).
    static func delete(_ folderID: String) {
        guard let folder = store.folder(id: folderID) else { return }
        FolderPanelController.shared.close()
        let tileURL = dockURL(for: folder)
        let old = pendingRenames.removeValue(forKey: folderID)
        if DockPrefs.containsTile(for: tileURL) {
            DockPrefs.modify { tiles in
                if let index = DockPrefs.index(of: tileURL, in: tiles) { tiles.remove(at: index) }
            }
        }
        if let old, old.path != folder.stubURL.path { removeStub(at: old) }
        StubManager.remove(folder)
        store.delete(folderID)
    }

    /// Sets a folder's app order (from Settings); the Dock icon's 2×2 preview follows.
    static func setAppOrder(_ folderID: String, _ urls: [URL]) {
        guard let folder = store.folder(id: folderID) else { return }
        let ordered = urls.map(\.path)
        let rest = folder.apps.filter { !ordered.contains($0) }
        guard ordered + rest != folder.apps,
              let updated = store.update(folderID, { $0.apps = ordered + rest }) else { return }
        StubManager.refreshTile(updated)
        FolderPanelController.shared.reload()
    }

    /// Reorders a folder's apps (from Settings); the Dock icon's 2×2 preview follows.
    static func moveApps(in folderID: String, from offsets: IndexSet, to destination: Int) {
        guard let folder = store.update(folderID, { folder in
            var apps = folder.apps
            let moving = offsets.map { apps[$0] }
            for index in offsets.sorted(by: >) { apps.remove(at: index) }
            let insertAt = destination - offsets.filter { $0 < destination }.count
            apps.insert(contentsOf: moving, at: max(0, min(insertAt, apps.count)))
            folder.apps = apps
        }) else { return }
        StubManager.refreshTile(folder)
        FolderPanelController.shared.reload()
    }

    /// An empty new folder. It joins the Dock (at the end of its apps) once it has an app.
    @discardableResult
    static func newEmptyFolder() -> String? {
        let folder = store.create(name: folderName, apps: [])
        do {
            try StubManager.install(folder)
        } catch {
            store.delete(folder.id)
            Prompt.error("Couldn’t create the folder.", error)
            return nil
        }
        EventInterceptor.shared.update(folders: store.folders)
        return folder.id
    }

    /// Puts the folder's apps back in the Dock where the folder was, then deletes the folder.
    static func ungroup(_ folderID: String) {
        guard let folder = store.folder(id: folderID) else { return }
        FolderPanelController.shared.close()
        DockPrefs.modify { tiles in
            let appTiles = folder.appURLs
                .filter { FileManager.default.fileExists(atPath: $0.path) && DockPrefs.index(of: $0, in: tiles) == nil }
                .map(DockPrefs.appTile(for:))
            if let index = DockPrefs.index(of: folder.stubURL, in: tiles) {
                tiles.replaceSubrange(index...index, with: appTiles)
            } else {
                tiles.append(contentsOf: appTiles)
            }
        }
        StubManager.remove(folder)
        store.delete(folderID)
    }

    static func remove(_ folderID: String) {
        guard let folder = store.folder(id: folderID),
              Prompt.confirm(title: "Remove “\(folder.name)” from the Dock?",
                             message: "The apps inside stay installed. Only the folder is removed.",
                             confirm: "Remove Folder",
                             icon: NSImage(contentsOf: DFShared.tileImageURL(for: folderID))) else { return }
        FolderPanelController.shared.close()
        DockPrefs.modify { tiles in
            if let index = DockPrefs.index(of: folder.stubURL, in: tiles) { tiles.remove(at: index) }
        }
        StubManager.remove(folder)
        store.delete(folderID)
    }

    // MARK: Helpers

}

// MARK: - Small modal prompts

enum Prompt {
    static func text(title: String, message: String?, defaultValue: String, confirm: String, icon: NSImage?) -> String? {
        let previous = NSWorkspace.shared.frontmostApplication
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        if let message { alert.informativeText = message }
        if let icon { alert.icon = icon }
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: defaultValue)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        let response = alert.runModal()
        previous?.activate()
        guard response == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func confirm(title: String, message: String, confirm: String, icon: NSImage?) -> Bool {
        let previous = NSWorkspace.shared.frontmostApplication
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        if let icon { alert.icon = icon }
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        previous?.activate()
        return response == .alertFirstButtonReturn
    }

    static func error(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        NSApp.activate()
        alert.runModal()
    }
}
