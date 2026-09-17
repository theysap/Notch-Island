import Foundation

/// A snapshot of whatever is playing on the system.
///
/// Position is stored as the elapsed time the source reported plus the moment
/// it reported it, rather than as a running counter. That way the UI can
/// interpolate the playhead at display refresh rate without the app polling the
/// source, and a paused track simply stops advancing.
struct NowPlaying: Sendable, Equatable {
    var title: String
    var artist: String?
    var album: String?
    var kind: MediaKind

    /// Bundle identifier of the application a person would recognise. For
    /// browser playback MediaRemote reports the media process
    /// (`com.apple.WebKit.GPU`), so the parent identifier is preferred.
    var sourceBundleIdentifier: String?
    var sourceName: String?

    var duration: TimeInterval?
    var isPlaying: Bool

    /// Elapsed time as reported, and when it was reported.
    var reportedElapsed: TimeInterval
    var reportedAt: Date
    var playbackRate: Double

    /// Identifies the track, so the UI can tell a new track from an update to
    /// the current one.
    var trackIdentifier: String

    /// Playhead position at a given moment, extrapolated from the last report.
    func position(at date: Date = .now) -> TimeInterval {
        guard isPlaying, playbackRate > 0 else {
            return clamp(reportedElapsed)
        }
        let drift = date.timeIntervalSince(reportedAt) * playbackRate
        return clamp(reportedElapsed + drift)
    }

    /// Fraction played, 0...1, or nil when the source reports no duration —
    /// live streams and radio, where a progress bar would be a lie.
    func progress(at date: Date = .now) -> Double? {
        guard let duration, duration > 0 else { return nil }
        return min(max(position(at: date) / duration, 0), 1)
    }

    private func clamp(_ value: TimeInterval) -> TimeInterval {
        guard let duration, duration > 0 else { return max(value, 0) }
        return min(max(value, 0), duration)
    }

    /// Whether there is anything worth putting on screen.
    ///
    /// A registered source with no title, no artist and no duration is a player
    /// sitting open with nothing loaded.
    var hasDisplayableMetadata: Bool {
        !title.isEmpty || !(artist ?? "").isEmpty || duration != nil
    }

    /// What to show when a source publishes no title at all.
    var displayTitle: String {
        title.isEmpty ? (sourceName ?? "Now Playing") : title
    }

    var displaySubtitle: String? {
        let parts = [artist, album].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? sourceName : parts.joined(separator: " — ")
    }
}
