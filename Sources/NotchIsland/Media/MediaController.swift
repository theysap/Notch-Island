import AppKit
import Observation
import SwiftUI

/// The app's view of what is playing, fed by the bridge.
///
/// Holds the current track, its artwork and the colours drawn from it, and
/// forwards transport commands back to the source application.
@MainActor
@Observable
final class MediaController {
    /// Nil when nothing is playing anywhere, which is when the island hides.
    private(set) var nowPlaying: NowPlaying?

    /// Artwork for the current track, or the source application's icon when the
    /// source publishes no artwork. Several sources never do — YouTube in
    /// Safari among them — so the icon is a normal outcome, not a failure.
    private(set) var artwork: NSImage?
    private(set) var artworkIsSourceIcon = false

    /// Icon of the application the audio is coming from, shown in the expanded
    /// player regardless of whether real artwork was available.
    private(set) var sourceIcon: NSImage?
    private(set) var palette: ArtworkPalette = .neutral

    /// Set while the user drags the progress bar, so incoming position reports
    /// do not fight the drag.
    private(set) var scrubPosition: TimeInterval?

    private let connection = MediaBridgeConnection()
    private var listener: Task<Void, Never>?
    private var artworkKey: String?
    private var artworkDownload: Task<Void, Never>?

    /// Decoded artwork, keyed by the URL it came from. Small, because it only
    /// ever holds what has recently been on screen.
    private var artworkCache: [URL: NSImage] = [:]
    private static let artworkCacheLimit = 24

    // MARK: - Lifecycle

