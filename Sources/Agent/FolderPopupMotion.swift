import AppKit
import SwiftUI

/// Shared motion and hit-area values for the folder popup and its hover trigger.
enum FolderPopupMotion {
    static let duration: TimeInterval = 0.19
    static let reducedMotionDuration: TimeInterval = 0.11
    static let closedScale: CGFloat = 0.96
    static let slideDistance: CGFloat = 9

    static let popupHitPadding: CGFloat = 8
    static let approachHorizontalPadding: CGFloat = 24
    static let exitGrace: TimeInterval = 0.28
    static let hoverExitGrace: TimeInterval = 0.32
    static let hoverOpenDelay: TimeInterval = 0.18
    static let hoverPollInterval: TimeInterval = 0.04

    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static var animationDuration: TimeInterval {
        reduceMotion ? reducedMotionDuration : duration
    }

    static var animation: Animation {
        reduceMotion
            ? .linear(duration: reducedMotionDuration)
            : .timingCurve(0.22, 0.61, 0.36, 1, duration: duration)
    }
}
