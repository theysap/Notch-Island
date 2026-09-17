import Foundation
import Testing
@testable import NotchIsland

@Suite("Playback position")
struct NowPlayingTests {
    private func track(
        elapsed: TimeInterval = 10,
        duration: TimeInterval? = 100,
        isPlaying: Bool = true,
        rate: Double = 1,
        reportedAt: Date
    ) -> NowPlaying {
        NowPlaying(
            title: "Track",
            artist: "Artist",
            album: nil,
            kind: .music,
            sourceBundleIdentifier: nil,
            sourceName: nil,
            duration: duration,
            isPlaying: isPlaying,
            reportedElapsed: elapsed,
            reportedAt: reportedAt,
            playbackRate: rate,
            trackIdentifier: "1"
        )
    }

    @Test("Position advances from the last report while playing")
    func interpolatesWhilePlaying() {
        let reportedAt = Date(timeIntervalSince1970: 1_000_000)
        let playing = track(reportedAt: reportedAt)

        #expect(playing.position(at: reportedAt) == 10)
        #expect(playing.position(at: reportedAt.addingTimeInterval(5)) == 15)
    }

    @Test("Position holds still while paused")
    func holdsWhilePaused() {
        let reportedAt = Date(timeIntervalSince1970: 1_000_000)
        let paused = track(isPlaying: false, rate: 0, reportedAt: reportedAt)

        #expect(paused.position(at: reportedAt.addingTimeInterval(30)) == 10)
    }

    @Test("Playback rate scales how fast the position advances")
    func honoursPlaybackRate() {
        let reportedAt = Date(timeIntervalSince1970: 1_000_000)
        let fast = track(rate: 2, reportedAt: reportedAt)

        #expect(fast.position(at: reportedAt.addingTimeInterval(5)) == 20)
    }

    @Test("Position never runs past the end of the track")
    func clampsToDuration() {
        let reportedAt = Date(timeIntervalSince1970: 1_000_000)
        let playing = track(reportedAt: reportedAt)

        // Long after the track should have ended — a source that stopped
        // reporting must not produce a position beyond its duration.
        #expect(playing.position(at: reportedAt.addingTimeInterval(1_000)) == 100)
        #expect(playing.progress(at: reportedAt.addingTimeInterval(1_000)) == 1)
    }

    @Test("Progress is unavailable without a duration")
    func noProgressWithoutDuration() {
        let reportedAt = Date(timeIntervalSince1970: 1_000_000)
        let live = track(duration: nil, reportedAt: reportedAt)

        #expect(live.progress(at: reportedAt) == nil)
        // Position still accumulates, it just cannot be expressed as a fraction.
        #expect(live.position(at: reportedAt.addingTimeInterval(5)) == 15)
    }

    @Test("Display strings fall back sensibly")
    func displayStrings() {
        var empty = track(reportedAt: .now)
        empty.title = ""
        empty.artist = nil
        empty.album = nil
        empty.sourceName = "Safari"

        #expect(empty.displayTitle == "Safari")
        #expect(empty.displaySubtitle == "Safari")

        var full = track(reportedAt: .now)
        full.artist = "Anirudh"
        full.album = "Jailer"
        #expect(full.displaySubtitle == "Anirudh — Jailer")
    }
}
