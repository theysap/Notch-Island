import SwiftUI

/// Picks the animation that matches what is playing.
struct MediaVisualizer: View {
    let kind: MediaKind
    let isPlaying: Bool
    let tint: Color
    let progress: Double?

    var body: some View {
        Group {
            switch kind {
            case .music:
                MusicBarsVisualizer(isPlaying: isPlaying, tint: tint)
            case .podcast:
                PodcastWaveVisualizer(isPlaying: isPlaying, tint: tint)
            case .video:
                VideoPlayheadVisualizer(isPlaying: isPlaying, tint: tint, progress: progress)
            case .generic:
                GenericPulseVisualizer(isPlaying: isPlaying, tint: tint)
            }
        }
        .accessibilityHidden(true)
    }
}
