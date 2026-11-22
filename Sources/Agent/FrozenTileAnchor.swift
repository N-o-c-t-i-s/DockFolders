import Foundation

/// Geometry decisions shared by the panel controller and the focused self-check.
enum FrozenTileGeometry {
    static func axisExtent(of frame: CGRect, orientation: CoreDock.Orientation) -> CGFloat {
        switch orientation {
        case .bottom: return frame.width
        case .left, .right: return frame.height
        }
    }

    /// Keeps the largest on-tile frame, and the latest position among equally large samples.
    static func betterOnTileFrame(
        _ candidate: CGRect,
        than current: CGRect?,
        orientation: CoreDock.Orientation
    ) -> CGRect {
        guard let current else { return candidate }
        let candidateExtent = axisExtent(of: candidate, orientation: orientation)
        let currentExtent = axisExtent(of: current, orientation: orientation)
        return candidateExtent >= currentExtent - 0.25 ? candidate : current
    }

    static func hasShrunk(
        _ live: CGRect,
        from anchor: CGRect,
        orientation: CoreDock.Orientation
    ) -> Bool {
        let anchorExtent = axisExtent(of: anchor, orientation: orientation)
        let liveExtent = axisExtent(of: live, orientation: orientation)
        let tolerance = max(1, anchorExtent * 0.015)
        return anchorExtent - liveExtent > tolerance
    }

    /// The Dock has restored enough magnification that using the live tile again will not jump.
    static func hasCaughtUp(
        _ live: CGRect,
        with anchor: CGRect,
        orientation: CoreDock.Orientation
    ) -> Bool {
        let anchorExtent = axisExtent(of: anchor, orientation: orientation)
        let liveExtent = axisExtent(of: live, orientation: orientation)
        return liveExtent >= anchorExtent - max(1, anchorExtent * 0.01)
    }

}

enum FrozenTileAnchorUpdate: Equatable {
    case live
    case froze
    case keptFrozen
    case clearedToLive
    case cleared
}

/// The popup-anchor state machine. A frozen frame remains authoritative until the live tile has
/// regained its size, including while the pointer is back on the live tile.
struct FrozenTileAnchorState: Equatable {
    private(set) var bestOnTileFrame: CGRect?
    private(set) var frozenTileFrame: CGRect?
    private(set) var wasOnLiveTile = false

    init(bestOnTileFrame: CGRect? = nil) {
        self.bestOnTileFrame = bestOnTileFrame
    }

    mutating func reset(bestOnTileFrame: CGRect? = nil) {
        self.bestOnTileFrame = bestOnTileFrame
        frozenTileFrame = nil
        wasOnLiveTile = false
    }

    mutating func update(
        liveTileFrame: CGRect,
        isOnLiveTile: Bool,
        isEngaged: Bool,
        orientation: CoreDock.Orientation
    ) -> FrozenTileAnchorUpdate {
        guard liveTileFrame.width > 0, liveTileFrame.height > 0 else {
            reset()
            return .cleared
        }

        if isOnLiveTile {
            bestOnTileFrame = FrozenTileGeometry.betterOnTileFrame(
                liveTileFrame,
                than: bestOnTileFrame,
                orientation: orientation
            )
            if let frozenTileFrame {
                guard FrozenTileGeometry.hasCaughtUp(
                    liveTileFrame,
                    with: frozenTileFrame,
                    orientation: orientation
                ) else {
                    wasOnLiveTile = true
                    return .keptFrozen
                }
                // Switch both the anchor and the best candidate in one state transition.
                bestOnTileFrame = liveTileFrame
                self.frozenTileFrame = nil
                wasOnLiveTile = true
                return .clearedToLive
            }
            wasOnLiveTile = true
            return .live
        }

        if frozenTileFrame != nil {
            if isEngaged {
                wasOnLiveTile = false
                return .keptFrozen
            }
            reset()
            return .cleared
        }

        if wasOnLiveTile, isEngaged, let candidate = bestOnTileFrame {
            frozenTileFrame = candidate
            wasOnLiveTile = false
            return .froze
        }

        if !isEngaged { bestOnTileFrame = nil }
        wasOnLiveTile = false
        return .live
    }
}

