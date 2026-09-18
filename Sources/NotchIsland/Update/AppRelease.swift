import Foundation

/// A published release, reduced to what installing one needs.
struct AppRelease: Equatable, Sendable {
    var version: AppVersion
    var notes: String
    var diskImage: URL

    /// The `SHA256SUMS.txt` the release workflow publishes beside the disk
    /// image. Without it an update cannot be verified, and is not installed.
    var checksums: URL
}

/// The slice of GitHub's release JSON that matters here.
struct GitHubRelease: Decodable, Sendable {
    struct Asset: Decodable, Sendable {
        var name: String
        var browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    var tagName: String
    var body: String?
    var draft: Bool
    var prerelease: Bool
    var assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body, draft, prerelease, assets
    }

    /// Nil when the release is not one to offer: a draft, a pre-release, a tag
    /// that is not a version, or a release with nothing to install.
    var release: AppRelease? {
        guard !draft, !prerelease, let version = AppVersion(tagName) else { return nil }

        guard
            let image = assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }),
            let sums = assets.first(where: { $0.name.lowercased().contains("sha256sums") })
        else { return nil }

        return AppRelease(
            version: version,
            notes: body ?? "",
            diskImage: image.browserDownloadURL,
            checksums: sums.browserDownloadURL
        )
    }
}

enum Checksums {
    /// Reads `shasum -a 256` output: a hex digest, whitespace, then the file
    /// name, which may carry a `*` binary marker or a leading path.
    static func digest(for fileName: String, in text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2 else { continue }

            let digest = parts[0].lowercased()
            guard digest.count == 64, digest.allSatisfy(\.isHexDigit) else { continue }

            var name = parts[1...].joined(separator: " ")
            if name.hasPrefix("*") { name.removeFirst() }
            guard (name as NSString).lastPathComponent == fileName else { continue }

            return digest
        }
        return nil
    }
}
