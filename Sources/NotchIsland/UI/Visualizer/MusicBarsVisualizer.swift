import SwiftUI

/// Equaliser bars for music.
///
/// The heights come from two sine waves of different frequency per bar rather
/// than one, which is what keeps it from looking like a metronome: the bars
/// drift in and out of step the way a real spectrum does.
struct MusicBarsVisualizer: View {
    let isPlaying: Bool
    let tint: Color

    private static let bars = 4
    private static let phases: [Double] = [0.0, 1.9, 3.4, 5.1]
    private static let speeds: [Double] = [1.00, 1.37, 0.83, 1.19]

    var body: some View {
        VisualizerCanvas(isPlaying: isPlaying) { context, size, time in
            // Capped so the bars stay slim rather than turning into blocks when
            // the frame is wider than it is tall.
            let spacing = 2.0
            let barWidth = min(
                (size.width - Double(Self.bars - 1) * spacing) / Double(Self.bars),
                3.2
            )
            let radius = barWidth / 2
            let totalWidth = barWidth * Double(Self.bars) + spacing * Double(Self.bars - 1)
            let originX = (size.width - totalWidth) / 2

            for index in 0..<Self.bars {
                let height = barHeight(index: index, time: time, maximum: size.height)
                let x = originX + Double(index) * (barWidth + spacing)
                let rect = CGRect(
                    x: x,
                    y: (size.height - height) / 2,
                    width: barWidth,
                    height: height
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: radius),
                    with: .color(tint.opacity(0.55 + 0.45 * (height / size.height)))
                )
            }
        }
    }

    private func barHeight(index: Int, time: Double, maximum: Double) -> Double {
        let minimum = maximum * 0.22
        guard isPlaying else { return minimum }

        let speed = Self.speeds[index]
        let phase = Self.phases[index]

        let primary = sin(time * 5.4 * speed + phase)
        let secondary = sin(time * 2.3 * speed + phase * 1.7)
        let combined = 0.65 * primary + 0.35 * secondary

        // combined is -1...1; map it into the available height.
        let normalised = (combined + 1) / 2
        return minimum + (maximum - minimum) * normalised
    }
}
