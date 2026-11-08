import AppKit

/// Dragging an app's tile in the Dock (the Dock does the dragging; this only watches, through the
/// event tap):
///  • Hold it over a folder for a moment and the folder springs open (outlined); let go on the
///    folder or in it, and the app goes in.
///  • Hold it over another app and a "Create Folder" tag appears above that app, like the Dock's
///    own name tags; let go and the two become a folder, in their place.
///
/// Targets are where tiles are right now (the Dock slides them aside as you drag, opening a gap
/// under the pointer; a gap is never a target). A quick pass over a tile doesn't count either, so
/// rearranging the Dock works as usual.
final class DockDragCollector {
    static let shared = DockDragCollector()

    private enum Target: Equatable {
        case folder(String)
        case app(URL)
    }

    private struct Tile {
        let target: Target
        let frame: CGRect   // global, top-left origin
    }

    private var dragged: DockItem?
    private var lastPoint: CGPoint = .zero
    /// Folder and app tiles where they are now (refreshed many times a second).
    private var currentTiles: [Tile] = []
    private var lastRefresh = Date.distantPast
    private var hover: Target?
    private var hoverToken = 0
    /// The folder that sprang open for this drag.
    private var openFolderID: String?
    /// The app showing "Create Folder".
    private var armedApp: URL?

    private static let holdDelay: TimeInterval = 0.18

    // MARK: Drag (from the event tap, on the main thread)

    func began(_ item: DockItem) {
        dragged = item
        openFolderID = nil
        armedApp = nil
        hover = nil
        currentTiles = tiles(excluding: item.url)
        lastRefresh = Date()
    }

    func moved(to point: CGPoint) {
        guard let dragged else { return }
        lastPoint = point
        refreshTiles()
        let panel = FolderPanelController.shared
        if let open = openFolderID {
            panel.setDropTargeted(panel.folderID == open && (panel.popupContains(cocoa(point)) || target(at: point) == .folder(open)))
            return
        }
        let over = target(at: point)
        if let armed = armedApp, over == .app(armed) {
            if let frame = currentFrame(of: .app(armed)) { DockTag.shared.move(toTile: frame) }
            return
        }
        guard over != hover else { return }
        hover = over
        hoverToken += 1
        if armedApp != nil { armedApp = nil; DockTag.shared.hide() }
        guard let over else { return }
        // Held there (even without moving): act on it.
        let token = hoverToken
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdDelay) { [weak self] in
            guard let self, self.dragged != nil, self.hoverToken == token else { return }
            // Still over that tile where it is now (not a gap it slid away from)?
            self.refreshTiles(force: true)
            guard self.target(at: self.lastPoint) == over else { return }
            switch over {
            case .folder(let id):
                self.openFolderID = id
                panel.show(folderID: id, item: nil)
                panel.heldForDrop = true
                panel.setDropTargeted(true)
            case .app(let url):
                guard let frame = self.currentFrame(of: over) else { return }
                self.armedApp = url
                DockTag.shared.show("Create Folder", forTile: frame)
            }
        }
    }

    func ended(at point: CGPoint) {
        let panel = FolderPanelController.shared
        let url = dragged?.url
        let open = openFolderID
        let armed = armedApp
        dragged = nil
        openFolderID = nil
        armedApp = nil
        hover = nil
        hoverToken += 1
        panel.heldForDrop = false
        panel.setDropTargeted(false)
        DockTag.shared.hide()
        guard let url else { return }

        if let open, panel.folderID == open {
            let inPopup = panel.popupContains(cocoa(point))
            guard inPopup || target(at: point) == .folder(open) else { return }
            FolderActions.dropFromDock(url, into: open, releasedOnDock: !inPopup)
        } else if let armed, target(at: point) == .app(armed) {
            FolderActions.combineInDock(dragged: url, onto: armed)
        }
    }

    // MARK: Where the tiles are

    private func refreshTiles(force: Bool = false) {
        guard let dragged, force || Date().timeIntervalSince(lastRefresh) > 0.05 else { return }
        currentTiles = tiles(excluding: dragged.url)
        lastRefresh = Date()
    }

    private func target(at point: CGPoint) -> Target? {
        // The middle of a tile where it is now (not its edges, where you'd aim to drop beside it).
        currentTiles.first { $0.frame.insetBy(dx: $0.frame.width * 0.2, dy: -8).contains(point) }?.target
    }

    private func currentFrame(of target: Target) -> CGRect? {
        currentTiles.first { $0.target == target }?.frame
    }

    /// Folders and ordinary apps in the Dock (not Finder, the Apps launcher, or the dragged app).
    private func tiles(excluding draggedURL: URL?) -> [Tile] {
        func path(_ url: URL?) -> String? { url?.standardizedFileURL.resolvingSymlinksInPath().path }
        let folders = Dictionary(FolderStore.shared.folders.compactMap { folder in
            path(FolderActions.dockURL(for: folder)).map { ($0, folder.id) }
        }, uniquingKeysWith: { first, _ in first })
        let skip = path(draggedURL)
        return DockAX.shared.items.compactMap { item in
            guard item.frame.width > 0, let url = item.url, let p = path(url), p != skip else { return nil }
            if let id = folders[p] { return Tile(target: .folder(id), frame: item.frame) }
            guard item.subrole == "AXApplicationDockItem", url.pathExtension == "app" else { return nil }
            let bundleID = Bundle(url: url)?.bundleIdentifier
            guard bundleID != "com.apple.finder", bundleID != "com.apple.apps.launcher" else { return nil }
            return Tile(target: .app(url), frame: item.frame)
        }
    }

    private func cocoa(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: (NSScreen.screens.first?.frame.height ?? 0) - p.y)
    }
}
