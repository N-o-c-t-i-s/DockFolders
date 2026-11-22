import CoreGraphics

/// How a folder's closed Dock tile previews the apps inside it.
enum DockIconDisplayMode: String, CaseIterable, Codable {
    case preview
    case cappedGrid
    case all
}

/// Pure geometry and item rules for the miniature grid inside a folder's Dock icon.
struct DockIconGridLayout: Equatable {
    static let cappedSlotCount = 16
    static let cappedAppCount = 15

    let columns: Int
    let rows: Int
    /// Apps drawn before the overflow badge, or all visible apps when there is no badge.
    let displayedAppCount: Int
    /// Apps represented by the final badge. Zero means every app has its own slot.
    let overflowCount: Int
    /// Slot rectangles in display order, including the final badge slot when needed.
    let slots: [CGRect]
    /// Bounds of the complete grid, including unused cells in a partial final row.
    let gridRect: CGRect

    var overflowLabel: String? {
        overflowCount > 0 ? "+\(overflowCount)" : nil
    }

    func isOverflowSlot(_ index: Int) -> Bool {
        overflowCount > 0 && index == displayedAppCount
    }

    static func make(
        appCount: Int,
        preferredColumns: Int,
        preferredRows: Int,
        displayMode: DockIconDisplayMode,
        in body: CGRect
    ) -> DockIconGridLayout {
        let count = max(0, appCount)
        let columns = displayMode == .preview ? 2 : max(1, preferredColumns)
        let reservedRows = displayMode == .preview ? 2 : max(1, preferredRows)

        let visibleSlotCount: Int
        let displayedAppCount: Int
        let overflowCount: Int
        switch displayMode {
        case .preview:
            displayedAppCount = min(count, 4)
            visibleSlotCount = displayedAppCount
            overflowCount = 0
        case .cappedGrid where count > cappedSlotCount:
            displayedAppCount = cappedAppCount
            visibleSlotCount = cappedSlotCount
            overflowCount = count - cappedAppCount
        case .cappedGrid:
            displayedAppCount = count
            visibleSlotCount = count
            overflowCount = 0
        case .all:
            displayedAppCount = count
            visibleSlotCount = count
            overflowCount = 0
        }

        let rows = visibleSlotCount == 0
            ? 0
            : max(reservedRows, (visibleSlotCount + columns - 1) / columns)
        guard rows > 0, body.width > 0, body.height > 0 else {
            return DockIconGridLayout(
                columns: columns,
                rows: rows,
                displayedAppCount: displayedAppCount,
                overflowCount: overflowCount,
                slots: [],
                gridRect: .zero
            )
        }

        let shortSide = min(body.width, body.height)
        let density = max(CGFloat(columns) / 4, CGFloat(rows) / 4, 1)
        let paddingFraction = max(0.05, 0.13 - (density - 1) * 0.035)
        let gapFraction = max(0.025, 0.075 - (density - 1) * 0.025)
        let preferredPadding = shortSide * paddingFraction
        let preferredGap = shortSide * gapFraction

        // Reserve a positive slot before allocating spacing. Very large "Show every app" grids
        // then scale padding and gaps down together instead of driving the slot size to zero.
        let zeroSpacingSlot = min(
            body.width / CGFloat(columns),
            body.height / CGFloat(rows)
        )
        let minimumSlot = min(
            zeroSpacingSlot * 0.75,
            shortSide / CGFloat(max(columns, rows) + 8)
        )
        let availableColumnSpacing = body.width - minimumSlot * CGFloat(columns)
        let availableRowSpacing = body.height - minimumSlot * CGFloat(rows)
        let preferredColumnSpacing = preferredPadding * 2
            + preferredGap * CGFloat(max(0, columns - 1))
        let preferredRowSpacing = preferredPadding * 2
            + preferredGap * CGFloat(max(0, rows - 1))
        let spacingScale = min(
            1,
            availableColumnSpacing / preferredColumnSpacing,
            availableRowSpacing / preferredRowSpacing
        )
        let padding = preferredPadding * spacingScale
        let gap = preferredGap * spacingScale
        let columnGaps = CGFloat(max(0, columns - 1)) * gap
        let rowGaps = CGFloat(max(0, rows - 1)) * gap
        let availableWidth = body.width - padding * 2 - columnGaps
        let availableHeight = body.height - padding * 2 - rowGaps
        let slotSide = min(availableWidth / CGFloat(columns), availableHeight / CGFloat(rows))

        let gridWidth = CGFloat(columns) * slotSide + columnGaps
        let gridHeight = CGFloat(rows) * slotSide + rowGaps
        let gridRect = CGRect(
            x: body.midX - gridWidth / 2,
            y: body.midY - gridHeight / 2,
            width: gridWidth,
            height: gridHeight
        )

        // Rows are filled from the top. A partial last row stays left-aligned inside the
        // centered grid, matching the open folder's reading order.
        let slots = (0..<visibleSlotCount).map { index in
            let column = index % columns
            let row = index / columns
            return CGRect(
                x: gridRect.minX + CGFloat(column) * (slotSide + gap),
                y: gridRect.maxY - slotSide - CGFloat(row) * (slotSide + gap),
                width: slotSide,
                height: slotSide
            )
        }

        return DockIconGridLayout(
            columns: columns,
            rows: rows,
            displayedAppCount: displayedAppCount,
            overflowCount: overflowCount,
            slots: slots,
            gridRect: gridRect
        )
    }
}
