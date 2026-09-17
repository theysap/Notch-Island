import SwiftUI

/// Small mark showing which application the audio is coming from.
///
/// It sits in the strip beside the camera housing, which is otherwise dead
/// space in the expanded player.
struct SourceBadge: View {
    let media: MediaController
    let track: NowPlaying

    var body: some View {
        HStack(spacing: 5) {
            if let icon = media.sourceIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 13, height: 13)
            } else {
                Image(systemName: track.kind.symbolName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }

            if let name = track.sourceName {
                Text(name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Playing in \(track.sourceName ?? "another application")"))
    }
}
