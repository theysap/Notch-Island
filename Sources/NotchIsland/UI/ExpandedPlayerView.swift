import SwiftUI

/// The island opened up: what is playing, where it has got to, and the controls
/// to do something about it.
struct ExpandedPlayerView: View {
    let media: MediaController
    let presentation: IslandPresentation
    let track: NowPlaying

    private var layout: IslandLayout { presentation.layout }

    /// Width of the strip either side of the camera housing. The housing splits
    /// the top of the island in two, and this is what is left on each side.
    private var sideWidth: Double {
        (layout.expandedSize.width - layout.shoulderRadius * 2 - layout.metrics.notchWidth) / 2
    }

    var body: some View {
        VStack(spacing: 0) {
            topStrip
            mainRow
            Spacer(minLength: 0)
        }
    }

    /// Runs either side of the camera housing, which nothing may be drawn over.
    private var topStrip: some View {
        HStack(spacing: 0) {
            SourceBadge(media: media, track: track)
                .frame(width: sideWidth - 14, alignment: .leading)
                .padding(.leading, 14)

            Color.clear
                .frame(width: layout.metrics.notchWidth)

            MediaVisualizer(
                kind: track.kind,
                isPlaying: track.isPlaying,
                tint: media.palette.accent,
                progress: media.displayProgress(at: .now)
            )
            .frame(width: 26, height: 14)
            .frame(width: sideWidth - 14, alignment: .trailing)
            .padding(.trailing, 14)
        }
        .frame(height: layout.metrics.notchHeight)
    }

    private var mainRow: some View {
        HStack(alignment: .top, spacing: 14) {
            ArtworkView(media: media, cornerRadius: 11)
                .frame(width: 92, height: 92)
                .shadow(color: .black.opacity(0.5), radius: 8, y: 3)

            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(
                    text: track.displayTitle,
                    font: .systemFont(ofSize: 13.5, weight: .semibold),
                    color: .white
                )

                if let subtitle = track.displaySubtitle {
                    MarqueeText(
                        text: subtitle,
                        font: .systemFont(ofSize: 11.5, weight: .regular),
                        color: .white.opacity(0.58)
                    )
                }

                Spacer(minLength: 2)

                ScrubBar(
                    media: media,
                    presentation: presentation,
                    track: track,
                    tint: media.palette.accent
                )

                // Centred on the progress bar rather than on the island, so
                // the controls line up with the timeline they belong to.
                TransportControls(
                    media: media,
                    presentation: presentation,
                    isPlaying: track.isPlaying,
                    tint: media.palette.accent
                )
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 2)
            }
            .frame(height: 104)
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
    }
}
