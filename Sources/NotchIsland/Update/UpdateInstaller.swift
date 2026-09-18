import CryptoKit
import Foundation

enum UpdateError: LocalizedError {
    case notAnApplication
    case notWritable
    case checksumMissing
    case checksumMismatch
    case noApplicationInImage
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAnApplication:
            "Updates are only available to the packaged app."
        case .notWritable:
            "NotchIsland cannot write to its own location. Move it to Applications and try again."
        case .checksumMissing:
            "The release does not list a checksum for its disk image."
        case .checksumMismatch:
            "The download did not match the checksum published with the release."
        case .noApplicationInImage:
            "The disk image does not contain NotchIsland."
        case .commandFailed(let what):
            "\(what) failed."
        }
    }
}

/// Downloads a release, checks it against the checksum published with it, and
/// puts it in place of the running copy.
///
/// The app is ad-hoc signed and not notarised, so there is no Developer ID for
/// macOS to check and no notarisation ticket to rely on. What can be relied on
/// is that the disk image came from the release over HTTPS and hashes to the
/// digest published beside it — so that is checked, and an update that does
/// not match is discarded rather than installed.
enum UpdateInstaller {
    /// Where the running copy lives, when it is a real application bundle.
    static var installedBundle: URL? {
        let url = Bundle.main.bundleURL
        guard url.pathExtension == "app" else { return nil }
        return url
    }

    static func install(
        _ release: AppRelease,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard let destination = installedBundle else { throw UpdateError.notAnApplication }
        guard FileManager.default.isWritableFile(atPath: destination.path) else {
            throw UpdateError.notWritable
        }

        let image = try await download(release.diskImage, progress: progress)
        defer { try? FileManager.default.removeItem(at: image) }

        try await verify(
            image, named: release.diskImage.lastPathComponent, against: release.checksums)

        let staged = try await unpack(image, matching: destination.lastPathComponent)
        defer { try? FileManager.default.removeItem(at: staged.deletingLastPathComponent()) }

        try replace(destination, with: staged)
        relaunch(destination)
    }

    // MARK: - Steps

    private static func download(
        _ url: URL, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdateError.commandFailed("Downloading the update")
        }

        let expected = response.expectedContentLength
        var data = Data()
        data.reserveCapacity(expected > 0 ? Int(expected) : 1 << 22)

        var lastReported = 0.0
        for try await byte in bytes {
            data.append(byte)
            if expected > 0 {
                let fraction = Double(data.count) / Double(expected)
                // Reporting every byte would swamp the main actor.
                if fraction - lastReported > 0.01 {
                    lastReported = fraction
                    progress(fraction)
                }
            }
        }
        progress(1)

        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("dmg")
        try data.write(to: file)
        return file
    }

    private static func verify(
        _ image: URL, named name: String, against checksums: URL
    ) async throws {
        let (data, response) = try await URLSession.shared.data(from: checksums)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
            let text = String(data: data, encoding: .utf8),
            let expected = Checksums.digest(for: name, in: text)
        else { throw UpdateError.checksumMissing }

        let actual = SHA256.hash(data: try Data(contentsOf: image))
            .map { String(format: "%02x", $0) }
            .joined()

        guard actual == expected else { throw UpdateError.checksumMismatch }
        AppLog.app.notice("Update checksum verified")
    }

    /// Mounts the image, copies the application out of it, and unmounts.
    private static func unpack(_ image: URL, matching bundleName: String) async throws -> URL {
        let mount = FileManager.default.temporaryDirectory
            .appendingPathComponent("notch-update-\(UUID().uuidString)")

        try run(
            "/usr/bin/hdiutil",
            [
                "attach", image.path, "-nobrowse", "-readonly", "-mountpoint", mount.path,
            ])
        defer { try? run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet"]) }

        let contents = try FileManager.default.contentsOfDirectory(
            at: mount, includingPropertiesForKeys: nil)
        guard
            let source = contents.first(where: {
                $0.pathExtension == "app" && $0.lastPathComponent == bundleName
            }) ?? contents.first(where: { $0.pathExtension == "app" })
        else { throw UpdateError.noApplicationInImage }

        // Staged beside the destination so the replacement below is a rename
        // on one volume rather than a copy across two.
        let staging = try FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask,
            appropriateFor: Bundle.main.bundleURL, create: true)
        let staged = staging.appendingPathComponent(bundleName)
        try FileManager.default.copyItem(at: source, to: staged)

        // The image was downloaded, so everything out of it is quarantined.
        // Left in place, the replaced app would be refused on relaunch.
        try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])

        return staged
    }

    private static func replace(_ destination: URL, with staged: URL) throws {
        _ = try FileManager.default.replaceItemAt(destination, withItemAt: staged)
        AppLog.app.notice("Update installed over the running copy")
    }

    /// Starts the new copy once this one has gone.
    ///
    /// It has to wait: the app quits another instance of itself at launch, so
    /// starting the new copy first would only make it quit again.
    private static func relaunch(_ bundle: URL) {
        let script = """
            while /bin/kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do
                /bin/sleep 0.2
            done
            /bin/sleep 0.3
            /usr/bin/open -n "\(bundle.path)"
            """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script]
        try? task.run()
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = arguments

        let output = Pipe()
        task.standardOutput = output
        task.standardError = output
        try task.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            let text = String(data: data, encoding: .utf8) ?? ""
            AppLog.app.error(
                "\(tool, privacy: .public) failed: \(text, privacy: .public)")
            throw UpdateError.commandFailed((tool as NSString).lastPathComponent)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
