import Foundation

@main
private enum FrozenTileAnchorSelfCheck {
    static func main() {
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else {
                fputs("FAIL: \(message)\n", stderr)
                exit(1)
            }
            checks += 1
        }

        let bottomAnchor = CGRect(x: 100, y: 20, width: 120, height: 120)
        let bottomLive = CGRect(x: 120, y: 50, width: 64, height: 64)
        expect(
            FrozenTileGeometry.hasShrunk(bottomLive, from: bottomAnchor, orientation: .bottom),
            "A smaller bottom-Dock tile should be detected as shrunk"
        )
        expect(
            !FrozenTileGeometry.hasShrunk(bottomAnchor, from: bottomAnchor, orientation: .bottom),
            "An unchanged bottom-Dock tile is not shrunk"
        )
        expect(
            FrozenTileGeometry.hasCaughtUp(bottomAnchor, with: bottomAnchor, orientation: .bottom),
            "An unchanged frame has caught up"
        )
        expect(
            !FrozenTileGeometry.hasCaughtUp(bottomLive, with: bottomAnchor, orientation: .bottom),
            "A shrinking bottom-Dock frame has not caught up"
        )

        let sideAnchor = CGRect(x: 20, y: 100, width: 96, height: 140)
        let sideLive = CGRect(x: 35, y: 120, width: 72, height: 82)
        expect(
            FrozenTileGeometry.hasShrunk(sideLive, from: sideAnchor, orientation: .left),
            "A shorter vertical-Dock tile should be detected as shrunk"
        )
        expect(
            FrozenTileGeometry.hasCaughtUp(sideAnchor, with: sideAnchor, orientation: .right),
            "A vertical-Dock frame with the same height has caught up"
        )

        let first = CGRect(x: 100, y: 20, width: 100, height: 120)
        let larger = CGRect(x: 90, y: 10, width: 120, height: 140)
        let sameSizeLater = CGRect(x: 92, y: 8, width: 120, height: 140)
        let best = FrozenTileGeometry.betterOnTileFrame(larger, than: first, orientation: .bottom)
        let latest = FrozenTileGeometry.betterOnTileFrame(sameSizeLater, than: best, orientation: .bottom)
        expect(best == larger, "The largest horizontal-Dock frame becomes the anchor candidate")
        expect(latest == sameSizeLater, "The latest position wins at equal size")

        let enteredFrame = CGRect(x: 100, y: 20, width: 120, height: 120)
        let returningFrame = CGRect(x: 120, y: 50, width: 64, height: 64)
        var anchorState = FrozenTileAnchorState()
        expect(
            anchorState.update(
                liveTileFrame: enteredFrame,
                isOnLiveTile: true,
                isEngaged: false,
                orientation: .bottom
            ) == .live,
            "Entering the live tile starts with the live anchor"
        )
        expect(
            anchorState.update(
                liveTileFrame: returningFrame,
                isOnLiveTile: false,
                isEngaged: true,
                orientation: .bottom
            ) == .froze,
            "Leaving a shrinking live tile freezes the magnified anchor"
        )
        expect(anchorState.frozenTileFrame == enteredFrame, "The frozen anchor is kept")
        expect(
            anchorState.update(
                liveTileFrame: returningFrame,
                isOnLiveTile: true,
                isEngaged: false,
                orientation: .bottom
            ) == .keptFrozen,
            "Returning to a still-shrunk tile keeps the frozen anchor"
        )
        expect(anchorState.frozenTileFrame == enteredFrame, "The popup anchor stays frozen while returning")
        let overshootFrame = CGRect(x: 96, y: 16, width: 132, height: 132)
        expect(
            FrozenTileGeometry.hasCaughtUp(overshootFrame, with: enteredFrame, orientation: .bottom),
            "A live tile larger than the frozen anchor has caught up"
        )
        expect(
            anchorState.update(
                liveTileFrame: overshootFrame,
                isOnLiveTile: true,
                isEngaged: false,
                orientation: .bottom
            ) == .clearedToLive,
            "A jump from a smaller frame past the anchor clears the frozen state"
        )
        expect(anchorState.frozenTileFrame == nil, "Caught-up state clears the frozen anchor")
        expect(anchorState.bestOnTileFrame == overshootFrame, "Best on-tile frame follows the live frame")

        print("Frozen tile anchor self-check passed for \(checks) cases.")
    }
}
