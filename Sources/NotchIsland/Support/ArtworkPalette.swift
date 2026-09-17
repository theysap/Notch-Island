import AppKit
import SwiftUI

/// Colours pulled from artwork, used to tint the island so it feels connected
/// to what is playing.
struct ArtworkPalette: Sendable, Equatable {
    var accent: Color
    /// A darker, desaturated companion used behind the expanded player.
    var background: Color

    static let neutral = ArtworkPalette(
        accent: Color(white: 0.75),
        background: Color(white: 0.09)
    )

    /// Averages the artwork down to a single colour, then pushes saturation and
    /// brightness into a range that stays legible against the notch's black.
    ///
    /// A plain average is deliberate: dominant-colour clustering picks out
    /// vivid details that look wrong when a whole album cover is muted, and it
    /// costs far more per track change.
    static func extract(from image: NSImage) -> ArtworkPalette {
        guard let average = image.averageColor() else { return .neutral }

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        // Greyscale artwork stays grey rather than being given an arbitrary hue.
        let accentSaturation = saturation < 0.08 ? 0.0 : min(max(saturation * 1.35, 0.35), 0.9)

        let accent = Color(
            hue: Double(hue),
            saturation: Double(accentSaturation),
            brightness: Double(min(max(brightness * 1.5, 0.62), 0.98))
        )
        let background = Color(
            hue: Double(hue),
            saturation: Double(accentSaturation * 0.7),
            brightness: Double(min(max(brightness * 0.35, 0.06), 0.18))
        )

        return ArtworkPalette(accent: accent, background: background)
    }
}

private extension NSImage {
    /// Average colour, computed by drawing the image into a 1×1 bitmap and
    /// letting Core Graphics do the downsampling.
    func averageColor() -> NSColor? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        var pixel: [UInt8] = [0, 0, 0, 0]
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        guard pixel[3] > 0 else { return nil }

        return NSColor(
            srgbRed: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )
    }
}
