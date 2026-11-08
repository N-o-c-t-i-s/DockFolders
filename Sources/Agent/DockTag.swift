import AppKit
import SwiftUI

/// A label like the Dock's own name tags, placed where the Dock puts them for a tile. Used for
/// "Create Folder" while an app is dragged over another app.
final class DockTag {
    static let shared = DockTag()

    private let state = DockTagState()
    private var tileAX: CGRect = .zero
    private lazy var panel: NSPanel = {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let host = NSHostingView(rootView: DockTagView(state: state))
        host.sizingOptions = []   // the window is sized here, not by its content
        panel.contentView = host
        return panel
    }()

    private static let margin: CGFloat = 12

    var isShowing: Bool { state.visible }

    func show(_ text: String, forTile tile: CGRect) {
        state.text = text
        state.edge = Self.edge
        move(toTile: tile)
        panel.orderFrontRegardless()
        withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) { state.visible = true }
    }

    /// Keeps the tag on its tile as the Dock slides tiles around.
    func move(toTile tile: CGRect) {
        tileAX = tile
        let size = Self.size(for: state.text, edge: Self.edge)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let t = CGRect(x: tile.minX, y: primaryHeight - tile.maxY, width: tile.width, height: tile.height)
        // Where the Dock puts its label's tip: just inside the tile's inner edge.
        let origin: CGPoint
        switch Self.edge {
        case .leading:   // left Dock: the tag sits to the right, pointing left
            origin = CGPoint(x: t.maxX - DockLabel.tipInset, y: t.midY - size.height / 2)
        case .trailing:  // right Dock
            origin = CGPoint(x: t.minX + DockLabel.tipInset - size.width, y: t.midY - size.height / 2)
        default:         // bottom Dock: above, pointing down
            origin = CGPoint(x: t.midX - size.width / 2, y: t.maxY - DockLabel.tipInset)
        }
        let frame = NSRect(x: (origin.x - Self.margin).rounded(), y: (origin.y - Self.margin).rounded(),
                           width: size.width + Self.margin * 2, height: size.height + Self.margin * 2)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    func hide() {
        guard state.visible else { return }
        withAnimation(.easeIn(duration: 0.12)) { state.visible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in
            guard let self, !self.state.visible else { return }
            self.panel.orderOut(nil)
        }
    }

    fileprivate static var edge: Edge {
        switch CoreDock.orientation {
        case .bottom: return .bottom
        case .left: return .leading
        case .right: return .trailing
        }
    }

    fileprivate static func size(for text: String, edge: Edge) -> CGSize {
        let body = CGSize(width: DockLabel.width(for: text), height: DockLabel.height)
        return edge == .bottom
            ? CGSize(width: body.width, height: body.height + DockLabel.pointerHeight)
            : CGSize(width: body.width + DockLabel.pointerHeight, height: body.height)
    }
}

final class DockTagState: ObservableObject {
    @Published var text = ""
    @Published var visible = false
    @Published var edge: Edge = .bottom
}

private struct DockTagView: View {
    @ObservedObject var state: DockTagState

    var body: some View {
        let size = DockTag.size(for: state.text, edge: state.edge)
        let horizontal = state.edge == .bottom
        let shape = CalloutShape(
            edge: state.edge,
            arrowPosition: horizontal ? size.width / 2 : DockLabel.height / 2,
            cornerRadius: DockLabel.height / 2,
            arrowWidth: DockLabel.pointerWidth, arrowHeight: DockLabel.pointerHeight
        )
        Text(state.text)
            .font(Font(DockLabel.font))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .frame(width: DockLabel.width(for: state.text), height: DockLabel.height)
            .padding(horizontal ? .bottom : (state.edge == .leading ? .leading : .trailing), DockLabel.pointerHeight)
            .dockGlass(in: shape)
            .frame(width: size.width, height: size.height)
            .scaleEffect(state.visible ? 1 : 0.85, anchor: anchor)
            .opacity(state.visible ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var anchor: UnitPoint {
        switch state.edge {
        case .leading: return .leading
        case .trailing: return .trailing
        default: return .bottom
        }
    }
}
