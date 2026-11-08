import AppKit

/// Drag an app from the Dock onto a folder to put it in: hold it over the folder for a moment
/// and the folder springs open (outlined, ready for it); let go on the folder or in it and the
/// app goes in. The Dock does the dragging; this only watches (through the event tap).
///
/// A quick pass over a folder doesn't count, so rearranging the Dock works as usual.
final class DockDragCollector {
    static let shared = DockDragCollector()

    private var dragged: DockItem?
    private var lastPoint: CGPoint = .zero
    /// Folder tiles where they were when the drag started: the Dock slides tiles aside as you
    /// drag, so this is where you aim. Global, top-left-origin coordinates.
    private var restingFrames: [(id: String, frame: CGRect)] = []
    /// The same tiles where they are now (refreshed a few times a second).
    private var currentFrames: [(id: String, frame: CGRect)] = []
    private var lastRefresh = Date.distantPast
    private var hoverID: String?
    private var hoverToken = 0
    /// The folder that sprang open for this drag.
    private var openFolderID: String?

    private static let springDelay: TimeInterval = 0.35

    // MARK: Drag (from the event tap, on the main thread)

    func began(_ item: DockItem) {
        dragged = item
        openFolderID = nil
        hoverID = nil
        restingFrames = folderTileFrames()
        currentFrames = restingFrames
        lastRefresh = Date()
    }

    func moved(to point: CGPoint) {
        guard dragged != nil else { return }
        lastPoint = point
        if Date().timeIntervalSince(lastRefresh) > 0.1 {
            currentFrames = folderTileFrames()
            lastRefresh = Date()
        }
        let panel = FolderPanelController.shared
        if let open = openFolderID {
            panel.setDropTargeted(panel.folderID == open && (panel.popupContains(cocoa(point)) || folder(at: point) == open))
            return
        }
        let over = folder(at: point)
        guard over != hoverID else { return }
        hoverID = over
        hoverToken += 1
        guard let over else { return }
        // Held there (even without moving): spring the folder open.
        let token = hoverToken
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.springDelay) { [weak self] in
            guard let self, self.dragged != nil, self.hoverToken == token, self.hoverID == over,
                  self.folder(at: self.lastPoint) == over else { return }
            self.openFolderID = over
            panel.show(folderID: over, item: nil)
            panel.heldForDrop = true
            panel.setDropTargeted(true)
        }
    }

    func ended(at point: CGPoint) {
        let panel = FolderPanelController.shared
        defer {
            dragged = nil
            openFolderID = nil
            hoverID = nil
            hoverToken += 1
            panel.heldForDrop = false
            panel.setDropTargeted(false)
        }
        guard let url = dragged?.url, let open = openFolderID, panel.folderID == open,
              panel.popupContains(cocoa(point)) || folder(at: point) == open else { return }
        FolderActions.dropFromDock(url, into: open)
    }

    // MARK: Where the folders are

    private func folder(at point: CGPoint) -> String? {
        // The middle of the tile (not its edges, which are where you'd aim to drop beside it).
        func hit(_ frames: [(id: String, frame: CGRect)]) -> String? {
            frames.first { $0.frame.insetBy(dx: $0.frame.width * 0.18, dy: -8).contains(point) }?.id
        }
        return hit(restingFrames) ?? hit(currentFrames)
    }

    private func folderTileFrames() -> [(id: String, frame: CGRect)] {
        let items = DockAX.shared.items
        return FolderStore.shared.folders.compactMap { folder in
            let path = FolderActions.dockURL(for: folder).standardizedFileURL.resolvingSymlinksInPath().path
            guard let tile = items.first(where: { $0.url?.standardizedFileURL.resolvingSymlinksInPath().path == path }),
                  tile.frame.width > 0 else { return nil }
            return (folder.id, tile.frame)
        }
    }

    private func cocoa(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: (NSScreen.screens.first?.frame.height ?? 0) - p.y)
    }
}
