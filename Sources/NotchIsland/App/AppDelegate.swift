import AppKit
import ImageIO
import SwiftUI

/// Owns the objects that outlive any particular window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let media = MediaController()
    private lazy var notchController = NotchWindowController(media: media)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The island is not an ordinary window-and-Dock-icon application.
        NSApp.setActivationPolicy(.accessory)

        #if DEBUG
        if let directory = IslandPreviewRenderer.requestedDirectory {
            IslandPreviewRenderer.render(into: directory)
            NSApp.terminate(nil)
            return
        }
        #endif
        media.start()
        notchController.start()
        AppLog.app.info("NotchIsland launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        media.stop()
    }
}
