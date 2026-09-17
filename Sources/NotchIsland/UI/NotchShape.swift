import SwiftUI

/// The island's outline: flush with the top edge of the screen, tucked in at
/// the top with concave shoulders so it reads as part of the bezel, and rounded
/// at the bottom.
///
/// The shoulders sit inside the shape's own rect, so the drawn body spans from
/// `shoulderRadius` to `width - shoulderRadius`. The island's frame therefore
/// has to be that much wider than the content it holds.
struct NotchShape: Shape, Animatable {
    var shoulderRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(shoulderRadius, bottomRadius) }
        set {
            shoulderRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        // Keep the curves from overlapping on a very short or narrow island.
        let shoulder = min(shoulderRadius, rect.width / 2, rect.height)
        let bottom = min(bottomRadius, rect.width / 2 - shoulder, rect.height - shoulder)

        var path = Path()

        // Top-left, flush with the screen edge, curving inwards and down.
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + shoulder, y: rect.minY + shoulder),
            control: CGPoint(x: rect.minX + shoulder, y: rect.minY)
        )

        // Left side down to the rounded bottom-left corner.
        path.addLine(to: CGPoint(x: rect.minX + shoulder, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + shoulder + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX + shoulder, y: rect.maxY)
        )

        // Across the bottom.
        path.addLine(to: CGPoint(x: rect.maxX - shoulder - bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - shoulder, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX - shoulder, y: rect.maxY)
        )

        // Right side back up to the screen edge.
        path.addLine(to: CGPoint(x: rect.maxX - shoulder, y: rect.minY + shoulder))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - shoulder, y: rect.minY)
        )

        path.closeSubpath()
        return path
    }
}
