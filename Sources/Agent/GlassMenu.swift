import AppKit
import SwiftUI

// A context menu drawn in Liquid Glass, styled after macOS Tahoe's menus.
//
// Why not NSMenu: a native menu takes keyboard focus, and the moment the Dock loses keyboard
// focus an auto-hiding Dock slides away. These menus never take focus, so the Dock stays put
// while you pick Hide or Quit.

struct MenuEntry: Identifiable {
    enum Kind {
        case action(() -> Void)
        case submenu([MenuEntry])
        case separator
        /// A title row (e.g. the app's name at the top of its menu); not clickable.
        case header
    }
    enum Indicator { case none, check, diamond }

    let id = UUID()
    var title = ""
    var kind: Kind
    var enabled = true
    var indicator: Indicator = .none
    /// Shown instead while ⌥ is held (e.g. Quit → Force Quit).
    var alternate: (title: String, action: () -> Void)?

    static func action(_ title: String, enabled: Bool = true, indicator: Indicator = .none,
                       _ handler: @escaping () -> Void) -> MenuEntry {
        MenuEntry(title: title, kind: .action(handler), enabled: enabled, indicator: indicator)
    }
    static func submenu(_ title: String, _ entries: [MenuEntry]) -> MenuEntry {
        MenuEntry(title: title, kind: .submenu(entries), enabled: !entries.isEmpty)
    }
    static var separator: MenuEntry { MenuEntry(kind: .separator) }
    static func header(_ title: String) -> MenuEntry { MenuEntry(title: title, kind: .header, enabled: false) }

    var isHeader: Bool { if case .header = kind { return true } else { return false } }

    var isSeparator: Bool { if case .separator = kind { return true } else { return false } }
    var submenu: [MenuEntry]? { if case .submenu(let e) = kind { return e } else { return nil } }
}

// MARK: - Metrics

enum MenuMetrics {
    static let rowHeight: CGFloat = 24
    static let separatorHeight: CGFloat = 11
    static let verticalPadding: CGFloat = 5
    static let rowInset: CGFloat = 5
    static let textPadding: CGFloat = 10
    static let indicatorWidth: CGFloat = 17
    static let chevronWidth: CGFloat = 18
    static let cornerRadius: CGFloat = 12
    static let minWidth: CGFloat = 170
    /// Pointer under a menu attached to a Dock tile (same as the Dock's name tag).
    static let pointerHeight: CGFloat = DockLabel.pointerHeight
    static let pointerWidth: CGFloat = 20
    /// Room for the glass shadow around the menu.
    static let margin: CGFloat = 24
    static let font = NSFont.systemFont(ofSize: 13)

    static func hasIndicators(_ entries: [MenuEntry]) -> Bool { entries.contains { $0.indicator != .none } }
    static func hasSubmenus(_ entries: [MenuEntry]) -> Bool { entries.contains { $0.submenu != nil } }

    static func height(of entry: MenuEntry) -> CGFloat { entry.isSeparator ? separatorHeight : rowHeight }

    static func size(_ entries: [MenuEntry]) -> CGSize {
        let titles = entries.flatMap { [$0.title, $0.alternate?.title ?? ""] }
        let textWidth = titles.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let width = rowInset * 2 + textPadding * 2 + ceil(textWidth)
            + (hasIndicators(entries) ? indicatorWidth : 0) + (hasSubmenus(entries) ? chevronWidth : 0)
        let height = verticalPadding * 2 + entries.reduce(0) { $0 + height(of: $1) }
        return CGSize(width: max(minWidth, width), height: height)
    }

    /// Distance from the menu's top edge to the top of row `index`.
    static func rowTop(_ index: Int, in entries: [MenuEntry]) -> CGFloat {
        verticalPadding + entries.prefix(index).reduce(0) { $0 + height(of: $1) }
    }
}

// MARK: - Model & controller

