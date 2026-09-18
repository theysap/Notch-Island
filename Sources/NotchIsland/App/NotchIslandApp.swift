import SwiftUI

@main
struct NotchIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra(isInserted: menuBarIconBinding) {
            MenuBarContent()
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }

        Settings {
            SettingsView(settings: appDelegate.settings)
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

    var body: some View {
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
}
