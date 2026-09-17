import AppKit

/// The status item's icon: the island's own silhouette, with the equaliser
/// showing through as negative space.
///
/// Drawn rather than shipped as an asset so it stays in step with the shape the
/// app actually draws, and marked as a template so macOS tints it for a light
/// or dark menu bar.
enum MenuBarIcon {
    static let image: NSImage = {
        let size = NSSize(width: 18, height: 12)

        let image = NSImage(size: size, flipped: false) { rect in
            let body = NSRect(x: 0, y: 0, width: rect.width, height: rect.height)
            let cornerRadius = body.height * 0.42

            // Flat along the top, where it meets the edge of the screen;
            // rounded along the bottom, like the island.
            let path = NSBezierPath()
            path.move(to: NSPoint(x: body.minX, y: body.maxY))
            path.line(to: NSPoint(x: body.minX, y: body.minY + cornerRadius))
            path.curve(
                to: NSPoint(x: body.minX + cornerRadius, y: body.minY),
                controlPoint1: NSPoint(x: body.minX, y: body.minY),
                controlPoint2: NSPoint(x: body.minX, y: body.minY)
            )
            path.line(to: NSPoint(x: body.maxX - cornerRadius, y: body.minY))
            path.curve(
                to: NSPoint(x: body.maxX, y: body.minY + cornerRadius),
                controlPoint1: NSPoint(x: body.maxX, y: body.minY),
                controlPoint2: NSPoint(x: body.maxX, y: body.minY)
            )
            path.line(to: NSPoint(x: body.maxX, y: body.maxY))
            path.close()

            NSColor.black.setFill()
            path.fill()

            // Bars cut out of the body. Negative space reads better than drawn
            // bars at this size, where a line is barely a pixel.
            let heights: [CGFloat] = [0.38, 0.68, 0.50, 0.80]
            let barWidth: CGFloat = 1.6
            let spacing: CGFloat = 1.5
            let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * spacing
            var x = body.midX - total / 2

            NSGraphicsContext.current?.compositingOperation = .destinationOut
            for fraction in heights {
                let height = body.height * 0.62 * fraction
                let bar = NSRect(x: x, y: body.midY - height / 2, width: barWidth, height: height)
                NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
                x += barWidth + spacing
            }
            NSGraphicsContext.current?.compositingOperation = .sourceOver

            return true
        }

        image.isTemplate = true
        return image
    }()
}