final class GlassMenuModel: ObservableObject {
    let entries: [MenuEntry]
    let level: Int
    /// For a menu attached to a Dock tile: where its pointer sits along the bottom edge.
    let pointerX: CGFloat?
    @Published var highlighted: UUID?
    @Published var optionDown = false

    init(entries: [MenuEntry], level: Int, pointerX: CGFloat? = nil) {
        self.entries = entries
        self.level = level
        self.pointerX = pointerX
    }
}

final class GlassMenuController {
    static let shared = GlassMenuController()

    private var stack: [(panel: FolderPanel, model: GlassMenuModel, glass: CGRect)] = []
    private var timer: Timer?
    private var onClose: (() -> Void)?
    private var watchesDock = false

    var isOpen: Bool { !stack.isEmpty }

    /// Whether a screen point (bottom-left origin) is over any open menu.
    func contains(_ point: CGPoint) -> Bool { stack.contains { $0.glass.contains(point) } }

    /// Shows a menu whose top-left corner is at `point` (screen coordinates, bottom-left origin).
    /// If `aboveBottomCenter` is true, `point` is instead the bottom-centre of the menu.
    func show(_ entries: [MenuEntry], at point: CGPoint, aboveBottomCenter: Bool = false,
              watchingDockFocus: Bool = false, onClose: (() -> Void)? = nil) {
        closeAll()
        self.onClose = onClose
        self.watchesDock = watchingDockFocus
        let size = MenuMetrics.size(entries)
        var origin = aboveBottomCenter
            ? CGPoint(x: point.x - size.width / 2, y: point.y)
            : CGPoint(x: point.x + 1, y: point.y - size.height - 1)
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main ?? NSScreen.screens[0]
        let bounds = screen.frame.insetBy(dx: 6, dy: 6)
        if !aboveBottomCenter, origin.y < bounds.minY { origin.y = point.y + 1 }   // no room below: open upward
        if !aboveBottomCenter, origin.x + size.width > bounds.maxX { origin.x = point.x - size.width - 1 }
        origin.x = min(max(origin.x, bounds.minX), bounds.maxX - size.width)
        origin.y = min(max(origin.y, bounds.minY), bounds.maxY - size.height)
        push(entries, glass: CGRect(origin: origin, size: size))
        startTimer()
    }

    /// Shows a menu above a Dock tile the way the Dock shows its own: with a pointer whose tip is
    /// at `tip` (screen coordinates), sitting where the Dock draws the tile's name tag. It's frosted
    /// and at least `minWidth` wide, so that name tag (still shown while the Dock is held) never
    /// shows through or around it.
    func showAttached(_ entries: [MenuEntry], tip: CGPoint, minWidth: CGFloat,
                      watchingDockFocus: Bool = false, onClose: (() -> Void)? = nil) {
        closeAll()
        self.onClose = onClose
        self.watchesDock = watchingDockFocus
        var size = MenuMetrics.size(entries)
        size.width = max(size.width, ceil(minWidth))
        size.height += MenuMetrics.pointerHeight
        let screen = NSScreen.screens.first { $0.frame.contains(tip) } ?? NSScreen.main ?? NSScreen.screens[0]
        let bounds = screen.frame.insetBy(dx: 6, dy: 6)
        let x = min(max(tip.x - size.width / 2, bounds.minX), bounds.maxX - size.width)
        push(entries, glass: CGRect(x: x, y: tip.y, width: size.width, height: size.height), pointerX: tip.x - x)
        startTimer()
    }

    func closeAll() {
        guard !stack.isEmpty else { return }
        for level in stack.indices.reversed() { stack[level].panel.orderOut(nil) }
        stack.removeAll()
        timer?.invalidate()
        timer = nil
        publishFrames()
        let callback = onClose
        onClose = nil
        callback?()
    }

    // MARK: Row events

