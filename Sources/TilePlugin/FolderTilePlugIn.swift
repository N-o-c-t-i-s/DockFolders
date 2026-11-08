import AppKit

/// Loaded by the Dock (com.apple.dock.external.extra) for each folder stub in the Dock.
/// It just shows the tile image the agent renders, and redraws when the agent says so.
///
/// Every folder stub carries its own copy of this plug-in, and the Dock loads them all into
/// one process. To keep their Objective-C class names unique, the agent patches the
/// placeholder below with the folder id when it creates a stub (see StubManager).
@objc(DFTile_ZZZZZZZZZZZZZZZZ)
final class FolderTilePlugIn: NSObject, NSDockTilePlugIn {
    private var dockTile: NSDockTile?
    private var observer: NSObjectProtocol?

    /// Which tile image to show. Stable per stub slot: the Dock may keep a slot's plug-in loaded
    /// after its folder is deleted and reuse it for the next folder in that slot.
    private lazy var tileKey: String = {
        let bundle = Bundle(for: FolderTilePlugIn.self)
        return bundle.object(forInfoDictionaryKey: DFShared.tileKeyInfoKey) as? String
            ?? bundle.object(forInfoDictionaryKey: DFShared.folderIDInfoKey) as? String ?? ""
    }()

    func setDockTile(_ dockTile: NSDockTile?) {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
        self.dockTile = dockTile
        guard dockTile != nil else { return }

        let id = tileKey
        observer = DistributedNotificationCenter.default().addObserver(
            forName: DFShared.tileChangedNotification, object: nil, queue: .main
        ) { [weak self] note in
            let target = note.object as? String
            if target == nil || target == "*" || target == id { self?.redraw() }
        }
        redraw()
    }

    private func redraw() {
        guard let dockTile else { return }
        guard let image = NSImage(contentsOf: DFShared.tileImageURL(for: tileKey)) else {
            dockTile.contentView = nil
            dockTile.display()
            return
        }
        let view = NSImageView(frame: NSRect(origin: .zero, size: dockTile.size))
        view.imageScaling = .scaleProportionallyUpOrDown
        view.image = image
        dockTile.contentView = view
        dockTile.display()
    }
}
