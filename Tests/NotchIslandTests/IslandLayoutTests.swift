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

    @Test("The hover zone reaches the top edge of the screen")
    func hoverZoneTouchesTheScreenEdge() {
        // The pointer cannot travel above the top of the screen, so a zone that
        // stopped short would be unreachable at its top edge.
        for expanded in [false, true] {
            #expect(layout.hoverZone(expanded: expanded).maxY == 1112)
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
