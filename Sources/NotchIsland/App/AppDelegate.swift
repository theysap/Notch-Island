import AppKit
import SwiftUI

/// Owns the objects that outlive any particular window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let media = MediaController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The island is not an ordinary window-and-Dock-icon application.
        NSApp.setActivationPolicy(.accessory)
        media.start()
        AppLog.app.info("NotchIsland launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        media.stop()
    }
}
