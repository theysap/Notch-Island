import SwiftUI

@main
struct NotchIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra(isInserted: menuBarIconBinding) {
            MenuBarContent(media: appDelegate.media)
        } label: {
            Image(systemName: menuBarSymbol)
        }

        Settings {
            SettingsView(settings: appDelegate.settings)
        }
    }

    /// The status item tracks whichever kind of media is playing, so the menu
    /// bar says something even with the island collapsed.
    private var menuBarSymbol: String {
        appDelegate.media.nowPlaying?.kind.symbolName ?? "waveform"
    }

    private var menuBarIconBinding: Binding<Bool> {
        Binding(
            get: { appDelegate.settings.showsMenuBarIcon },
            set: { appDelegate.settings.showsMenuBarIcon = $0 }
        )
    }
}

/// The menu behind the status item. Deliberately small: the island itself is
/// the interface.
private struct MenuBarContent: View {
    let media: MediaController

    var body: some View {
        if let track = media.nowPlaying {
            Text(track.displayTitle)
            if let subtitle = track.displaySubtitle {
                Text(subtitle)
            }
            Divider()

            Button(track.isPlaying ? "Pause" : "Play") { media.togglePlayPause() }
            Button("Next") { media.nextTrack() }
            Button("Previous") { media.previousTrack() }
        } else {
            Text("Nothing Playing")
        }

        Divider()

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
