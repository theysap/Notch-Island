import SwiftUI

/// Drives the visualisers from a single timeline.
///
/// Everything is drawn into one `Canvas` rather than built from animated views,
/// so a frame costs one draw pass. The timeline stops entirely when playback is
/// paused: a paused track should not be spending battery on animation.
struct VisualizerCanvas: View {
    let isPlaying: Bool
    let draw: (inout GraphicsContext, CGSize, Double) -> Void

    /// 30fps. At this size the difference from 60 is not visible, and it halves
    /// the work.
    private static let frameInterval = 1.0 / 30.0

    var body: some View {
        TimelineView(.animation(minimumInterval: Self.frameInterval, paused: !isPlaying)) {
            timeline in
            Canvas(opaque: false, rendersAsynchronously: false) { context, size in
                var context = context
                draw(&context, size, timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .drawingGroup()
    }
}