    func hover(_ entry: MenuEntry, index: Int, level: Int) {
        guard level < stack.count else { return }
        closeSubmenus(deeperThan: level)
        guard entry.enabled, !entry.isSeparator else { stack[level].model.highlighted = nil; return }
        stack[level].model.highlighted = entry.id
        if let submenu = entry.submenu { openSubmenu(submenu, fromRow: index, level: level) }
    }

    func unhover(_ entry: MenuEntry, level: Int) {
        guard level < stack.count, stack[level].model.highlighted == entry.id else { return }
        // Keep a submenu's parent row lit while its submenu is open.
        if entry.submenu != nil, stack.count > level + 1 { return }
        stack[level].model.highlighted = nil
    }

    func click(_ entry: MenuEntry, index: Int, level: Int) {
        guard entry.enabled, level < stack.count else { return }
        switch entry.kind {
        case .submenu(let entries):
            if stack.count <= level + 1 { openSubmenu(entries, fromRow: index, level: level) }
        case .action(let handler):
            let action = (stack[level].model.optionDown ? entry.alternate?.action : nil) ?? handler
            closeAll()
            DispatchQueue.main.async(execute: action)
        case .separator, .header:
            break
        }
    }

    // MARK: Internals

    private func push(_ entries: [MenuEntry], glass: CGRect, pointerX: CGFloat? = nil) {
        let model = GlassMenuModel(entries: entries, level: stack.count, pointerX: pointerX)
        model.optionDown = NSEvent.modifierFlags.contains(.option)
        let panel = FolderPanel()
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1 + stack.count)
        let host = NSHostingView(rootView: GlassMenuView(model: model))
        host.sizingOptions = []
        panel.contentView = host
        // Lay out and draw fully before showing: menus appear instantly, like native ones,
        // instead of growing out of their first (empty) layout.
        panel.setFrame(glass.insetBy(dx: -MenuMetrics.margin, dy: -MenuMetrics.margin), display: false)
        host.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        panel.orderFrontRegardless()
        stack.append((panel, model, glass))
        publishFrames()
    }

    private func openSubmenu(_ entries: [MenuEntry], fromRow index: Int, level: Int) {
        let parent = stack[level].glass
        let size = MenuMetrics.size(entries)
        let rowTop = MenuMetrics.rowTop(index, in: stack[level].model.entries)
        var origin = CGPoint(x: parent.maxX - 4, y: parent.maxY - rowTop + MenuMetrics.verticalPadding - size.height)
        let screen = NSScreen.screens.first { $0.frame.intersects(parent) } ?? NSScreen.main ?? NSScreen.screens[0]
        let bounds = screen.frame.insetBy(dx: 6, dy: 6)
        if origin.x + size.width > bounds.maxX { origin.x = parent.minX - size.width + 4 }
        origin.y = min(max(origin.y, bounds.minY), bounds.maxY - size.height)
        push(entries, glass: CGRect(origin: origin, size: size))
    }

    private func closeSubmenus(deeperThan level: Int) {
        while stack.count > level + 1 {
            stack.removeLast().panel.orderOut(nil)
        }
        publishFrames()
    }

    private func publishFrames() {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        EventInterceptor.shared.setMenuFrames(stack.map {
            CGRect(x: $0.glass.minX, y: primaryHeight - $0.glass.maxY, width: $0.glass.width, height: $0.glass.height)
        })
    }

    private func startTimer() {
        timer?.invalidate()
        var ticks = 0
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            let option = NSEvent.modifierFlags.contains(.option)
            for entry in self.stack where entry.model.optionDown != option { entry.model.optionDown = option }
            ticks += 1
            // Esc (or anything else) took the Dock's focus away: close, like the Dock's own menus.
            if self.watchesDock, ticks % 4 == 0, !DockAX.shared.isFocused { self.closeAll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}

// MARK: - Views

struct GlassMenuView: View {
    @ObservedObject var model: GlassMenuModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let indicators = MenuMetrics.hasIndicators(model.entries)
        let chevrons = MenuMetrics.hasSubmenus(model.entries)
        VStack(spacing: 0) {
            ForEach(Array(model.entries.enumerated()), id: \.element.id) { index, entry in
                if entry.isSeparator {
                    Rectangle()
                        .fill(Color.primary.opacity(scheme == .dark ? 0.16 : 0.12))
                        .frame(height: 1)
                        .padding(.horizontal, MenuMetrics.rowInset + MenuMetrics.textPadding)
                        .frame(height: MenuMetrics.separatorHeight)
                } else {
                    row(entry, index: index, indicators: indicators, chevrons: chevrons)
                }
            }
        }
        .padding(.vertical, MenuMetrics.verticalPadding)
        .modifier(MenuSurface(pointerX: model.pointerX))
        .padding(MenuMetrics.margin)
        .transaction { $0.disablesAnimations = true }
    }

    private func row(_ entry: MenuEntry, index: Int, indicators: Bool, chevrons: Bool) -> some View {
        let lit = model.highlighted == entry.id
        let title = (model.optionDown ? entry.alternate?.title : nil) ?? entry.title
        let textColor: Color = entry.isHeader ? .primary : (!entry.enabled ? .secondary.opacity(0.6) : (lit ? .white : .primary))
        return HStack(spacing: 0) {
            if indicators {
                Group {
                    switch entry.indicator {
                    case .check: Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                    case .diamond: Image(systemName: "diamond.fill").font(.system(size: 7))
                    case .none: Color.clear
                    }
                }
                .frame(width: MenuMetrics.indicatorWidth, alignment: .leading)
            }
            Text(title)
                .font(Font(MenuMetrics.font).weight(entry.isHeader ? .semibold : .regular))
                .lineLimit(1)
            Spacer(minLength: 0)
            if chevrons, entry.submenu != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: MenuMetrics.chevronWidth, alignment: .trailing)
            }
        }
        .foregroundStyle(textColor)
        .padding(.horizontal, MenuMetrics.textPadding)
        .frame(height: MenuMetrics.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.accentColor)
                .opacity(lit && entry.enabled ? 1 : 0)
        )
        .padding(.horizontal, MenuMetrics.rowInset)
        .overlay(
            HoverCatcher(
                onEnter: { GlassMenuController.shared.hover(entry, index: index, level: model.level) },
                onExit: { GlassMenuController.shared.unhover(entry, level: model.level) },
                onClick: { GlassMenuController.shared.click(entry, index: index, level: model.level) }
            )
        )
    }
}

