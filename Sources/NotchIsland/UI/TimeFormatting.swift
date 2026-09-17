import Foundation

enum TimeFormatting {
    /// `3:07`, or `1:04:22` once there is an hour to show. Deliberately not
    /// locale-dependent: this is a playback position, and every media player
    /// shows it this way.
    static func position(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }

        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Time left, as `-1:23`.
    static func remaining(_ seconds: TimeInterval) -> String {
        "-" + position(max(seconds, 0))
    }
}
