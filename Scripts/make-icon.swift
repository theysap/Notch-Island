//
//  make-icon.swift
//
//  Draws the application icon and writes an .iconset.
//
//  The icon is generated rather than committed as binary blobs so it can be
//  adjusted in one place and regenerated at every size. Run through
//  Scripts/build-app.sh; it is not needed at runtime.
//
//  usage: swift Scripts/make-icon.swift <output.iconset>

import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.iconset>\n".utf8))
    exit(1)
}

let outputDirectory = URL(fileURLWithPath: arguments[1])
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

/// Draws the icon into a square of the given size.
///
/// The artwork is a rounded tile in the dark grey of a closed display, with the
/// island's own silhouette across the top and an equaliser inside it — the app
/// as it actually appears, rather than a generic music glyph.
func drawIcon(size: CGFloat, into context: CGContext) {
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    // macOS icons sit inside the canvas rather than filling it.
    let inset = size * 0.09
    let tile = rect.insetBy(dx: inset, dy: inset)
    let tileRadius = tile.width * 0.2237  // Apple's squircle proportion.

    let tilePath = CGPath(
        roundedRect: tile, cornerWidth: tileRadius, cornerHeight: tileRadius, transform: nil)

    // Body: a subtle vertical gradient, lighter at the top.
    context.saveGState()
    context.addPath(tilePath)
    context.clip()

    let colours =
        [
            CGColor(srgbRed: 0.16, green: 0.17, blue: 0.20, alpha: 1),
            CGColor(srgbRed: 0.07, green: 0.07, blue: 0.09, alpha: 1),
        ] as CFArray
    if let space = CGColorSpace(name: CGColorSpace.sRGB),
        let gradient = CGGradient(colorsSpace: space, colors: colours, locations: [0, 1])
    {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: tile.midX, y: tile.maxY),
            end: CGPoint(x: tile.midX, y: tile.minY),
            options: []
        )
    }

    // The island: a black bar across the top with rounded lower corners,
    // matching the shape the app actually draws on screen.
    let islandWidth = tile.width * 0.72
    let islandHeight = tile.height * 0.28
    let island = CGRect(
        x: tile.midX - islandWidth / 2,
        y: tile.maxY - islandHeight,
        width: islandWidth,
        height: islandHeight
    )
    let islandPath = CGMutablePath()
    let bottomRadius = islandHeight * 0.42
    islandPath.move(to: CGPoint(x: island.minX, y: island.maxY))
    islandPath.addLine(to: CGPoint(x: island.minX, y: island.minY + bottomRadius))
    islandPath.addQuadCurve(
        to: CGPoint(x: island.minX + bottomRadius, y: island.minY),
        control: CGPoint(x: island.minX, y: island.minY)
    )
    islandPath.addLine(to: CGPoint(x: island.maxX - bottomRadius, y: island.minY))
    islandPath.addQuadCurve(
        to: CGPoint(x: island.maxX, y: island.minY + bottomRadius),
        control: CGPoint(x: island.maxX, y: island.minY)
    )
    islandPath.addLine(to: CGPoint(x: island.maxX, y: island.maxY))
    islandPath.closeSubpath()

    // A wash of the accent colour below the island, so the lower half of the
    // tile is not dead space.
    if let space = CGColorSpace(name: CGColorSpace.sRGB),
        let glow = CGGradient(
            colorsSpace: space,
            colors: [
                CGColor(srgbRed: 1.0, green: 0.45, blue: 0.16, alpha: 0.30),
                CGColor(srgbRed: 1.0, green: 0.45, blue: 0.16, alpha: 0.0),
            ] as CFArray,
            locations: [0, 1]
        )
    {
        context.drawRadialGradient(
            glow,
            startCenter: CGPoint(x: tile.midX, y: island.minY),
            startRadius: 0,
            endCenter: CGPoint(x: tile.midX, y: island.minY),
            endRadius: tile.width * 0.56,
            options: []
        )
    }

    context.addPath(islandPath)
    context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
    context.fillPath()

    // Equaliser bars inside the island, in the app's accent orange.
    let barCount = 4
    let barWidth = islandWidth * 0.072
    let spacing = barWidth * 0.85
    let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
    let heights: [CGFloat] = [0.42, 0.78, 0.55, 0.92]
    let maximumHeight = islandHeight * 0.62

    context.setFillColor(CGColor(srgbRed: 1.0, green: 0.45, blue: 0.16, alpha: 1))
    for index in 0..<barCount {
        let height = maximumHeight * heights[index]
        let bar = CGRect(
            x: island.midX - totalWidth / 2 + CGFloat(index) * (barWidth + spacing),
            y: island.midY - height / 2,
            width: barWidth,
            height: height
        )
        context.addPath(
            CGPath(
                roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2,
                transform: nil))
    }
    context.fillPath()

    context.restoreGState()

    // A hairline edge so the tile reads against both light and dark
    // backgrounds.
    context.addPath(tilePath)
    context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.08))
    context.setLineWidth(max(size * 0.004, 0.5))
    context.strokePath()
}

func writeIcon(pixels: Int, to url: URL) throws {
    guard
        let context = CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else {
        throw CocoaError(.fileWriteUnknown)
    }

    drawIcon(size: CGFloat(pixels), into: context)

    guard let image = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL, "public.png" as CFString, 1, nil)
    else {
        throw CocoaError(.fileWriteUnknown)
    }

    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw CocoaError(.fileWriteUnknown)
    }
}

// The set of sizes iconutil expects.
let variants: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

for variant in variants {
    let suffix = variant.scale == 1 ? "" : "@\(variant.scale)x"
    let name = "icon_\(variant.points)x\(variant.points)\(suffix).png"
    try writeIcon(
        pixels: variant.points * variant.scale, to: outputDirectory.appending(path: name))
}

print("Wrote \(variants.count) icon sizes to \(outputDirectory.path)")
