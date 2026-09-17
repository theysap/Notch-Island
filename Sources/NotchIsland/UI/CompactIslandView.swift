import SwiftUI

/// The island at rest: artwork to the left of the camera housing, an activity
/// indicator to the right, and the housing itself left untouched in between.
struct CompactIslandView: View {
    let media: MediaController
    let layout: IslandLayout
    let track: NowPlaying

    private var artworkSize: CGFloat {
        // Leaves a couple of points of black above and below inside the menu
        // bar strip.
        max(layout.metrics.notchHeight - 15, 16)
    }

    var body: some View {
        HStack(spacing: 0) {
            ArtworkView(media: media, cornerRadius: 5)
                .frame(width: artworkSize, height: artworkSize)
                .frame(width: layout.compactSideWidth)

            // The camera housing. Nothing is ever drawn here.
            Color.clear
                .frame(width: layout.metrics.notchWidth)

            MediaVisualizer(
                kind: track.kind,
                isPlaying: track.isPlaying,
                tint: media.palette.accent,
                progress: media.displayProgress(at: .now)
            )
            .frame(width: 24, height: artworkSize * 0.8)
            .frame(width: layout.compactSideWidth)
        }
        .frame(height: layout.metrics.notchHeight)
    }
}
