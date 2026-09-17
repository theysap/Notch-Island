import Foundation

/// Turns the artwork link a source publishes into one that can actually be
/// fetched.
enum ArtworkURL {
    /// Large enough for the expanded player on a Retina display, small enough
    /// not to waste bandwidth.
    static let size = 512

    /// Apple's image service hands out templates with size placeholders rather
    /// than finished URLs, and they are useless until those are filled in.
    private static let placeholders: [String: String] = [
        "{w}": "\(size)",
        "{h}": "\(size)",
        "{f}": "jpg",
        "{c}": "bb",
    ]

    static func resolve(_ text: String) -> URL? {
        var resolved = text
        for (placeholder, value) in placeholders {
            resolved = resolved.replacingOccurrences(of: placeholder, with: value)
        }

        guard let url = URL(string: resolved), let scheme = url.scheme?.lowercased(),
            scheme == "https" || scheme == "http"
        else { return nil }

        return url
    }

    /// A second URL to try when the first comes back empty.
    ///
    /// Some of these links point at an image directory rather than an image:
    /// the size and format are expected to be appended. There is no way to tell
    /// which kind a link is by looking at it, so the plain form is tried first
    /// and this is the fallback.
    static func sizedAlternative(for url: URL) -> URL? {
        guard url.pathExtension.isEmpty else { return nil }

        let base =
            url.absoluteString.hasSuffix("/")
            ? String(url.absoluteString.dropLast())
            : url.absoluteString

        return URL(string: "\(base)/\(size)x\(size)bb.jpg")
    }
}
