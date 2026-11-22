import CoreGraphics

private let counts = [0, 1, 2, 3, 4, 6, 8, 9, 12, 16, 17, 25, 100, 150, 200]
private let body = CGRect(x: 100, y: 80, width: 824, height: 824)
private let epsilon: CGFloat = 0.0001

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("Layout self-check failed: \(message)\n", stderr)
        exit(1)
    }
}

private func expectedRows(for slotCount: Int, columns: Int) -> Int {
    slotCount == 0 ? 0 : (slotCount + columns - 1) / columns
}

private func verify(
    count: Int,
    preferredColumns: Int,
    preferredRows: Int,
    mode: DockIconDisplayMode,
    expectedColumns: Int,
    expectedDisplayedApps: Int,
    expectedSlotCount: Int,
    expectedOverflow: Int
) {
    let layout = DockIconGridLayout.make(
        appCount: count,
        preferredColumns: preferredColumns,
        preferredRows: preferredRows,
        displayMode: mode,
        in: body
    )
    let context = "count=\(count) mode=\(mode.rawValue) preferredColumns=\(preferredColumns) preferredRows=\(preferredRows)"

    check(layout.columns == expectedColumns, "\(context): columns")
    check(layout.displayedAppCount == expectedDisplayedApps, "\(context): displayed apps")
    check(layout.slots.count == expectedSlotCount, "\(context): slot count")
    check(layout.overflowCount == expectedOverflow, "\(context): overflow count")
    let reservedRows = mode == .preview ? 2 : preferredRows
    let expectedRowCount = expectedSlotCount == 0
        ? 0
        : max(reservedRows, expectedRows(for: expectedSlotCount, columns: expectedColumns))
    check(
        layout.rows == expectedRowCount,
        "\(context): rows"
    )

    let representedApps = layout.slots.count - (layout.overflowCount > 0 ? 1 : 0)
    check(representedApps == layout.displayedAppCount, "\(context): represented apps")
    if mode == .preview {
        check(layout.displayedAppCount == min(count, 4), "\(context): preview represents the first four apps")
    } else {
        check(
            layout.displayedAppCount + layout.overflowCount == count,
            "\(context): every app is represented by an item or the overflow badge"
        )
    }
    check(
        layout.overflowLabel == (expectedOverflow > 0 ? "+\(expectedOverflow)" : nil),
        "\(context): overflow label"
    )

    guard !layout.slots.isEmpty else {
        check(count == 0, "\(context): expected an empty layout")
        check(layout.gridRect == .zero, "\(context): empty grid rect")
        return
    }

    check(abs(layout.gridRect.midX - body.midX) < epsilon, "\(context): grid is horizontally centered")
    check(abs(layout.gridRect.midY - body.midY) < epsilon, "\(context): grid is vertically centered")
    check(body.contains(layout.gridRect), "\(context): grid fits inside the body")

    for slot in layout.slots {
        check(body.contains(slot), "\(context): slot fits inside the body")
        check(slot.width > 0 && slot.height > 0, "\(context): positive slot size")
        check(abs(slot.width - slot.height) < epsilon, "\(context): square slots")
    }

    for first in layout.slots.indices {
        for second in layout.slots.index(after: first)..<layout.slots.endIndex {
            let overlap = layout.slots[first].intersection(layout.slots[second])
            check(overlap.isNull || overlap.isEmpty, "\(context): overlapping slots \(first), \(second)")
        }
    }

    // Each partial row begins at the grid's leading edge, while the grid itself is centered.
    for row in 0..<layout.rows {
        let slotIndex = row * expectedColumns
        if slotIndex < layout.slots.count {
            check(
                abs(layout.slots[slotIndex].minX - layout.gridRect.minX) < epsilon,
                "\(context): row \(row) is left-aligned inside the centered grid"
            )
        }
    }

    if layout.overflowCount > 0 {
        let badgeIndex = layout.displayedAppCount
        check(layout.slots.indices.contains(badgeIndex), "\(context): overflow badge slot exists")
        check(layout.isOverflowSlot(badgeIndex), "\(context): overflow badge slot is marked")
        check(!layout.isOverflowSlot(0), "\(context): app slot is not a badge")
    }
}

private func verifyTwoAppsReservePageRows(columns: Int, rows: Int) {
    let layout = DockIconGridLayout.make(
        appCount: 2,
        preferredColumns: columns,
        preferredRows: rows,
        displayMode: .cappedGrid,
        in: body
    )
    let context = "two apps mode=cappedGrid grid=\(columns)x\(rows)"

    check(layout.columns == columns, "\(context): columns")
    check(layout.rows == rows, "\(context): reserved rows")
    check(layout.slots.count == 2, "\(context): slot count")
    check(abs(layout.gridRect.midX - body.midX) < epsilon, "\(context): grid is horizontally centered")
    check(abs(layout.gridRect.midY - body.midY) < epsilon, "\(context): grid is vertically centered")

    let first = layout.slots[0]
    let second = layout.slots[1]
    let gap = (layout.gridRect.width - CGFloat(columns) * first.width) / CGFloat(columns - 1)
    check(abs(first.minX - layout.gridRect.minX) < epsilon, "\(context): first app is in the top-left cell")
    check(abs(first.maxY - layout.gridRect.maxY) < epsilon, "\(context): first app is in the top row")
    check(
        abs(second.minX - (first.maxX + gap)) < epsilon,
        "\(context): second app is in the second top-left cell"
    )
    check(abs(second.maxY - layout.gridRect.maxY) < epsilon, "\(context): second app is in the top row")

    let expectedHeight = CGFloat(rows) * first.height + CGFloat(rows - 1) * gap
    check(abs(layout.gridRect.height - expectedHeight) < epsilon, "\(context): grid height includes every reserved row")
}

@main
private enum DockIconGridLayoutSelfCheck {
    static func main() {
        for (preferredColumns, preferredRows) in [(3, 3), (4, 4)] {
            for count in counts {
                let previewApps = min(count, 4)
                verify(
                    count: count,
                    preferredColumns: preferredColumns,
                    preferredRows: preferredRows,
                    mode: .preview,
                    expectedColumns: 2,
                    expectedDisplayedApps: previewApps,
                    expectedSlotCount: previewApps,
                    expectedOverflow: 0
                )

                let cappedApps = count > DockIconGridLayout.cappedSlotCount
                    ? DockIconGridLayout.cappedAppCount
                    : count
                let cappedSlots = count > DockIconGridLayout.cappedSlotCount
                    ? DockIconGridLayout.cappedSlotCount
                    : count
                let cappedOverflow = count > DockIconGridLayout.cappedSlotCount
                    ? count - DockIconGridLayout.cappedAppCount
                    : 0
                verify(
                    count: count,
                    preferredColumns: preferredColumns,
                    preferredRows: preferredRows,
                    mode: .cappedGrid,
                    expectedColumns: preferredColumns,
                    expectedDisplayedApps: cappedApps,
                    expectedSlotCount: cappedSlots,
                    expectedOverflow: cappedOverflow
                )

                verify(
                    count: count,
                    preferredColumns: preferredColumns,
                    preferredRows: preferredRows,
                    mode: .all,
                    expectedColumns: preferredColumns,
                    expectedDisplayedApps: count,
                    expectedSlotCount: count,
                    expectedOverflow: 0
                )
            }
        }

        verifyTwoAppsReservePageRows(columns: 3, rows: 3)
        verifyTwoAppsReservePageRows(columns: 4, rows: 4)

        print("Dock icon grid layout self-check passed for \(counts.count * 2 * 3 + 2) cases.")
    }
}
