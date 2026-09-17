import AppKit

/// Measurements of the built-in display's notch, read from the system rather
/// than hardcoded — the notch is a different size on every MacBook model.
struct NotchMetrics: Equatable, Sendable {
    /// Full frame of the screen the island belongs to, in screen coordinates.
    var screenFrame: CGRect
    /// Width of the camera housing.
    var notchWidth: CGFloat
    /// Height of the camera housing, which is also the menu bar height on
    /// notched machines.
    var notchHeight: CGFloat

    /// Horizontal centre of the notch in screen coordinates. The notch is
    /// centred on every current model, but this is derived from the measured
    /// areas rather than assumed.
    var centreX: CGFloat

    /// The island only appears on a display that physically has a notch.
    ///
    /// Measured from the display rather than looked up per model: every notched
    /// Mac reports the areas either side of its camera housing, so this is
    /// exact on machines that do not exist yet, where a table of models would
    /// be wrong.
    static func builtInNotched() -> NotchMetrics? {
        for screen in NSScreen.screens {
            guard screen.isBuiltIn,
                let left = screen.auxiliaryTopLeftArea,
                let right = screen.auxiliaryTopRightArea
            else { continue }

            let width = screen.frame.width - left.width - right.width
            let height = max(left.height, right.height)

            // A screen with no notch reports the two areas as meeting in the
            // middle, leaving nothing between them.
            guard width > 1 else { continue }

            // Refuse a nonsensical reading rather than drawing a malformed
            // island from it.
            guard MacModel.plausibleWidth.contains(width),
                MacModel.plausibleHeight.contains(height)
            else {
                AppLog.window.error(
                    "Ignoring implausible notch measurement \(width, format: .fixed(precision: 1))×\(height, format: .fixed(precision: 1)) on \(MacModel.identifier, privacy: .public)"
                )
                continue
            }

            if abs(left.width - right.width) > 0.5 {
                // Every notched Mac centres the housing. If one ever does not,
                // the island still follows the housing rather than the screen.
                AppLog.window.notice(
                    "Camera housing is not centred: left \(left.width, format: .fixed(precision: 1)), right \(right.width, format: .fixed(precision: 1))"
                )
            }

            return NotchMetrics(
                screenFrame: screen.frame,
                notchWidth: width,
                notchHeight: height,
                centreX: screen.frame.minX + left.width + width / 2
            )
        }
        return nil
    }
}

extension NSScreen {
    /// True for the laptop's own display, as opposed to anything plugged in.
    var isBuiltIn: Bool {
        guard let number = deviceDescription[.init("NSScreenNumber")] as? NSNumber else {
            return false
        }
        return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
    }
}
