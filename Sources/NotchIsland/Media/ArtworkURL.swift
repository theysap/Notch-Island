import Foundation

/// Turns the artwork link a source publishes into one that can actually be
/// fetched.
enum ArtworkURL {
    /// Apple's image service hands out templates with size placeholders rather
    /// than finished URLs, and they are useless until those are filled in.
    private static let placeholders: [String: String] = [
        "{w}": "\(size)",
        "{h}": "\(size)",
        "{f}": "jpg",
        "{c}": "bb",
    ]

    /// Large enough for the expanded player on a Retina display, small enough
    /// not to waste bandwidth on a thumbnail.
    private static let size = 512

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
}
