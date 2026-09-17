import SwiftUI

/// The progress bar in the expanded player, draggable to seek.
///
/// Built on the system's glass material rather than flat shapes, so it reads
/// the way a slider does elsewhere on macOS 26: a translucent track, a filled
/// portion tinted from the artwork, and a knob that appears under the pointer.
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

    /// The track thickens under the pointer, as system sliders do.
    private var trackHeight: Double { isActive ? 7 : 4 }
    private var knobDiameter: Double { presentation.isScrubbing ? 13 : 11 }

    var body: some View {
        TimelineView(
            .animation(minimumInterval: 0.2, paused: !track.isPlaying && !presentation.isScrubbing)
        ) { timeline in
            let now = timeline.date
            VStack(spacing: 5) {
                slider(progress: media.displayProgress(at: now))
                labels(position: media.displayPosition(at: now))
            }
        }
    }

    private func slider(progress: Double?) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fraction = progress ?? 0
            let filled = fraction * width

            // One container so the track and the knob are treated as a single
            // piece of glass and blend where they meet.
            //
            // The material is layered *behind* solid fills rather than applied
            // to them. `glassEffect` replaces what a view draws with the
            // material itself, and over the island's pure black there is
            // nothing behind it to refract — so used on its own it renders as
            // nothing at all. Layering keeps the slider legible and lets the
            // material add its rim highlight on top of that.
            GlassEffectContainer(spacing: 6) {
                ZStack(alignment: .leading) {
                    Capsule()
                        .glassEffect(.regular, in: .capsule)
                        .frame(height: trackHeight)

                    Capsule()
                        .fill(.white.opacity(0.16))
                        .frame(height: trackHeight)

                    if progress != nil {
                        Capsule()
                            .fill(tint.gradient)
                            .frame(width: max(filled, trackHeight), height: trackHeight)
                    } else {
                        // No duration to show — a live stream. A moving bar
                        // would imply a position that does not exist.
                        Capsule()
                            .fill(tint.opacity(0.32))
                            .frame(height: trackHeight)
                    }

                    if progress != nil, isActive {
                        knob
                            .offset(
                                x: min(max(filled - knobDiameter / 2, 0), width - knobDiameter))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            // A generous target: the visible track is only a few points tall.
            .contentShape(.rect)
            .gesture(dragGesture(width: width))
        }
        .frame(height: 14)
        .accessibilityLabel("Playback position")
        .accessibilityValue(progress.map { "\(Int(($0 * 100).rounded())) percent" } ?? "Unknown")
        .onHover { presentation.isScrubBarHovered = $0 }
        .animation(.smooth(duration: 0.18), value: isActive)
        .animation(.smooth(duration: 0.18), value: presentation.isScrubbing)
        .disabled(track.duration == nil)
    }

    private var knob: some View {
        ZStack {
            Circle()
                .glassEffect(.regular.interactive(), in: .circle)
            Circle()
                .fill(.white.opacity(0.95))
                .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
        }
        .frame(width: knobDiameter, height: knobDiameter)
        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
        .transition(.opacity.combined(with: .scale))
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
