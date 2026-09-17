import Foundation

/// A transport command for the source application, sent through the bridge.
enum PlaybackCommand: Sendable, Equatable {
    case playPause
    case play
    case pause
    case next
    case previous
    case seek(TimeInterval)
    /// Asks the bridge to resend current state, ignoring its duplicate
    /// suppression. Used when the island becomes visible again.
    case refresh

    /// One line of JSON, newline included, ready to write to the bridge.
    var wireFormat: Data? {
        var object: [String: Any]
        switch self {
        case .playPause: object = ["cmd": "playpause"]
        case .play: object = ["cmd": "play"]
        case .pause: object = ["cmd": "pause"]
        case .next: object = ["cmd": "next"]
        case .previous: object = ["cmd": "previous"]
        case .refresh: object = ["cmd": "refresh"]
        case .seek(let position): object = ["cmd": "seek", "value": max(position, 0)]
        }

        guard var data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        data.append(0x0A)
        return data
    }
}
