import Foundation

/// Asks a source application directly for the two things MediaRemote will not
/// report.
///
/// **Artwork for tracks in the library.** Apple Music publishes an https URL
/// in the artwork identifier for catalogue tracks, and an opaque identifier
/// like `af179ea681815796#tr:46c3f80a25e79aee` for a track in the library —
/// with no bytes anywhere. Measured on this machine: the info dictionary
/// carries no `ArtworkData` in any of its four variants, including from a
/// fresh process at the instant of a track change;
/// `MRContentItemGetArtworkData` reports `HasArtworkData = 1` and returns nil;
/// and neither the playback-queue request with `includeArtwork` nor
/// `MRMediaRemoteGetNowPlayingArtwork` ever calls back.
///
/// **A seek made inside the source.** MediaRemote reports a seek made *through*
/// it and nothing else. Measured: Music moved from 119.4s to 45.6s and the
/// content item went on reporting its original anchor, unchanged — so the
/// island's playhead carried on from where it thought it was.
///
/// Both need Automation permission, which macOS asks for once per source. The
/// app must be signed with `com.apple.security.automation.apple-events` and
/// carry `NSAppleEventsUsageDescription` for that prompt to appear at all —
/// under the hardened runtime, an app missing either gets -1743 and the user is
/// never asked. See `Resources/NotchIsland.entitlements`.
///
/// A refusal backs the source off rather than abandoning it, and everything
/// falls back to what MediaRemote provides in the meantime.
actor SourceScripting {
    static let shared = SourceScripting()

    /// Sources with an AppleScript dictionary covering what is needed here.
    /// Only ones that have actually been tried belong in this list.
    private static let scriptable: Set<String> = ["com.apple.Music"]

    static func supports(_ bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return scriptable.contains(bundleIdentifier)
    }

    /// When a source was last refused.
    ///
    /// A refusal is not permanent: the user can grant Automation in System
    /// Settings at any time, and an app that gave up for good would go on
    /// showing the Music icon until it was relaunched. macOS only ever shows
    /// the prompt once — after that a denied event fails immediately and
    /// silently — so retrying costs nothing and picks the permission up as
    /// soon as it is granted.
    private var refusedAt: [String: Date] = [:]

    /// How long to wait before trying a refused source again.
    private static let refusalCooldown: TimeInterval = 60

    private func isRefused(_ bundleIdentifier: String) -> Bool {
        guard let at = refusedAt[bundleIdentifier] else { return false }
        guard Date.now.timeIntervalSince(at) < Self.refusalCooldown else {
            refusedAt.removeValue(forKey: bundleIdentifier)
            return false
        }
        return true
    }

    /// Where the source says it has got to, which is the only account of a
    /// seek the user made in the source's own window.
    func playerPosition(of bundleIdentifier: String) -> TimeInterval? {
        let script = """
            tell application id "\(bundleIdentifier)"
                if player state is stopped then return -1
                return player position
            end tell
            """

        guard let result = run(script, for: bundleIdentifier) else { return nil }
        let position = result.doubleValue
        return position >= 0 ? position : nil
    }

    /// The current track's cover, as the source itself holds it.
    func artwork(of bundleIdentifier: String) -> Data? {
        let script = """
            tell application id "\(bundleIdentifier)"
                if player state is stopped then return missing value
                set theTrack to current track
                if (count of artworks of theTrack) is 0 then return missing value
                return raw data of artwork 1 of theTrack
            end tell
            """

        guard let result = run(script, for: bundleIdentifier) else { return nil }
        let data = result.data
        return data.isEmpty ? nil : data
    }

    private func run(_ source: String, for bundleIdentifier: String) -> NSAppleEventDescriptor? {
        guard !isRefused(bundleIdentifier) else { return nil }
        guard let script = NSAppleScript(source: source) else { return nil }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)

        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            switch code {
            case -1743, -1744:
                // The user said no, or has not been asked and cannot be.
                // Backed off rather than abandoned, so granting it later works
                // without a relaunch.
                refusedAt[bundleIdentifier] = .now
                AppLog.media.notice(
                    "Automation refused for \(bundleIdentifier, privacy: .public) (\(code)); falling back to MediaRemote, retrying in \(Int(Self.refusalCooldown))s"
                )
            case -1728:
                // Nothing is loaded in the source. Ordinary, not a failure.
                break
            default:
                AppLog.media.info(
                    "AppleScript to \(bundleIdentifier, privacy: .public) failed: \(code)")
            }
            return nil
        }

        refusedAt.removeValue(forKey: bundleIdentifier)
        return result
    }
}
