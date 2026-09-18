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

    /// Keeps the playhead honest against sources that seek without telling
    /// MediaRemote, and fetches artwork MediaRemote does not publish. See
    /// `SourceScripting` for what was measured.
    private var sourceSync: Task<Void, Never>?
    private var sourceArtwork: Task<Void, Never>?
    private var artworkKey: String?
    private var artworkDownload: Task<Void, Never>?

    /// Key of the download currently running. Repeat requests for the same
    /// artwork arrive routinely, and without this each one cancels the last —
    /// so the cover never finished loading at all.
    private var artworkInFlightKey: String?

    /// The last status the streaming helper reported. Metadata arrives
    /// separately, from one-shot fetches.
    private var status: BridgeStatus?

    /// Decoded artwork, keyed by the URL it came from. Small, because it only
    /// ever holds what has recently been on screen.
    private var artworkCache: [URL: NSImage] = [:]
    private static let artworkCacheLimit = 24

    /// Cache keys, least recently used first, so a full cache drops its
    /// coldest cover rather than everything it holds.
    private var artworkCacheOrder: [URL] = []

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

        sourceSync = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await self?.resyncPositionFromSource()
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        sourceSync?.cancel()
        sourceSync = nil
        sourceArtwork?.cancel()
        sourceArtwork = nil
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
        AppLog.media.info(
            "bridge message: \(String(describing: message).prefix(60), privacy: .public)")
        switch message {
        case .ready:
            AppLog.media.info("Media bridge ready")
            Task { [connection] in
                await connection.noteHealthy()
                // First read of the dictionary. Anything already playing shows
                // up here, if the daemon has an undelivered change to hand over.
                await connection.fetchMetadata()
            }

        case .noData:
            // A fetch that went unanswered. Keep what is already on screen.
            break

        case .changed:
            Task { [connection] in await connection.fetchMetadata() }

        case .status(let status):
            apply(status)

        case .idle:
            status = nil
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

    /// Applies a status update, and asks for fresh metadata.
    ///
    /// Playback state arrives here rather than with the metadata, because the
    /// streaming helper can see it change and cannot see the dictionary.
    private func apply(_ status: BridgeStatus) {
        let previous = self.status
        self.status = status
        AppLog.media.info(
            "status: playing=\(status.isPlaying), source=\(status.sourceName ?? "none", privacy: .public)"
        )

        // A different application took over: what is on screen is now stale,
        // and there is nothing to show until a fetch lands.
        if let source = status.sourceBundleIdentifier,
            let current = nowPlaying?.sourceBundleIdentifier,
            source != current
        {
            nowPlaying = nil
            artworkKey = nil
        }

        if var track = nowPlaying, track.isPlaying != status.isPlaying {
            // Pin the playhead where it had got to before changing state, so a
            // pause stops the clock instead of letting it run on.
            track.reportedElapsed = track.position(at: .now)
            track.reportedAt = .now
            track.isPlaying = status.isPlaying
            track.playbackRate = status.isPlaying ? max(track.playbackRate, 1) : 0
            nowPlaying = track
        }

        // Anything that moved is worth re-reading the dictionary for; the
        // daemon answers only when it has actually changed.
        if previous != status {
            Task { [connection] in await connection.fetchMetadata() }
        }

        synthesisePlaceholderIfNeeded()
    }

    /// Puts *something* on screen while waiting for metadata.
    ///
    /// Starting the app part-way through a track leaves nothing to show: the
    /// daemon hands the dictionary over only when it changes, and a track
    /// already under way has not changed. Polling does not help — measured at
    /// sixteen consecutive fetches over 25 seconds, every one unanswered.
    ///
    /// So the island shows the source it can see, and fills in properly at the
    /// next track change. This only ever happens while something really is
    /// playing; a source that is merely open still shows nothing at all.
    private func synthesisePlaceholderIfNeeded() {
        guard nowPlaying == nil, let status, status.isPlaying,
            status.sourceBundleIdentifier != nil
        else { return }

        let placeholder = NowPlaying(
            title: "",
            artist: nil,
            album: nil,
            kind: .generic,
            sourceBundleIdentifier: status.sourceBundleIdentifier,
            sourceName: status.sourceName,
            duration: nil,
            isPlaying: true,
            reportedElapsed: 0,
            reportedAt: .now,
            playbackRate: 1,
            trackIdentifier: "placeholder"
        )

        nowPlaying = placeholder
        applySourceIcon(for: placeholder)
    }

    private func apply(_ track: NowPlaying) {
        var track = track

        if track.sourceName == nil {
            track.sourceName = status?.sourceName
        }

        // Playing state comes from the status, which is driven by
        // notifications and so is current. The dictionary's own rate is a
        // snapshot from whenever the fetch happened to land — right after a
        // track change it can still read as stopped — and writing that back
        // into the status leaves the island showing paused over music that is
        // playing.
        if let status {
            track.isPlaying = status.isPlaying
            if !status.isPlaying {
                track.playbackRate = 0
            } else if track.playbackRate == 0 {
                track.playbackRate = 1
            }
        }

        // Nothing new: a second fetch for the same track lands routinely,
        // because a change produces both a status and a `changed` event.
        if let current = nowPlaying, current == track {
            return
        }

        let isNewTrack = nowPlaying?.trackIdentifier != track.trackIdentifier
        nowPlaying = track
        AppLog.media.info(
            "Now playing: \(track.displayTitle, privacy: .public) — playing=\(track.isPlaying), new=\(isNewTrack)"
        )

        guard isNewTrack else { return }

        // Show the source application's icon straight away. If real artwork
        // follows — it usually arrives in the same burst — it replaces this
        // with no visible gap, and if it never arrives the icon is already
        // there.
        artworkKey = nil
        artworkInFlightKey = nil
        artworkDownload?.cancel()
        artworkDownload = nil
        applySourceIcon(for: track)
        fetchArtworkFromSource(for: track)
    }

    /// Gets the cover from the source application, for the tracks MediaRemote
    /// publishes no artwork for at all.
    ///
    /// Deliberately late and conditional: a track whose artwork is a URL has
    /// it within a few hundred milliseconds, and when it does there is nothing
    /// to go and find. Only a track still showing nothing but the source's
    /// icon is worth the work.
    private func fetchArtworkFromSource(for track: NowPlaying) {
        guard SourceArtwork.canProvide(for: track.sourceBundleIdentifier) else { return }

        let key = track.trackIdentifier
        sourceArtwork?.cancel()
        sourceArtwork = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self, self.stillWaitingForArtwork(of: key) else { return }

            let data = await SourceArtwork.artwork(for: track)
            guard !Task.isCancelled, let data, let image = NSImage(data: data) else { return }
            self.applyArtworkFromSource(image, for: key)
        }
    }

    /// True while the track is still current and showing nothing but an icon.
    private func stillWaitingForArtwork(of trackIdentifier: String) -> Bool {
        nowPlaying?.trackIdentifier == trackIdentifier && (artwork == nil || artworkIsSourceIcon)
    }

    private func applyArtworkFromSource(_ image: NSImage, for trackIdentifier: String) {
        guard stillWaitingForArtwork(of: trackIdentifier) else { return }

        artworkKey = trackIdentifier
        artwork = image
        artworkIsSourceIcon = false
        palette = ArtworkPalette.extract(from: image)
        AppLog.media.info("Artwork read from the source application")
    }

    /// Pulls the playhead back to where the source says it is.
    ///
    /// A seek made in the source's own window is reported nowhere by
    /// MediaRemote — measured: Music moved from 119.4s to 45.6s while the
    /// content item went on reporting its original anchor — so without this
    /// the island keeps counting from wherever it last thought it was.
    private func resyncPositionFromSource() async {
        guard scrubPosition == nil, let track = nowPlaying, track.isPlaying,
            let source = track.sourceBundleIdentifier, SourceScripting.supports(source)
        else { return }

        guard let actual = await SourceScripting.shared.playerPosition(of: source) else { return }

        // The await took time, and the drag may have started in it.
        guard scrubPosition == nil, var current = nowPlaying,
            current.trackIdentifier == track.trackIdentifier
        else { return }

        // Only a real disagreement is worth acting on. Normally there is none:
        // measured against Music over successive polls, the interpolated
        // playhead and the source's own position agree to about 3ms. So
        // anything approaching a second means the source moved without saying
        // so, which is exactly the case this exists for.
        let believed = current.position(at: .now)
        guard abs(believed - actual) > 0.75 else { return }

        current.reportedElapsed = actual
        current.reportedAt = .now
        nowPlaying = current
        AppLog.media.info(
            "Playhead resynced from the source: \(believed, format: .fixed(precision: 1))s -> \(actual, format: .fixed(precision: 1))s"
        )
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
        guard key != artworkKey, key != artworkInFlightKey else { return }

        if let cached = artworkCache[url] {
            noteArtworkUse(url)
            artworkKey = key
            artwork = cached
            artworkIsSourceIcon = false
            palette = ArtworkPalette.extract(from: cached)
            return
        }

        artworkDownload?.cancel()
        artworkInFlightKey = key
        artworkDownload = Task { [weak self] in
            var image = await Self.download(url)
            if image == nil, let alternative = ArtworkURL.sizedAlternative(for: url) {
                image = await Self.download(alternative)
            }

            guard let image else {
                AppLog.media.notice(
                    "Could not load artwork (cancelled: \(Task.isCancelled)) from \(url.absoluteString, privacy: .public)"
                )
                return
            }

            guard !Task.isCancelled, let self else { return }
            self.artworkInFlightKey = nil
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
        artworkCache[url] = image
        noteArtworkUse(url)

        while artworkCache.count > Self.artworkCacheLimit, !artworkCacheOrder.isEmpty {
            artworkCache.removeValue(forKey: artworkCacheOrder.removeFirst())
        }

        artworkKey = key
        artwork = image
        artworkIsSourceIcon = false
        palette = ArtworkPalette.extract(from: image)
    }

    /// Marks a cover as the most recently used, for eviction order.
    private func noteArtworkUse(_ url: URL) {
        artworkCacheOrder.removeAll { $0 == url }
        artworkCacheOrder.append(url)
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
