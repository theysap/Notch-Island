import AppKit
import SwiftUI

/// Single-line text that scrolls itself when it is too long to fit.
///
/// The width is measured with the same font Core Text will use, so the decision
/// to scroll is made before any layout happens rather than inferred from a
/// truncation that already occurred. Text that fits is drawn as plain static
/// text, with no timeline running.
struct MarqueeText: View {
    let text: String
    let font: NSFont
    let color: Color

    /// Points per second. Slow enough to read, quick enough to get back.
    var speed: Double = 26
    /// How long each end is held before moving off again.
    var pause: Double = 1.8

    private var textWidth: Double {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    var body: some View {
        GeometryReader { proxy in
            let available = proxy.size.width
            let overflow = textWidth - available

            if overflow > 0.5 {
                scrolling(available: available, overflow: overflow)
            } else {
                label
                    .frame(width: available, height: proxy.size.height, alignment: .leading)
            }
        }
        .frame(height: ceil(font.boundingRectForFont.height))
    }

    private var label: some View {
        Text(text)
            .font(Font(font))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    /// Slides to the end, waits, and slides back.
    ///
    /// The alternative — a continuous ticker with the text repeated behind
    /// itself — shows two copies at once whenever the gap is smaller than the
    /// visible width, which reads as a glitch rather than as scrolling.
    private func scrolling(available: Double, overflow: Double) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
            let offset = offset(
                elapsed: timeline.date.timeIntervalSinceReferenceDate,
                overflow: overflow
            )

            label
                .offset(x: -offset)
                .frame(width: available, alignment: .leading)
                .clipped()
                // Fades whichever end the text is running past, so it slides
                // out of view instead of being chopped off.
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: offset > 1 ? .clear : .black, location: 0),
                            .init(color: .black, location: min(12 / available, 0.18)),
                            .init(color: .black, location: 1 - min(12 / available, 0.18)),
                            .init(color: offset < overflow - 1 ? .clear : .black, location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
    }

    private func offset(elapsed: Double, overflow: Double) -> Double {
        let travel = overflow / speed
        let period = (pause + travel) * 2
        let position = elapsed.truncatingRemainder(dividingBy: period)

        if position < pause {
            return 0
        }
        if position < pause + travel {
            return (position - pause) * speed
        }
        if position < pause * 2 + travel {
            return overflow
        }
        return overflow - (position - pause * 2 - travel) * speed
    }
}
