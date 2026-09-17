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
