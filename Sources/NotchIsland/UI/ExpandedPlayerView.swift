import SwiftUI

/// The island opened up: artwork, what is playing, and where it has got to.
struct ExpandedPlayerView: View {
    let media: MediaController
    let layout: IslandLayout
    let track: NowPlaying

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ArtworkView(media: media, cornerRadius: 12)
                .frame(width: 96, height: 96)

            VStack(alignment: .leading, spacing: 4) {
                Text(track.displayTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let subtitle = track.displaySubtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.top, layout.metrics.notchHeight + 8)
        .padding(.bottom, 18)
    }
}
