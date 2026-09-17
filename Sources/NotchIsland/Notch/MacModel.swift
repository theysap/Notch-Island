import Foundation

/// Identifies the machine, for diagnostics and for sanity-checking the notch
/// measurements.
///
/// The island's dimensions are *measured* from the display rather than looked
/// up from a table of models. Every notched Mac reports the areas either side
/// of its camera housing, so measuring is exact on models that do not exist
/// yet, where a table would be wrong. The model identifier is used only to say
/// what the machine is in the log, and to decide whether an implausible
/// measurement should be trusted.
enum MacModel {
    /// For example `Mac15,12`.
    static let identifier: String = {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else {
            return "unknown"
        }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else {
            return "unknown"
        }
        // sysctl returns a null-terminated string; the terminator is not part
        // of the value.
        let characters = bytes.prefix { $0 != 0 }
        return String(decoding: characters, as: UTF8.self)
    }()

    static var isLaptop: Bool {
        identifier.hasPrefix("MacBook") || isAppleSiliconLaptop
    }

    /// Apple silicon machines report generic `MacN,M` identifiers, so the
    /// family has to come from elsewhere. A notch only exists on laptops, and
    /// the display itself is what confirms it.
    private static var isAppleSiliconLaptop: Bool {
        identifier.hasPrefix("Mac") && !identifier.hasPrefix("Macmini")
            && !identifier.hasPrefix("MacPro") && !identifier.hasPrefix("iMac")
            && !identifier.hasPrefix("MacStudio")
    }

    /// Bounds a notch measurement has to fall within to be believed.
    ///
    /// Every notched Mac to date sits far inside these; they exist to catch a
    /// nonsensical reading from an unusual display configuration rather than to
    /// encode any particular model.
    static let plausibleWidth: ClosedRange<CGFloat> = 120...420
    static let plausibleHeight: ClosedRange<CGFloat> = 20...80
}
