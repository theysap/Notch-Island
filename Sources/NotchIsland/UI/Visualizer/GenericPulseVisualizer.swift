import SwiftUI

/// A slow pulse for audio that does not say what it is.
struct GenericPulseVisualizer: View {
    let isPlaying: Bool
    let tint: Color

    var body: some View {
        VisualizerCanvas(isPlaying: isPlaying) { context, size, time in
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let base = min(size.width, size.height) * 0.22
            let beat = isPlaying ? (sin(time * 3.1) + 1) / 2 : 0.0

            let haloRadius = base * (1.5 + 0.9 * beat)
            context.fill(
                Path(ellipseIn: CGRect(
                    x: centre.x - haloRadius,
                    y: centre.y - haloRadius,
                    width: haloRadius * 2,
                    height: haloRadius * 2
                )),
                with: .color(tint.opacity(0.12 + 0.16 * (1 - beat)))
            )

            let dotRadius = base * (1 + 0.16 * beat)
            context.fill(
                Path(ellipseIn: CGRect(
                    x: centre.x - dotRadius,
                    y: centre.y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                )),
                with: .color(tint.opacity(isPlaying ? 0.95 : 0.45))
            )
        }
    }
}
