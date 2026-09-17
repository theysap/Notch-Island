import Foundation

/// One line of output from the media bridge.
enum BridgeMessage: Sendable {
    case ready
    case idle
    case state(NowPlaying)
    case artwork(key: String, mimeType: String, data: Data)
    case failure(String)
}

/// Wire format. Kept separate from ``NowPlaying`` so the shape the bridge sends
/// can change without the rest of the app caring.
private struct BridgeEnvelope: Decodable {
    let type: String
    let payload: StatePayload?
    let key: String?
    let mimeType: String?
    let data: String?
    let message: String?
}

private struct StatePayload: Decodable {
    let title: String
    let artist: String?
    let album: String?
    let bundleIdentifier: String?
    let parentBundleIdentifier: String?
    let appName: String?
    let mediaType: String?
    let isMusicApp: Bool?
    let duration: Double?
    let elapsedTime: Double?
    let playbackRate: Double?
    let timestamp: Double?
    let trackIdentifier: String?
    let isPlaying: Bool?
}

extension BridgeMessage {
    /// Decodes one JSON line. Returns nil for anything unrecognised, so a newer
    /// bridge emitting message types this build does not know about is ignored
    /// rather than treated as a failure.
    static func decode(line: Data) -> BridgeMessage? {
        guard let envelope = try? JSONDecoder().decode(BridgeEnvelope.self, from: line) else {
            return nil
        }

        switch envelope.type {
        case "ready":
            return .ready

        case "idle":
            return .idle

        case "error":
            return .failure(envelope.message ?? "unknown bridge error")

        case "artwork":
            guard let key = envelope.key,
                  let encoded = envelope.data,
                  let bytes = Data(base64Encoded: encoded), !bytes.isEmpty
            else { return nil }
            return .artwork(
                key: key,
                mimeType: envelope.mimeType ?? "application/octet-stream",
                data: bytes
            )

        case "state":
            guard let payload = envelope.payload else { return nil }
            return .state(payload.makeNowPlaying())

        default:
            return nil
        }
    }
}

private extension StatePayload {
    func makeNowPlaying() -> NowPlaying {
        // Browser playback surfaces as the media helper process; the parent is
        // the application a person recognises.
        let source = parentBundleIdentifier ?? bundleIdentifier

        let kind = MediaKind.infer(
            mediaType: mediaType,
            isMusicApp: isMusicApp,
            bundleIdentifier: source,
            album: album,
            artist: artist,
            duration: duration
        )

        // A duration of zero means "unknown", not "zero seconds long".
        let resolvedDuration = (duration ?? 0) > 0 ? duration : nil

        let rate = playbackRate ?? (isPlaying == true ? 1 : 0)
        let reportedAt = timestamp.map { Date(timeIntervalSince1970: $0) } ?? .now

        return NowPlaying(
            title: title,
            artist: artist,
            album: album,
            kind: kind,
            sourceBundleIdentifier: source,
            sourceName: appName,
            duration: resolvedDuration,
            isPlaying: isPlaying ?? (rate > 0),
            reportedElapsed: elapsedTime ?? 0,
            reportedAt: reportedAt,
            playbackRate: rate,
            trackIdentifier: trackIdentifier ?? "\(title)|\(artist ?? "")|\(album ?? "")"
        )
    }
}
