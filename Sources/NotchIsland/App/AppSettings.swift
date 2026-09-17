import Observation
import ServiceManagement

/// User preferences, backed by `UserDefaults`.
@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let showsMenuBarIcon = "showsMenuBarIcon"
        static let hidesWhenPaused = "hidesWhenPaused"
        static let reservesMenuBarSpace = "reservesMenuBarSpace"
    }

    @ObservationIgnored
    private let defaults: UserDefaults

    /// Set while a change is being written back, so correcting a failed
    /// registration does not loop.
    @ObservationIgnored
    private var isApplyingLaunchAtLogin = false

    var showsMenuBarIcon: Bool {
        didSet { defaults.set(showsMenuBarIcon, forKey: Key.showsMenuBarIcon) }
    }

    /// Hides the island entirely while playback is paused, rather than leaving
    /// a dormant one in the menu bar.
    var hidesWhenPaused: Bool {
        didSet { defaults.set(hidesWhenPaused, forKey: Key.hidesWhenPaused) }
    }

    /// Keeps the system's status items clear of the island by reserving menu
    /// bar width while the island is on screen.
    var reservesMenuBarSpace: Bool {
        didSet { defaults.set(reservesMenuBarSpace, forKey: Key.reservesMenuBarSpace) }
    }

    /// Mirrors the login item's registration, which the system owns; there is
    /// nothing of our own to persist.
    var launchAtLogin: Bool {
        didSet {
            guard !isApplyingLaunchAtLogin else { return }
            applyLaunchAtLogin()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        defaults.register(defaults: [
            Key.showsMenuBarIcon: true,
            Key.hidesWhenPaused: false,
            Key.reservesMenuBarSpace: true,
        ])

        showsMenuBarIcon = defaults.bool(forKey: Key.showsMenuBarIcon)
        hidesWhenPaused = defaults.bool(forKey: Key.hidesWhenPaused)
        reservesMenuBarSpace = defaults.bool(forKey: Key.reservesMenuBarSpace)
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Whether the island should be on screen for the given track.
    func showsIsland(for track: NowPlaying?) -> Bool {
        guard let track else { return false }
        return track.isPlaying || !hidesWhenPaused
    }

    private func applyLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if launchAtLogin {
                try service.register()
            } else {
                try service.unregister()
            }
            AppLog.app.info("Launch at login set to \(self.launchAtLogin)")
        } catch {
            // Registration needs a real application bundle, so this fails when
            // running the binary straight out of the build directory. Put the
            // toggle back rather than leaving it showing a state that is not
            // true.
            AppLog.app.error("Could not change login item: \(error.localizedDescription)")
            isApplyingLaunchAtLogin = true
            launchAtLogin = service.status == .enabled
            isApplyingLaunchAtLogin = false
        }
    }
}
