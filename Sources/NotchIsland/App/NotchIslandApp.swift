import SwiftUI

@main
struct NotchIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(media: appDelegate.media)
        } label: {
            Image(systemName: "waveform")
        }
    }
}

/// The menu behind the status item. Deliberately small: the island itself is
/// the interface, and this is the way out of the app.
private struct MenuBarContent: View {
    let media: MediaController

    var body: some View {
        if let track = media.nowPlaying {
            Text(track.displayTitle)
            if let subtitle = track.displaySubtitle {
                Text(subtitle)
            }
            Divider()
        } else {
            Text("Nothing Playing")
            Divider()
        }

        Button("Quit NotchIsland") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