    func start() {
        guard listener == nil else { return }

        listener = Task { [weak self] in
            guard let self else { return }
            let stream = await connection.start()
            for await message in stream {
                self.handle(message)
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        Task { [connection] in await connection.stop() }
    }

    // MARK: - Commands

    func send(_ command: PlaybackCommand) {
        Task { [connection] in await connection.send(command) }
    }

    func togglePlayPause() { send(.playPause) }
    func nextTrack() { send(.next) }
    func previousTrack() { send(.previous) }

    // MARK: - Scrubbing

    func beginScrub(at position: TimeInterval) {
        scrubPosition = position
    }

    func updateScrub(to position: TimeInterval) {
        scrubPosition = position
    }

    func endScrub() {
        guard let position = scrubPosition else { return }
        scrubPosition = nil
        send(.seek(position))

        // Move the local playhead immediately so the bar does not snap back
        // while the source catches up.
        if var track = nowPlaying {
            track.reportedElapsed = position
            track.reportedAt = .now
            nowPlaying = track
        }
    }

    /// Playhead to draw: the drag position while scrubbing, the interpolated
    /// position otherwise.
    func displayPosition(at date: Date) -> TimeInterval {
        scrubPosition ?? nowPlaying?.position(at: date) ?? 0
    }

    func displayProgress(at date: Date) -> Double? {
        guard let track = nowPlaying, let duration = track.duration, duration > 0 else {
            return nil
        }
        if let scrubPosition {
            return min(max(scrubPosition / duration, 0), 1)
        }
        return track.progress(at: date)
    }

    // MARK: - Message handling

    private func handle(_ message: BridgeMessage) {
        switch message {
        case .ready:
            AppLog.media.info("Media bridge ready")
            Task { [connection] in await connection.noteHealthy() }

        case .idle:
            artworkDownload?.cancel()
            artworkDownload = nil
            nowPlaying = nil
            artwork = nil
            artworkKey = nil
            artworkIsSourceIcon = false
            sourceIcon = nil
            palette = .neutral

        case .state(let track):
            apply(track)

        case .artwork(let key, _, let data):
            applyArtwork(key: key, data: data)

        case .artworkURL(let key, let url):
            fetchArtwork(key: key, from: url)

        case .failure(let message):
            AppLog.media.error("Bridge reported: \(message, privacy: .public)")
        }
    }

    private func apply(_ track: NowPlaying) {
        let isNewTrack = nowPlaying?.trackIdentifier != track.trackIdentifier
        nowPlaying = track

        guard isNewTrack else { return }

        // Show the source application's icon straight away. If real artwork
        // follows — it usually arrives in the same burst — it replaces this
        // with no visible gap, and if it never arrives the icon is already
        // there.
        artworkKey = nil
        artworkDownload?.cancel()
        artworkDownload = nil
        applySourceIcon(for: track)
    }

    private func applySourceIcon(for track: NowPlaying) {
        guard let identifier = track.sourceBundleIdentifier,
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
        else {
            sourceIcon = nil
            artwork = nil
            artworkIsSourceIcon = false
            palette = .neutral
            return
        }

        let icon = NSWorkspace.shared.icon(forFile: url.path)
        sourceIcon = icon
        artwork = icon
        artworkIsSourceIcon = true
        palette = ArtworkPalette.extract(from: icon)
    }

    /// Downloads artwork a source linked to rather than supplied.
    ///
    /// The request is cancelled if the track changes before it lands, so a slow
    /// download cannot arrive late and put the previous track's cover over the
    /// current one.
    private func fetchArtwork(key: String, from url: URL) {
        guard key != artworkKey else { return }

        if let cached = artworkCache[url] {
            artworkKey = key
            artwork = cached
            artworkIsSourceIcon = false
            palette = ArtworkPalette.extract(from: cached)
            return
        }

        artworkDownload?.cancel()
        artworkDownload = Task { [weak self] in
            var image = await Self.download(url)
            if image == nil, let alternative = ArtworkURL.sizedAlternative(for: url) {
                image = await Self.download(alternative)
            }

            guard let image else {
                AppLog.media.notice(
                    "Could not load artwork from \(url.host() ?? "source", privacy: .public)")
                return
            }

            guard !Task.isCancelled, let self else { return }
            self.storeArtwork(image, for: url, key: key)
        }
    }

    private static func download(_ url: URL) async -> NSImage? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .returnCacheDataElseLoad

        guard let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
            !data.isEmpty
        else { return nil }

        return NSImage(data: data)
    }

    private func storeArtwork(_ image: NSImage, for url: URL, key: String) {
        if artworkCache.count >= Self.artworkCacheLimit {
            artworkCache.removeAll(keepingCapacity: true)
        }
        artworkCache[url] = image

        artworkKey = key
        artwork = image
        artworkIsSourceIcon = false
        palette = ArtworkPalette.extract(from: image)
    }

    private func applyArtwork(key: String, data: Data) {
        guard key != artworkKey, let image = NSImage(data: data) else { return }
        artworkKey = key
        artwork = image
        artworkIsSourceIcon = false
        palette = ArtworkPalette.extract(from: image)
    }
}

#if DEBUG
extension MediaController {
    /// True when the app was launched with `--simulate-playback`, which feeds
    /// the island a synthetic track instead of starting the bridge.
    ///
    /// The island only appears when something is actually playing, which makes
    /// the window layer — placement, hover, menu bar reservation — awkward to
    /// exercise without commandeering the machine's audio. Debug builds only.
    static var isSimulatingPlayback: Bool {
        CommandLine.arguments.contains("--simulate-playback")
    }

    /// Publishes a synthetic track and advances it, standing in for the bridge.
    func startSimulatedPlayback() {
        let kinds: [MediaKind] = [.music, .video, .podcast]
        var index = 0

        func publish() {
            let kind = kinds[index % kinds.count]
            nowPlaying = NowPlaying(
                title: "Simulated \(kind.rawValue.capitalized) Track",
                artist: "NotchIsland",
                album: "Debug",
                kind: kind,
                sourceBundleIdentifier: Bundle.main.bundleIdentifier,
                sourceName: "Simulator",
                duration: 240,
                isPlaying: true,
                reportedElapsed: 0,
                reportedAt: .now,
                playbackRate: 1,
                trackIdentifier: "simulated-\(index)"
            )
            palette = ArtworkPalette(accent: .orange, background: .black)
            index += 1
        }

        publish()
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard self != nil else { return }
                publish()
            }
        }
    }

    /// Builds a controller with fixed state, for the preview renderer. Lives
    /// here because the properties it sets are file-private for writing, and is
    /// compiled out of release builds.
    static func preview(track: NowPlaying, artwork: NSImage?) -> MediaController {
        let controller = MediaController()
        controller.nowPlaying = track
        controller.sourceIcon = artwork
        if let artwork {
            controller.artwork = artwork
            controller.palette = ArtworkPalette.extract(from: artwork)
        }
        return controller
    }
}
#endif
