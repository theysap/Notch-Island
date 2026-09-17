import SwiftUI

/// Artwork for the current track, or the source application's icon when the
/// source publishes none.
struct ArtworkView: View {
    let media: MediaController
    var cornerRadius: CGFloat

    var body: some View {
        Group {
            if let artwork = media.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder
            }
        }
        .clipShape(.rect(cornerRadius: cornerRadius))
        .overlay {
            // A hairline keeps pale artwork from bleeding into the island's
            // black.
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
        }
        .animation(.smooth(duration: 0.3), value: media.artwork)
    }

    private var placeholder: some View {
        ZStack {
            Rectangle().fill(.white.opacity(0.08))
            Image(systemName: media.nowPlaying?.kind.symbolName ?? "waveform")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.65))
        }
    }
}
