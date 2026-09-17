import CoreGraphics

/// Sizes for the island in both of its states, derived from the measured notch
/// so the compact form lines up with the hardware on any model.
struct IslandLayout: Equatable, Sendable {
    var metrics: NotchMetrics

    /// Radius of the concave shoulders where the island meets the bezel.
    var shoulderRadius: CGFloat { 9 }

    /// How far the compact island reaches past each side of the notch. Artwork
    /// lives in the left stretch, the visualiser in the right.
    var compactSideWidth: CGFloat { 54 }

    var compactCornerRadius: CGFloat { 14 }
    var expandedCornerRadius: CGFloat { 26 }

    /// The shape draws its shoulders inside its own bounds, so the frame is
    /// wider than the visible body by one shoulder on each side.
    var compactSize: CGSize {
        CGSize(
            width: metrics.notchWidth + compactSideWidth * 2 + shoulderRadius * 2,
            height: metrics.notchHeight
        )
    }

    var expandedSize: CGSize {
        CGSize(width: 384 + shoulderRadius * 2, height: 172)
    }

    func size(expanded: Bool) -> CGSize {
        expanded ? expandedSize : compactSize
    }

    /// How far the collapsed island reaches past the camera housing on each
    /// side. The island is symmetric about the housing, so this is the same
    /// number left and right.
    var overhangPerSide: CGFloat {
        (compactSize.width - metrics.notchWidth) / 2
    }

    /// Menu bar width to reserve on the right, so status items are laid out
    /// clear of the island rather than underneath it. A little more than the
    /// overhang, so icons do not sit flush against the island's edge.
    var menuBarReservation: CGFloat {
        overhangPerSide + 6
    }

    /// Room around the island for its shadow, and for the expanded state to
    /// grow into without the window having to be resized mid-animation.
    private var padding: CGFloat { 40 }

    var windowSize: CGSize {
        CGSize(
            width: max(compactSize.width, expandedSize.width) + padding * 2,
            height: expandedSize.height + padding
        )
    }

    /// Window frame in screen coordinates, hung from the top of the screen and
    /// centred on the notch.
    var windowFrame: CGRect {
        let size = windowSize
        return CGRect(
            x: metrics.centreX - size.width / 2,
            y: metrics.screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// The island itself inside the window, in AppKit's bottom-left coordinates.
    /// Used for hit testing, so clicks outside the island fall through to
    /// whatever is underneath.
    func islandRectInWindow(expanded: Bool) -> CGRect {
        let island = size(expanded: expanded)
        let window = windowSize
        return CGRect(
            x: (window.width - island.width) / 2,
            y: window.height - island.height,
            width: island.width,
            height: island.height
        )
    }

    /// The area that triggers expansion, in screen coordinates.
    ///
    /// Collapsed, it is the strip of menu bar the island occupies, widened
    /// slightly so the pointer does not have to be precise. Expanded, it is the
    /// island plus a forgiving margin, so drifting a few points off the edge
    /// while reaching for a button does not dismiss it.
    func hoverZone(expanded: Bool) -> CGRect {
        let island = size(expanded: expanded)
        let margin: CGFloat = expanded ? 24 : 6
        let height = island.height + margin

        return CGRect(
            x: metrics.centreX - island.width / 2 - margin,
            y: metrics.screenFrame.maxY - height,
            width: island.width + margin * 2,
            height: height
        )
    }
}
