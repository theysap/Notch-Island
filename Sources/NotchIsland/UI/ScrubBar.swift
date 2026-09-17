import SwiftUI

/// The progress bar in the expanded player, draggable to seek.
///
/// Dragging updates a local position immediately and only tells the source
/// where to go on release. Seeking on every pixel of movement would flood the
/// source application with commands, and most of them handle that badly.
struct ScrubBar: View {
    let media: MediaController
    let presentation: IslandPresentation
    let track: NowPlaying
    let tint: Color

    private var isActive: Bool {
        presentation.isScrubBarHovered || presentation.isScrubbing
    }

    private var height: Double { isActive ? 5 : 3 }

    var body: some View {
        TimelineView(
            .animation(minimumInterval: 0.2, paused: !track.isPlaying && !presentation.isScrubbing)
        ) { timeline in
            let now = timeline.date
            VStack(spacing: 5) {
                bar(progress: media.displayProgress(at: now))
                labels(position: media.displayPosition(at: now))
            }
        }
    }

    private func bar(progress: Double?) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let filled = (progress ?? 0) * width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.16))

                if progress != nil {
                    Capsule()
                        .fill(tint)
                        .frame(width: max(filled, height))
                } else {
                    // No duration to show — a live stream. A moving bar would
                    // imply a position that does not exist.
                    Capsule()
                        .fill(tint.opacity(0.35))
                }
            }
            .frame(height: height)
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(dragGesture(width: width))
        }
        .frame(height: 12)
        .onHover { presentation.isScrubBarHovered = $0 }
        .animation(.smooth(duration: 0.18), value: isActive)
        .disabled(track.duration == nil)
    }

    private func dragGesture(width: Double) -> some Gesture {
        // A zero minimum distance makes a plain click seek, which is what
        // clicking a progress bar is expected to do.
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let duration = track.duration, duration > 0, width > 0 else { return }
                let fraction = min(max(value.location.x / width, 0), 1)
                if presentation.isScrubbing {
                    media.updateScrub(to: fraction * duration)
                } else {
                    presentation.isScrubbing = true
                    media.beginScrub(at: fraction * duration)
                }
            }
            .onEnded { _ in
                guard presentation.isScrubbing else { return }
                presentation.isScrubbing = false
                media.endScrub()
            }
    }

    private func labels(position: TimeInterval) -> some View {
        HStack {
            Text(TimeFormatting.position(position))
            Spacer(minLength: 0)
            if let duration = track.duration {
                Text(TimeFormatting.remaining(duration - position))
            }
        }
        .font(.system(size: 9.5, weight: .medium).monospacedDigit())
        .foregroundStyle(.white.opacity(0.45))
    }
}