/// Plain menus are rounded glass. Menus attached to a Dock tile get the Dock's pointer and are
/// frosted, so the tile's name tag underneath doesn't show through.
private struct MenuSurface: ViewModifier {
    let pointerX: CGFloat?

    func body(content: Content) -> some View {
        if let pointerX {
            let shape = CalloutShape(edge: .bottom, arrowPosition: pointerX, cornerRadius: MenuMetrics.cornerRadius,
                                     arrowWidth: MenuMetrics.pointerWidth, arrowHeight: MenuMetrics.pointerHeight)
            content
                .padding(.bottom, MenuMetrics.pointerHeight)
                .background(Rectangle().fill(.thickMaterial).clipShape(shape))
                .dockGlass(in: shape)
        } else {
            content.dockGlass(in: RoundedRectangle(cornerRadius: MenuMetrics.cornerRadius, style: .continuous))
        }
    }
}

/// Hover + click tracking that works in a window that is never key (and an app that isn't active).
struct HoverCatcher: NSViewRepresentable {
    var onEnter: () -> Void
    var onExit: () -> Void
    var onClick: () -> Void

    func makeNSView(context: Context) -> HoverView { HoverView() }

    func updateNSView(_ view: HoverView, context: Context) {
        view.onEnter = onEnter
        view.onExit = onExit
        view.onClick = onClick
    }
}

final class HoverView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    var onClick: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
    override func rightMouseDown(with event: NSEvent) {}
    override func rightMouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
}
