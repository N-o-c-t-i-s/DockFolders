import AppKit
import SwiftUI

/// While you drag an app up out of the Dock, every folder in the Dock shows a small glass target
/// above it. Let go on one and the app moves into that folder: the Dock takes its tile out (with
/// its usual poof, as for any app dragged off the Dock) and the folder gains it.
final class DropTargetController {
    static let shared = DropTargetController()

    private final class Target {
        let folderID: String
        let panel: NSPanel
        let state = DropTargetState()
        /// Where the pill is (Cocoa coordinates), a little enlarged so it's easy to hit.
        var hitFrame: CGRect = .zero

        init(folderID: String, panel: NSPanel) {
            self.folderID = folderID
            self.panel = panel
        }
    }

    private var targets: [String: Target] = [:]
    private var dragged: DockItem?
    /// The Dock's resting inner edge (global, top-left origin), taken when the drag starts.
    private var dockEdge: CGFloat?
    private var showing = false
    private var lastLayout = Date.distantPast

    private var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    // MARK: Drag (from the event tap, on the main thread)

    func began(_ item: DockItem) {
        guard !FolderStore.shared.folders.isEmpty else { return }
        dragged = item
        dockEdge = DockAX.shared.restingInnerEdge()
        showing = false
    }

    func moved(to point: CGPoint) {
        guard dragged != nil else { return }
        let outside = isOutsideDock(point)
        if outside != showing {
            showing = outside
            if outside { layout() }
            for target in targets.values { target.state.visible = outside }
        } else if outside, Date().timeIntervalSince(lastLayout) > 0.3 {
            layout()   // the Dock closes the gap the dragged tile left, so follow its tiles
        }
        let p = cocoa(point)
        for target in targets.values { target.state.hovered = showing && target.hitFrame.contains(p) }
    }

    func ended(at point: CGPoint) {
        defer { tearDown() }
        guard let dragged, let url = dragged.url, showing else { return }
        let p = cocoa(point)
        guard let target = targets.values.first(where: { $0.panel.isVisible && $0.hitFrame.contains(p) }) else { return }
        FolderActions.dropFromDock(url, into: target.folderID)
    }

    // MARK: Targets

    private func isOutsideDock(_ point: CGPoint) -> Bool {
        guard let edge = dockEdge else { return false }
        switch CoreDock.orientation {
        case .bottom: return point.y < edge - 12
        case .left: return point.x > edge + 12
        case .right: return point.x < edge - 12
        }
    }

    private func layout() {
        lastLayout = Date()
        let items = DockAX.shared.items
        var seen = Set<String>()
        for folder in FolderStore.shared.folders where !folder.apps.isEmpty {
            let tileURL = FolderActions.dockURL(for: folder).standardizedFileURL.resolvingSymlinksInPath().path
            guard let tile = items.first(where: { $0.url?.standardizedFileURL.resolvingSymlinksInPath().path == tileURL }),
                  tile.frame.width > 0 else { continue }
            seen.insert(folder.id)
            let target = targets[folder.id] ?? makeTarget(for: folder)
            place(target, above: tile.frame)
            if !target.panel.isVisible { target.panel.orderFrontRegardless() }
            target.state.visible = showing
        }
        for (id, target) in targets where !seen.contains(id) {
            target.panel.orderOut(nil)
            targets.removeValue(forKey: id)
        }
    }

    private func makeTarget(for folder: Folder) -> Target {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 80),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true   // the drag belongs to the Dock; we only watch it
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let target = Target(folderID: folder.id, panel: panel)
        panel.contentView = NSHostingView(rootView: DropTargetView(
            name: folder.name, icon: NSImage(contentsOf: DFShared.tileImageURL(for: folder.id)), state: target.state
        ))
        targets[folder.id] = target
        return target
    }

    /// Centres the target a little beyond the tile (above it for a bottom Dock), clear of the
    /// Dock's own name label and far enough out that letting go there takes the tile off the Dock.
    private func place(_ target: Target, above tileAX: CGRect) {
        let tile = cocoa(tileAX)
        let reach = tile.height * 0.9 + 26
        let center: CGPoint
        switch CoreDock.orientation {
        case .bottom: center = CGPoint(x: tile.midX, y: tile.maxY + reach)
        case .left: center = CGPoint(x: tile.maxX + reach + 40, y: tile.midY)
        case .right: center = CGPoint(x: tile.minX - reach - 40, y: tile.midY)
        }
        let size = target.panel.frame.size
        target.panel.setFrameOrigin(NSPoint(x: (center.x - size.width / 2).rounded(), y: (center.y - size.height / 2).rounded()))
        let pillWidth = min(size.width, DockLabel.width(for: FolderStore.shared.folder(id: target.folderID)?.name ?? "") + 30)
        target.hitFrame = CGRect(x: center.x - pillWidth / 2, y: center.y - 15, width: pillWidth, height: 30).insetBy(dx: -14, dy: -14)
    }

    private func tearDown() {
        dragged = nil
        showing = false
        for target in targets.values { target.state.visible = false; target.state.hovered = false }
        let current = targets
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.dragged == nil else { return }
            for target in current.values { target.panel.orderOut(nil) }
            self.targets.removeAll()
        }
    }

    /// Global top-left-origin → Cocoa screen coordinates.
    private func cocoa(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: primaryHeight - p.y) }
    private func cocoa(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height) }
}

final class DropTargetState: ObservableObject {
    @Published var visible = false
    @Published var hovered = false
}

/// A glass pill with the folder's icon and name, like the Dock's own name label.
private struct DropTargetView: View {
    let name: String
    let icon: NSImage?
    @ObservedObject var state: DropTargetState

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 20, height: 20)
            }
            Text(name)
                .font(Font(DockLabel.font))
                .lineLimit(1)
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .frame(height: 30)
        .background(Capsule().fill(Color.accentColor.opacity(state.hovered ? 0.45 : 0)))
        .dockGlass(in: Capsule())
        .scaleEffect(state.hovered ? 1.15 : (state.visible ? 1 : 0.6))
        .opacity(state.visible ? 1 : 0)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: state.hovered)
        .animation(.snappy(duration: 0.18), value: state.visible)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
