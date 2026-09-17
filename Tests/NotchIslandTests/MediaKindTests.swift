import Foundation
import Testing

@testable import NotchIsland

@Suite("Content type inference")
struct MediaKindTests {
    @Test("An explicit media type from the system wins over everything else")
    func explicitMediaTypeWins() {
        // A podcast played through a music app is still a podcast.
        #expect(
            MediaKind.infer(
                mediaType: "MRMediaRemoteMediaTypePodcast",
                isMusicApp: true,
                bundleIdentifier: "com.apple.Music",
                album: "Some Album",
                artist: "Some Artist",
                duration: 180
            ) == .podcast
        )

        #expect(
            MediaKind.infer(
                mediaType: "MRMediaRemoteMediaTypeVideo",
                isMusicApp: nil,
                bundleIdentifier: nil,
                album: nil,
                artist: nil,
                duration: nil
            ) == .video
        )
    }

    @Test("Known applications are classified by bundle identifier")
    func knownApplications() {
        #expect(kind(bundle: "com.apple.podcasts") == .podcast)
        #expect(kind(bundle: "com.colliderli.iina") == .video)
        #expect(kind(bundle: "com.spotify.client") == .music)
        #expect(kind(bundle: "com.apple.TV") == .video)
    }

    @Test("Browser playback with full track tags is treated as music")
    func browserWithTrackTags() {
        #expect(
            kind(bundle: "com.apple.Safari", album: "Jailer", artist: "Anirudh", duration: 240)
                == .music
        )
    }

    @Test("Long browser playback without an album is treated as a podcast")
    func browserLongForm() {
        #expect(
            kind(bundle: "com.google.Chrome", album: nil, artist: "Some Show", duration: 3600)
                == .podcast
        )
    }

    @Test("Ordinary browser playback is treated as video")
    func browserDefaultsToVideo() {
        #expect(
            kind(bundle: "com.apple.Safari", album: nil, artist: nil, duration: 600) == .video
        )
        // YouTube supplies a channel as the artist but no album.
        #expect(
            kind(bundle: "com.apple.Safari", album: nil, artist: "Some Channel", duration: 842)
                == .video
        )
    }

    @Test("An empty album does not count as having one")
    func emptyAlbumIsNotAnAlbum() {
        #expect(
            kind(bundle: "com.apple.Safari", album: "", artist: "Channel", duration: 300) == .video
        )
    }

    @Test("Unknown sources fall back on whether track tags are present")
    func unknownSources() {
        #expect(
            kind(bundle: "com.example.unknown", album: nil, artist: "Someone", duration: 200)
                == .music
        )
        #expect(
            kind(bundle: "com.example.unknown", album: nil, artist: nil, duration: nil) == .generic
        )
    }

    @Test("A music app flag classifies as music when no media type is given")
    func musicAppFlag() {
        #expect(
            MediaKind.infer(
                mediaType: nil,
                isMusicApp: true,
                bundleIdentifier: "com.example.unknown",
                album: nil,
                artist: nil,
                duration: nil
            ) == .music
        )
    }

    private func kind(
        bundle: String?,
        album: String? = nil,
        artist: String? = nil,
        duration: TimeInterval? = nil
    ) -> MediaKind {
        MediaKind.infer(
            mediaType: nil,
            isMusicApp: nil,
            bundleIdentifier: bundle,
            album: album,
            artist: artist,
            duration: duration
        )
    }
}
