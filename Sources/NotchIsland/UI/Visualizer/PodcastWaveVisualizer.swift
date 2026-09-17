import SwiftUI

/// A travelling waveform for speech.
///
/// Speech is not steady the way music is — it comes in bursts with gaps between
/// them — so the wave's amplitude is driven by an envelope that drops close to
/// silence between phrases. That pause is the thing that tells a podcast apart
/// from a song at a glance.
struct PodcastWaveVisualizer: View {
    let isPlaying: Bool
    let tint: Color

    var body: some View {
        VisualizerCanvas(isPlaying: isPlaying) { context, size, time in
            let midY = size.height / 2
            let amplitude = midY * 0.92 * envelope(at: time)
            let wavelength = size.width / 1.6

            var path = Path()
            // Two points per horizontal point is enough for a curve this small
            // to look smooth without wasting fill rate.
            let step = 0.5
            var x = 0.0
            while x <= size.width {
                let angle = (x / wavelength - time * 1.15) * 2 * .pi
                let y = midY + sin(angle) * amplitude * taper(x: x, width: size.width)
                if x == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                x += step
            }

            context.stroke(
                path,
                with: .color(tint.opacity(isPlaying ? 0.95 : 0.4)),
                style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
            )
        }
    }

    /// Speech-like bursts: mostly loud, briefly near-silent.
    private func envelope(at time: Double) -> Double {
        guard isPlaying else { return 0.18 }
        let slow = sin(time * 1.6)
        let fast = sin(time * 4.3 + 1.1)
        let mixed = 0.7 * slow + 0.3 * fast
        return 0.32 + 0.68 * pow((mixed + 1) / 2, 1.6)
    }

    /// Fades the wave out at both ends so it does not stop abruptly against the
    /// island's black.
    private func taper(x: Double, width: Double) -> Double {
        let edge = width * 0.18
        if x < edge { return x / edge }
        if x > width - edge { return (width - x) / edge }
        return 1
    }
}
