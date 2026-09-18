import SwiftUI

@main
struct NotchIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra(isInserted: menuBarIconBinding) {
            MenuBarContent(updates: appDelegate.updates)
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }

        Settings {
            SettingsView(settings: appDelegate.settings, updates: appDelegate.updates)
        }
    }

    private var menuBarIconBinding: Binding<Bool> {
        Binding(
            get: { appDelegate.settings.showsMenuBarIcon },
            set: { appDelegate.settings.showsMenuBarIcon = $0 }
        )
    }
}

/// The menu behind the status item.
///
/// Deliberately just the way in and the way out. The island is the interface,
/// and macOS's own Now Playing control already covers transport from the menu
/// bar, so repeating it here would only be clutter.
private struct MenuBarContent: View {
    @Environment(\.openSettings) private var openSettings
    let updates: UpdateChecker

    var body: some View {
        // What is running, so the version is answerable without opening
        // anything.
        Text("NotchIsland \(AppInfo.versionDescription)")

        updateItem

        Divider()

        // Not a `SettingsLink`, which opens the window without activating the
        // app. An accessory application never becomes active on its own, so
        // the window arrives visible but behind whatever the user was looking
        // at, and not even key — measured: with the activation call the window
        // is key and the app frontmost, without it neither is true. Same root
        // cause as the dead controls fixed in v0.14.0.
        Button("Settings…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")

        Button("Quit NotchIsland") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// The one line that changes: an offer while there is one, progress while
    /// it installs, and the way to look again otherwise.
    @ViewBuilder
    private var updateItem: some View {
        switch updates.state {
        case .available(let release):
            Button("Update to \(release.version.description)…") {
                updates.installAvailableUpdate()
            }
            .disabled(!updates.canInstall)

        case .checking:
            Text("Checking for updates…")

        case .downloading(let fraction):
            Text("Downloading update… \(Int(fraction * 100))%")

        case .installing:
            Text("Installing update…")

        case .idle, .upToDate, .failed:
            Button("Check for Updates…") {
                Task { await updates.check(userInitiated: true) }
            }
        }
    }
}
