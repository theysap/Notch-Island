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
    var body: some View {
        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",")

        Button("Quit NotchIsland") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
