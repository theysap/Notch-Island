import Foundation

/// One line of output from the media bridge.
/// Who is playing and whether they are playing, with no track metadata.
///
/// The streaming helper cannot obtain metadata after its first attempt (see
/// `NMBFetchOnce`), so this is all it can report. A change here is the app's
/// cue to run a one-shot fetch.
struct BridgeStatus: Sendable, Equatable {
    var isPlaying: Bool
    var sourceBundleIdentifier: String?
    var sourceName: String?
}

enum BridgeMessage: Sendable {
    case ready
    case idle
    /// A fetch that went unanswered. Says nothing about what is playing, so it
    /// must never be treated as idle.
    case noData
    case status(BridgeStatus)
    /// Something moved. The app answers this by re-reading the dictionary,
    /// which is the only way to notice a track change.
    case changed
    case state(NowPlaying)
    case artwork(key: String, mimeType: String, data: Data)
    /// Some sources publish a link to their artwork instead of the bytes.
    /// Apple Music is one: it provides an mzstatic URL and no image data
    /// anywhere in the dictionary.
    case artworkURL(key: String, url: URL)
    case failure(String)
}

/// Wire format. Kept separate from ``NowPlaying`` so the shape the bridge sends
/// can change without the rest of the app caring.
private struct BridgeEnvelope: Decodable {
    let type: String
    let payload: StatePayload?
    let isPlaying: LooseBool?
    let bundleIdentifier: String?
    let parentBundleIdentifier: String?
    let appName: String?
    let key: String?
    let mimeType: String?
    let data: String?
    let url: String?
    let message: String?
}

/// A boolean that may arrive as `true`, `1` or `1.0`.
///
/// MediaRemote's dictionaries are loosely typed, and the strict decoder throws
/// out the *entire* payload over a single mismatched field — which is how a
/// number where a boolean was expected once made every track update vanish
/// without a word.
private struct LooseBool: Decodable {
    let value: Bool

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let boolean = try? container.decode(Bool.self) {
            value = boolean
        } else if let integer = try? container.decode(Int.self) {
            value = integer != 0
        } else if let number = try? container.decode(Double.self) {
            value = number != 0
        } else {
            value = false
        }
    }
}

private struct StatePayload: Decodable {
    let title: String
    let artist: String?
    let album: String?
    let bundleIdentifier: String?
    let parentBundleIdentifier: String?
    let appName: String?
    let mediaType: String?
    let contentType: String?
    let isMusicApp: LooseBool?
    let duration: Double?
    let elapsedTime: Double?
    let playbackRate: Double?
    let timestamp: Double?
    let trackIdentifier: String?
    let isPlaying: LooseBool?
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

        case "nodata":
            return .noData

        case "changed":
            return .changed

        case "status":
            return .status(
                BridgeStatus(
                    isPlaying: envelope.isPlaying?.value ?? false,
                    sourceBundleIdentifier: envelope.parentBundleIdentifier
                        ?? envelope.bundleIdentifier,
                    sourceName: envelope.appName
                )
            )

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

        case "artworkURL":
            guard let key = envelope.key,
                let text = envelope.url,
                let url = ArtworkURL.resolve(text)
            else { return nil }
            return .artworkURL(key: key, url: url)

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
            mediaType: mediaType ?? contentType,
            isMusicApp: isMusicApp?.value,
            bundleIdentifier: source,
            album: album,
            artist: artist,
            duration: duration
        )

        // A duration of zero means "unknown", not "zero seconds long".
        let resolvedDuration = (duration ?? 0) > 0 ? duration : nil

        let rate = playbackRate ?? (isPlaying?.value == true ? 1 : 0)
        let reportedAt = timestamp.map { Date(timeIntervalSince1970: $0) } ?? .now

        return NowPlaying(
            title: title,
            artist: artist,
            album: album,
            kind: kind,
            sourceBundleIdentifier: source,
            sourceName: appName,
            duration: resolvedDuration,
            isPlaying: isPlaying?.value ?? (rate > 0),
            reportedElapsed: elapsedTime ?? 0,
            reportedAt: reportedAt,
            playbackRate: rate,
            trackIdentifier: trackIdentifier ?? "\(title)|\(artist ?? "")|\(album ?? "")"
        )
    }
}
