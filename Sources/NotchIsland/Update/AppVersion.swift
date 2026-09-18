import Foundation

/// A release version, compared the way people expect rather than the way
/// strings sort: 0.17.10 comes after 0.17.9.
struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    var major: Int
    var minor: Int
    var patch: Int

    init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses `1.2.3`, `v1.2.3`, or a shorter form like `1.2`. Anything after
    /// the patch number — a `-beta` suffix, build metadata — is ignored rather
    /// than refused, so an unfamiliar tag still compares sensibly.
    init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") {
            text.removeFirst()
        }

        // Stop at the first character that cannot be part of `1.2.3`.
        let numeric = text.prefix { $0.isNumber || $0 == "." }
        let parts = numeric.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, let major = Int(parts[0]) else { return nil }

        self.major = major
        self.minor = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        self.patch = parts.count > 2 ? Int(parts[2]) ?? 0 : 0
    }

    var description: String { "\(major).\(minor).\(patch)" }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

extension AppVersion {
    /// The running application's version, from the bundle it was built into.
    /// Nil for a bare `swift build` binary, which has no bundle to read.
    static var current: AppVersion? {
        guard let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        else { return nil }
        return AppVersion(short)
    }
}
