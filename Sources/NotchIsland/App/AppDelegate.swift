import AppKit
import ImageIO
import SwiftUI

/// Owns the objects that outlive any particular window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let media = MediaController()
    let settings = AppSettings()
    private lazy var notchController = NotchWindowController(media: media, settings: settings)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The island is not an ordinary window-and-Dock-icon application.
        NSApp.setActivationPolicy(.accessory)

        guard !terminateIfAlreadyRunning() else { return }

        #if DEBUG
        if let directory = IslandPreviewRenderer.requestedDirectory {
            IslandPreviewRenderer.render(into: directory)
            NSApp.terminate(nil)
            return
        }

        if let command = IslandPreviewRenderer.requestedCommand {
            media.start()
            Task {
                // Long enough for the helper to come up.
                try? await Task.sleep(for: .seconds(3))
                self.media.send(command)
                try? await Task.sleep(for: .seconds(2))
                NSApp.terminate(nil)
            }
            return
        }

        if let directory = IslandPreviewRenderer.requestedLiveDirectory {
            media.start()
            // Long enough for the bridge to start and answer.
            Task {
                try? await Task.sleep(for: .seconds(6))
                IslandPreviewRenderer.renderLive(into: directory, media: media)
                NSApp.terminate(nil)
            }
            return
        }
        #endif
        #if DEBUG
        if MediaController.isSimulatingPlayback {
            media.startSimulatedPlayback()
        } else {
            media.start()
        }
        #else
        media.start()
        #endif

        notchController.start()
        AppLog.app.info("NotchIsland launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        media.stop()
    }

    /// Quits immediately if another copy is already running.
    ///
    /// Two islands would sit on top of each other in the same notch, each with
    /// its own helper process and its own menu bar reservation.
    private func terminateIfAlreadyRunning() -> Bool {
        guard let identifier = Bundle.main.bundleIdentifier else { return false }

        let others = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }

        guard !others.isEmpty else { return false }

        AppLog.app.notice("Another copy of NotchIsland is already running; quitting")
        others.first?.activate()
        NSApp.terminate(nil)
        return true
    }
}
