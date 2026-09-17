import AppKit
import SwiftUI

/// The window the island lives in.
///
/// It floats above the menu bar on every space, never takes focus away from the
/// app the person is actually using, and stays out of the way of the window
/// cycler.
final class NotchPanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        // Clicking a transport button must not pull focus from the foreground
        // application, but the panel still has to accept those clicks.
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false

        isOpaque = false
        backgroundColor = .clear
        // The island draws its own shadow, shaped to its outline; a window
        // shadow would trace the rectangular frame instead.
        hasShadow = false

        isMovable = false
        isMovableByWindowBackground = false
        ignoresMouseEvents = true

        // Above the menu bar and its status items.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)

        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]

        // Nothing here should ever appear in a screenshot of a window list or
        // in Mission Control.
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that only claims the pointer where the island actually is.
///
/// The window is much larger than the island so the expanded state has room to
/// animate into. Without this, the empty corners of that window would swallow
/// clicks meant for whatever is behind them.
final class IslandHostingView<Content: View>: NSHostingView<Content> {
    /// The island's current bounds within this view. Updated as the island
    /// expands and collapses.
    var interactiveRect: CGRect = .zero

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard interactiveRect.contains(point) else { return nil }
        return super.hitTest(point)
    }
}
