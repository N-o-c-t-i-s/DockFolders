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
    mode: DockIconDisplayMode,
    expectedColumns: Int,
    expectedDisplayedApps: Int,
    expectedSlotCount: Int,
    expectedOverflow: Int
) {
    let layout = DockIconGridLayout.make(
        appCount: count,
        preferredColumns: preferredColumns,
        displayMode: mode,
        in: body
    )
    let context = "count=\(count) mode=\(mode.rawValue) preferredColumns=\(preferredColumns)"

    check(layout.columns == expectedColumns, "\(context): columns")
    check(layout.displayedAppCount == expectedDisplayedApps, "\(context): displayed apps")
    check(layout.slots.count == expectedSlotCount, "\(context): slot count")
    check(layout.overflowCount == expectedOverflow, "\(context): overflow count")
    check(
        layout.rows == expectedRows(for: expectedSlotCount, columns: expectedColumns),
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

@main
private enum DockIconGridLayoutSelfCheck {
    static func main() {
        for preferredColumns in [3, 4] {
            for count in counts {
                let previewApps = min(count, 4)
                verify(
                    count: count,
                    preferredColumns: preferredColumns,
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
                    mode: .cappedGrid,
                    expectedColumns: preferredColumns,
                    expectedDisplayedApps: cappedApps,
                    expectedSlotCount: cappedSlots,
                    expectedOverflow: cappedOverflow
                )

                verify(
                    count: count,
                    preferredColumns: preferredColumns,
                    mode: .all,
                    expectedColumns: preferredColumns,
                    expectedDisplayedApps: count,
                    expectedSlotCount: count,
                    expectedOverflow: 0
                )
            }
        }

        print("Dock icon grid layout self-check passed for \(counts.count * 2 * 3) cases.")
    }
}
