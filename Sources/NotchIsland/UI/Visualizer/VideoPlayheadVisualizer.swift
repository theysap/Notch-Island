import SwiftUI

/// A playhead for video.
///
/// Where music and speech get an abstract animation, video gets something
/// useful: the real position in the file, as a track with a lit head. When the
/// source reports no duration — a live stream — the head sweeps instead, which
/// still reads as "playing" without inventing a position.
struct VideoPlayheadVisualizer: View {
    let isPlaying: Bool
    let tint: Color
    /// 0...1, or nil when the source reports no duration.
    let progress: Double?

    var body: some View {
        VisualizerCanvas(isPlaying: isPlaying && progress == nil) { context, size, time in
            let midY = size.height / 2
            let trackHeight = 1.6
            let inset = 1.0
            let trackRect = CGRect(
                x: inset,
                y: midY - trackHeight / 2,
                width: size.width - inset * 2,
                height: trackHeight
            )

            context.fill(
                Path(roundedRect: trackRect, cornerRadius: trackHeight / 2),
                with: .color(tint.opacity(0.28))
            )

            let position = headPosition(time: time)

            let filled = CGRect(
                x: trackRect.minX,
                y: trackRect.minY,
                width: trackRect.width * position,
                height: trackHeight
            )
            context.fill(
                Path(roundedRect: filled, cornerRadius: trackHeight / 2),
                with: .color(tint.opacity(0.85))
            )

            let headRadius = 2.6
            let headX = trackRect.minX + trackRect.width * position
            let head = CGRect(
                x: headX - headRadius,
                y: midY - headRadius,
                width: headRadius * 2,
                height: headRadius * 2
            )

            // A soft halo so the head reads at this size against black.
            context.fill(
                Path(ellipseIn: head.insetBy(dx: -1.6, dy: -1.6)),
                with: .color(tint.opacity(0.28)))
            context.fill(Path(ellipseIn: head), with: .color(tint.opacity(isPlaying ? 1 : 0.5)))
        }
    }

    private func headPosition(time: Double) -> Double {
        if let progress {
            return min(max(progress, 0), 1)
        }
        guard isPlaying else { return 0.5 }
        // Sweeps back and forth for sources with no duration.
        return (sin(time * 1.6) + 1) / 2
    }
}
