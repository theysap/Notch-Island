import Foundation

/// Artwork that a source application holds but MediaRemote will not hand over.
///
/// MediaRemote publishes artwork as an https URL for some tracks and as an
/// opaque identifier for others, and for the second kind it keeps the bytes to
/// itself: measured across Apple Music, Chrome and VLC, the dictionary carries
/// the size and the MIME type — 768×768 `image/jpeg` — while
/// `MRContentItemGetArtworkData` reports `HasArtworkData = 1` and returns nil,
/// and every request variant either answers without the bytes or never calls
/// back at all. See CURRENT.md §4.10.
///
/// So the artwork is fetched from the source instead, by whatever route that
/// particular source offers.
enum SourceArtwork {
    /// Whether this source has a route worth trying.
    static func canProvide(for bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return SourceScripting.supports(bundleIdentifier) || bundleIdentifier == vlcIdentifier
    }

    /// The cover for a track, or nil when this source offers no way to get it.
    static func artwork(for track: NowPlaying) async -> Data? {
        guard let source = track.sourceBundleIdentifier else { return nil }

        // VLC writes the artwork it extracts to its own cache, keyed by the
        // artist and album it reports through MediaRemote — so the two line up
        // exactly, and reading it needs no permission of any kind.
        if source == vlcIdentifier {
            return vlcCachedArtwork(artist: track.artist, album: track.album)
        }

        if SourceScripting.supports(source) {
            return await SourceScripting.shared.artwork(of: source)
        }

        return nil
    }

    // MARK: - VLC

    static let vlcIdentifier = "org.videolan.vlc"

    /// Where VLC keeps the cover it extracted from a local file.
    ///
    /// Measured: a track reported as artist "Krishna Chaitanya", album
    /// "Nuvvila - (2011)" had its cover at
    /// `~/Library/Caches/org.videolan.vlc/art/artistalbum/Krishna Chaitanya/Nuvvila - (2011)/art.jpg`.
    /// VLC also keeps an `arturl` tree keyed by a hash of the artwork's
    /// address, which cannot be reconstructed from anything MediaRemote
    /// reports, so only the artist/album tree is used.
    static func vlcArtworkDirectory(
        artist: String?, album: String?, cachesDirectory: URL
    ) -> URL? {
        guard let artist, !artist.isEmpty, let album, !album.isEmpty else { return nil }

        // A path component cannot contain a separator, and VLC does not create
        // one for a name that does.
        guard !artist.contains("/"), !album.contains("/") else { return nil }

        return
            cachesDirectory
            .appendingPathComponent("org.videolan.vlc", isDirectory: true)
            .appendingPathComponent("art", isDirectory: true)
            .appendingPathComponent("artistalbum", isDirectory: true)
            .appendingPathComponent(artist, isDirectory: true)
            .appendingPathComponent(album, isDirectory: true)
    }

    private static func vlcCachedArtwork(artist: String?, album: String?) -> Data? {
        guard
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
            let directory = vlcArtworkDirectory(
                artist: artist, album: album, cachesDirectory: caches)
        else { return nil }

        // The file is `art.jpg` or `art.png` depending on what was embedded.
        guard
            let entries = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)
        else { return nil }

        let cover = entries.first { $0.lastPathComponent.hasPrefix("art") }
        guard let cover else { return nil }

        return try? Data(contentsOf: cover)
    }
}
