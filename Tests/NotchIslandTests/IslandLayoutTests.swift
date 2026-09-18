import CoreGraphics
import Testing

@testable import NotchIsland

@Suite("Island geometry")
struct IslandLayoutTests {
    /// The development machine: a 13-inch MacBook Air, measured at runtime.
    private let layout = IslandLayout(
        metrics: NotchMetrics(
            screenFrame: CGRect(x: 0, y: 0, width: 1710, height: 1112),
            notchWidth: 208,
            notchHeight: 37.5,
            centreX: 855
        )
    )

    @Test("The compact island clears the notch on both sides")
    func compactSpansTheNotch() {
        let body = layout.compactSize.width - layout.shoulderRadius * 2
        #expect(body == 208 + layout.compactSideWidth * 2)
        #expect(layout.compactSize.height == 37.5)
    }

    @Test("The window hangs from the top of the screen, centred on the notch")
    func windowIsPinnedToTheTop() {
        let frame = layout.windowFrame

        #expect(frame.maxY == 1112)
        #expect(frame.midX == 855)
        #expect(frame.width == layout.windowSize.width)
    }

    @Test("The window is large enough for both states")
    func windowFitsBothStates() {
        #expect(layout.windowSize.width >= layout.expandedSize.width)
        #expect(layout.windowSize.width >= layout.compactSize.width)
        #expect(layout.windowSize.height >= layout.expandedSize.height)
    }

    @Test("The island sits flush with the top of its window in both states")
    func islandIsTopAligned() {
        for expanded in [false, true] {
            let rect = layout.islandRectInWindow(expanded: expanded)
            // AppKit coordinates: the top of the window is maxY.
            #expect(rect.maxY == layout.windowSize.height)
            #expect(rect.midX == layout.windowSize.width / 2)
        }
    }

    @Test("The hover zone contains the pointer at the top edge of the screen")
    func hoverZoneTouchesTheScreenEdge() {
        // Flicking the pointer to the top of the screen reports the screen's
        // maxY exactly, and `contains` excludes a rectangle's own maxY — so a
        // zone that stopped there would be unreachable at the one position the
        // pointer lands in most often.
        for expanded in [false, true] {
            let zone = layout.hoverZone(expanded: expanded)
            #expect(zone.maxY > 1112)
            #expect(zone.contains(CGPoint(x: zone.midX, y: 1112)))
        }
    }

    @Test("The expanded hover zone contains the collapsed one")
    func hoverZoneGrowsWithTheIsland() {
        let collapsed = layout.hoverZone(expanded: false)
        let expanded = layout.hoverZone(expanded: true)

        // Otherwise the island would close the instant it finished opening.
        #expect(expanded.contains(CGPoint(x: collapsed.midX, y: collapsed.midY)))
        #expect(expanded.width > collapsed.width)
        #expect(expanded.height > collapsed.height)
    }
}

@Suite("Island symmetry")
struct IslandSymmetryTests {
    private func layout(notchWidth: CGFloat, screenWidth: CGFloat) -> IslandLayout {
        IslandLayout(
            metrics: NotchMetrics(
                screenFrame: CGRect(x: 0, y: 0, width: screenWidth, height: 1112),
                notchWidth: notchWidth,
                notchHeight: 37.5,
                centreX: screenWidth / 2
            )
        )
    }

    @Test("The island extends by the same amount on both sides of the notch")
    func overhangIsEqualOnBothSides() {
        // Checked across notch widths so the property holds on any model, not
        // just the machine this was written on.
        for notchWidth in [180.0, 208.0, 220.0, 260.0] as [CGFloat] {
            let layout = layout(notchWidth: notchWidth, screenWidth: 1710)
            let left = layout.overhangPerSide
            let right = layout.compactSize.width - notchWidth - left

            #expect(left == right)
            #expect(left > 0)
        }
    }

    @Test("The island is centred on the notch, not on the screen")
    func centredOnTheNotch() {
        // These coincide on every current Mac, but the island follows the
        // camera housing regardless.
        let offCentre = IslandLayout(
            metrics: NotchMetrics(
                screenFrame: CGRect(x: 0, y: 0, width: 1710, height: 1112),
                notchWidth: 208,
                notchHeight: 37.5,
                centreX: 800
            )
        )

        #expect(offCentre.windowFrame.midX == 800)
    }

    @Test("Both states are centred within the window")
    func bothStatesAreCentred() {
        let layout = layout(notchWidth: 208, screenWidth: 1710)

        for expanded in [false, true] {
            let island = layout.islandRectInWindow(expanded: expanded)
            let leftGap = island.minX
            let rightGap = layout.windowSize.width - island.maxX
            #expect(leftGap == rightGap)
        }
    }

    @Test("The reserved menu bar width covers the island's overhang")
    func reservationCoversOverhang() {
        let layout = layout(notchWidth: 208, screenWidth: 1710)

        // Status icons must end up clear of the island, not flush against it.
        #expect(layout.menuBarReservation > layout.overhangPerSide)
    }
}

@Suite("Notch measurement limits")
struct NotchMeasurementTests {
    @Test("Plausible ranges accept every notch shipped so far")
    func acceptsKnownNotches() {
        // 13-inch MacBook Air, measured on the development machine.
        #expect(MacModel.plausibleWidth.contains(208))
        #expect(MacModel.plausibleHeight.contains(37.5))
    }

    @Test("Plausible ranges reject nonsense")
    func rejectsNonsense() {
        #expect(!MacModel.plausibleWidth.contains(0))
        #expect(!MacModel.plausibleWidth.contains(1710))
        #expect(!MacModel.plausibleHeight.contains(0))
        #expect(!MacModel.plausibleHeight.contains(500))
    }

    @Test("The model identifier is readable")
    func readsModelIdentifier() {
        let identifier = MacModel.identifier
        #expect(!identifier.isEmpty)
        #expect(identifier != "unknown")
        // sysctl returns a null-terminated string; the terminator must not
        // survive into the value.
        #expect(!identifier.contains("\0"))
    }
}
