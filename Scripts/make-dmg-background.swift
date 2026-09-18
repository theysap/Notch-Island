// Renders the disk image's background picture.
//
// Run with `swift Scripts/make-dmg-background.swift`. It writes
// Scripts/dmg/background.tiff, which carries both a 1x and a 2x
// representation so the window is sharp on a Retina display. The result is
// committed, because a build machine has no business rendering artwork.

import AppKit

let width = 640.0
let height = 400.0

/// Where Finder is told to put the two icons. The arrow is drawn between them,
/// so these have to agree with the positions in Scripts/dmg/layout.applescript.
let appIcon = CGPoint(x: 170, y: 215)
let applicationsIcon = CGPoint(x: 470, y: 215)

func render(scale: CGFloat) -> NSBitmapImageRep {
    let pixelsWide = Int(width * scale)
    let pixelsHigh = Int(height * scale)

    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    let bounds = NSRect(x: 0, y: 0, width: width, height: height)

    // A light field. This is not a style choice: Finder draws the icon labels
    // in a dark grey and offers no way to change it — its icon view exposes
    // text *size*, label position, a background picture and a background
    // colour, and no text colour at all. On a dark background the two names
    // are nearly invisible, so the background is light and the labels land on
    // it legibly.
    NSGradient(
        colors: [
            NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1),
            NSColor(srgbRed: 0.90, green: 0.90, blue: 0.92, alpha: 1),
        ]
    )?.draw(in: bounds, angle: 270)

    // The island itself, hung from the top edge exactly as it is on screen.
    let notchWidth = 132.0
    let notchHeight = 24.0
    let notch = NSBezierPath()
    let left = (width - notchWidth) / 2
    let right = left + notchWidth
    let top = height
    let bottom = height - notchHeight
    let radius = 10.0
    notch.move(to: CGPoint(x: left, y: top))
    notch.line(to: CGPoint(x: left, y: bottom + radius))
    notch.appendArc(
        withCenter: CGPoint(x: left + radius, y: bottom + radius), radius: radius,
        startAngle: 180, endAngle: 270)
    notch.line(to: CGPoint(x: right - radius, y: bottom))
    notch.appendArc(
        withCenter: CGPoint(x: right - radius, y: bottom + radius), radius: radius,
        startAngle: 270, endAngle: 360)
    notch.line(to: CGPoint(x: right, y: top))
    notch.close()
    NSColor.black.setFill()
    notch.fill()

    // A hint of the artwork and the indicator, either side of the housing.
    NSColor(srgbRed: 0.98, green: 0.35, blue: 0.24, alpha: 0.95).setFill()
    NSBezierPath(
        roundedRect: NSRect(x: left + 14, y: height - 17, width: 11, height: 11),
        xRadius: 3, yRadius: 3
    ).fill()
    for (index, barHeight) in [6.0, 11.0, 8.0, 12.0].enumerated() {
        NSBezierPath(
            roundedRect: NSRect(
                x: right - 40 + Double(index) * 7, y: height - 12 - barHeight / 2 + 5,
                width: 3, height: barHeight),
            xRadius: 1.5, yRadius: 1.5
        ).fill()
    }

    // Finder's coordinates run from the top, the drawing here from the bottom.
    func fromTop(_ y: Double) -> Double { height - y }
    func fromTopRect(_ bottomEdgeFromTop: Double) -> Double { height - bottomEdgeFromTop }

    func draw(_ text: String, font: NSFont, colour: NSColor, centreY: Double) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(x: (width - size.width) / 2, y: centreY - size.height / 2),
            withAttributes: attributes)
    }

    draw(
        "NotchIsland",
        font: .systemFont(ofSize: 25, weight: .semibold),
        colour: NSColor(srgbRed: 0.08, green: 0.08, blue: 0.09, alpha: 1), centreY: fromTop(78))
    draw(
        "Drag the app into your Applications folder",
        font: .systemFont(ofSize: 13, weight: .regular),
        colour: NSColor(white: 0, alpha: 0.5), centreY: fromTop(106))

    // The arrow between the two icons.
    let arrowY = fromTop(appIcon.y)
    let arrow = NSBezierPath()
    arrow.lineWidth = 2.5
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: CGPoint(x: 296, y: arrowY))
    arrow.line(to: CGPoint(x: 344, y: arrowY))
    arrow.move(to: CGPoint(x: 332, y: arrowY + 11))
    arrow.line(to: CGPoint(x: 344, y: arrowY))
    arrow.line(to: CGPoint(x: 332, y: arrowY - 11))
    NSColor(white: 0, alpha: 0.32).setStroke()
    arrow.stroke()

    draw(
        "First launch needs Privacy & Security → Open Anyway",
        font: .systemFont(ofSize: 11, weight: .regular),
        colour: NSColor(white: 0, alpha: 0.42), centreY: fromTop(348))

    return rep
}

let one = render(scale: 1)
let two = render(scale: 2)

let directory = URL(fileURLWithPath: "Scripts/dmg", isDirectory: true)
try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

for (rep, name) in [(one, "background.png"), (two, "background@2x.png")] {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not encode \(name)")
    }
    try data.write(to: directory.appendingPathComponent(name))
}

print("wrote Scripts/dmg/background.png and background@2x.png")
print("now: tiffutil -cathidpicheck background.png background@2x.png -out background.tiff")
