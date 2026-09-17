import Foundation

/// What is playing, which decides how the island animates on the right-hand
/// side of the notch.
enum MediaKind: String, Sendable, CaseIterable {
    /// Equaliser bars.
    case music
    /// A playhead sweep.
    case video
    /// A speech-cadence waveform.
    case podcast
    /// A soft pulse, for audio that does not identify itself.
    case generic

    var symbolName: String {
        switch self {
        case .music: "music.note"
        case .video: "play.rectangle.fill"
        case .podcast: "mic.fill"
        case .generic: "waveform"
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .music: "Music"
        case .video: "Video"
        case .podcast: "Podcast"
        case .generic: "Audio"
        }
    }
}

extension MediaKind {
    /// Applications that host arbitrary media, where the bundle identifier says
    /// nothing useful about what is actually playing.
    private static let browserIdentifiers: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "org.mozilla.firefox",
        "company.thebrowser.Browser",
        "company.thebrowser.dia",
        "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi",
        "org.chromium.Chromium",
        "ai.perplexity.comet",
    ]

    private static let podcastIdentifiers: Set<String> = [
        "com.apple.podcasts",
        "fm.overcast.overcast",
        "au.com.shiftyjelly.pocketcasts.osx",
        "com.pocketcasts.desktop",
        "org.videolan.podcast",
        "com.bookmate.listen",
    ]

    private static let videoIdentifiers: Set<String> = [
        "com.apple.TV",
        "com.apple.QuickTimePlayerX",
        "com.colliderli.iina",
        "org.videolan.vlc",
        "com.netflix.Netflix",
        "tv.plex.desktop",
        "com.plexapp.plexmediaplayer",
        "com.mpv",
        "io.mpv",
    ]

    private static let musicIdentifiers: Set<String> = [
        "com.apple.Music",
        "com.apple.iTunes",
        "com.spotify.client",
        "com.tidal.desktop",
        "com.deezer.deezer-desktop",
        "com.soundcloud.desktop",
        "org.niltsh.MPlayerX",
        "com.roon.Roon",
        "com.doppler.app",
    ]

    /// A podcast episode is far longer than a song. Used only when the source
    /// application is a browser and nothing better is known.
    private static let longFormThreshold: TimeInterval = 30 * 60

    /// Works out what is playing from whatever the system was willing to say.
    ///
    /// MediaRemote reports an explicit media type for well-behaved native
    /// applications, and nothing at all for browsers — which is where most
    /// video and a good deal of podcast listening actually happens. The
    /// fallbacks below are ordered most-trustworthy first.
    static func infer(
        mediaType: String?,
        isMusicApp: Bool?,
        bundleIdentifier: String?,
        album: String?,
        artist: String?,
        duration: TimeInterval?
    ) -> MediaKind {
        // The system told us outright.
        if let mediaType {
            let normalised = mediaType.lowercased()
            if normalised.contains("podcast") { return .podcast }
            if normalised.contains("video") { return .video }
            if normalised.contains("music") { return .music }
        }

        if isMusicApp == true { return .music }

        if let bundleIdentifier {
            if podcastIdentifiers.contains(bundleIdentifier) { return .podcast }
            if videoIdentifiers.contains(bundleIdentifier) { return .video }
            if musicIdentifiers.contains(bundleIdentifier) { return .music }

            if browserIdentifiers.contains(bundleIdentifier) {
                // A full set of track tags in a browser almost always means a
                // streaming music service rather than a video.
                if let album, !album.isEmpty, let artist, !artist.isEmpty {
                    return .music
                }
                // Anything running past half an hour in a browser is far more
                // likely to be an episode than a song.
                if let duration, duration > longFormThreshold {
                    return .podcast
                }
                return .video
            }
        }

        // An unknown native application that publishes track tags is treated as
        // a music player; otherwise the neutral pulse is used.
        if let artist, !artist.isEmpty { return .music }
        return .generic
    }
}
