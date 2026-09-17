import AppKit

/// Reserves menu bar width so the system's status items are laid out clear of
/// the island instead of underneath it.
///
/// There is no API for moving another application's status items, but the menu
/// bar lays items out from the right edge leftwards and will not place one
/// where there is no room. An empty status item of the island's width therefore
/// pushes everything else clear, and macOS folds whatever no longer fits behind
/// its overflow chevron on its own.
///
/// This only works for the status items on the right. Application menus on the
/// left are drawn by the system and cannot be reserved against; see the README.
@MainActor
final class MenuBarSpacer {
    private var item: NSStatusItem?

    /// Width currently reserved. State arrives about once a second, and
    /// re-applying an unchanged reservation would rebuild the status item's
    /// image every time for no reason.
    private var reservedWidth: CGFloat?

    /// Sets the reserved width, or removes the reservation when `width` is nil.
    func reserve(width: CGFloat?) {
        guard let width, width > 0 else {
            remove()
            return
        }

        guard reservedWidth != width else { return }
        reservedWidth = width

        let item = existingItem()
        item.length = width
        item.isVisible = true

        // A status item with no content at all can be collapsed away by the
        // system. A fully transparent image of the reserved width guarantees
        // the space is held while staying invisible.
        item.button?.image = Self.transparentImage(width: width)

        AppLog.window.notice("Reserved \(width, format: .fixed(precision: 1))pt of menu bar width")
    }

    func remove() {
        reservedWidth = nil
        guard let item else { return }
        NSStatusBar.system.removeStatusItem(item)
        self.item = nil
    }

    private static func transparentImage(width: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: max(width, 1), height: 1))
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.unlockFocus()
        return image
    }

    private func existingItem() -> NSStatusItem {
        if let item { return item }

        let item = NSStatusBar.system.statusItem(withLength: 0)
        // Remembering the position keeps the reservation next to the notch
        // across launches instead of drifting through the menu bar.
        item.autosaveName = "com.notchisland.menu-bar-spacer"

        if let button = item.button {
            button.title = ""
            button.isEnabled = false
            // Nothing here should respond to the pointer; clicks belong to
            // whatever the island is drawn over.
            button.setAccessibilityElement(false)
        }

        self.item = item
        return item
    }
}
