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
        #expect(kind(bundle: "com.netflix.Netflix") == .video)
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

    @Test("A general player is judged by what it is playing, not by being VLC")
    func generalPlayerFollowsContent() {
        // A song in VLC: tagged, and short enough to be one.
        #expect(
            kind(
                bundle: "org.videolan.vlc", album: "Salute - (2008)",
                artist: "Sadhana Sargam", duration: 366) == .music)

        // An untagged file is a video as far as anyone can tell.
        #expect(kind(bundle: "org.videolan.vlc", duration: 366) == .video)
    }

    @Test("Anything feature length in a general player is a video, tags or not")
    func generalPlayerLongForm() {
        // A film, a lecture or a recorded set — not a song, whatever it is
        // tagged as.
        #expect(
            kind(
                bundle: "org.videolan.vlc", album: "Live", artist: "Someone",
                duration: 16 * 60) == .video)

        // Just under the line, with tags, is still a song.
        #expect(
            kind(
                bundle: "com.colliderli.iina", album: "An Album", artist: "Someone",
                duration: 14 * 60) == .music)
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

@Suite("Source artwork")
struct SourceArtworkTests {
    private let caches = URL(fileURLWithPath: "/Users/someone/Library/Caches", isDirectory: true)

    @Test("VLC's cache path is built from the artist and album it reports")
    func vlcPathFromArtistAndAlbum() {
        // Measured on a real track: MediaRemote reported this artist and album,
        // and VLC had written the cover to exactly this directory.
        let directory = SourceArtwork.vlcArtworkDirectory(
            artist: "Krishna Chaitanya", album: "Nuvvila - (2011)", cachesDirectory: caches)

        #expect(
            directory?.path
                == "/Users/someone/Library/Caches/org.videolan.vlc/art/artistalbum/"
                + "Krishna Chaitanya/Nuvvila - (2011)")
    }

    @Test("No artist or album means no lookup")
    func vlcPathNeedsBoth() {
        #expect(
            SourceArtwork.vlcArtworkDirectory(artist: nil, album: "A", cachesDirectory: caches)
                == nil)
        #expect(
            SourceArtwork.vlcArtworkDirectory(artist: "A", album: "", cachesDirectory: caches)
                == nil)
    }

    @Test("A separator in a tag cannot escape the cache directory")
    func vlcPathRejectsSeparators() {
        // VLC does not create a directory for such a name, and building one
        // here would point somewhere else entirely.
        #expect(
            SourceArtwork.vlcArtworkDirectory(
                artist: "../../etc", album: "passwd", cachesDirectory: caches) == nil)
    }

    @Test("Only sources with a route are tried")
    func routesAreKnown() {
        #expect(SourceArtwork.canProvide(for: "org.videolan.vlc"))
        #expect(SourceArtwork.canProvide(for: "com.apple.Music"))
        #expect(!SourceArtwork.canProvide(for: "com.google.Chrome"))
        #expect(!SourceArtwork.canProvide(for: nil))
    }
}
