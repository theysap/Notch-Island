import AppKit
import Foundation
import Observation

/// Looks for a newer release, and installs one when asked.
///
/// Checking is cheap and quiet: one request to the releases API on launch and
/// every few hours after. Nothing is downloaded until the user picks the
/// update out of the menu, and nothing is installed that does not match the
/// checksum published with it.
@MainActor
@Observable
final class UpdateChecker {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(AppRelease)
        case downloading(Double)
        case installing
        case failed(String)
    }

    private(set) var state: State = .idle

    /// When the newest release was last looked for, so the menu can say.
    private(set) var lastChecked: Date?

    private let settings: AppSettings
    private let feed: URL
    private var timer: Task<Void, Never>?
    private var work: Task<Void, Never>?

    /// The releases API for the repository this app is published from.
    static let defaultFeed = URL(
        string: "https://api.github.com/repos/theysap/Notch-Island/releases/latest")!

    init(settings: AppSettings, feed: URL? = nil) {
        self.settings = settings
        #if DEBUG
        // Lets the whole path — check, download, verify, install, relaunch —
        // be exercised against a local server instead of a real release.
        let override = ProcessInfo.processInfo.environment["NOTCH_UPDATE_FEED"]
            .flatMap(URL.init(string:))
        #else
        let override: URL? = nil
        #endif
        self.feed = feed ?? override ?? Self.defaultFeed
    }

    isolated deinit {
        timer?.cancel()
        work?.cancel()
    }

    /// Whether this copy can update itself at all. A `swift build` binary
    /// cannot: there is no bundle to replace.
    var canInstall: Bool { UpdateInstaller.installedBundle != nil }

    var availableRelease: AppRelease? {
        if case .available(let release) = state { return release }
        return nil
    }

    var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing: true
        case .idle, .upToDate, .available, .failed: false
        }
    }

    // MARK: - Checking

    func start() {
        guard timer == nil else { return }

        timer = Task { [weak self] in
            // Not on the very first moment of launch; the island matters more.
            try? await Task.sleep(for: .seconds(10))
            while !Task.isCancelled {
                if self?.settings.checksForUpdatesAutomatically == true {
                    await self?.check(userInitiated: false)
                }
                try? await Task.sleep(for: .seconds(6 * 60 * 60))
            }
        }
    }

    func check(userInitiated: Bool) async {
        guard !isBusy else { return }
        if case .available = state, !userInitiated { return }

        state = .checking
        defer { lastChecked = .now }

        do {
            let release = try await newestRelease()
            guard let release else {
                state = .upToDate
                return
            }

            guard let current = AppVersion.current else {
                // A development build has no version to compare against, so
                // offering it an update would be meaningless.
                state = .upToDate
                return
            }

            if release.version > current {
                AppLog.app.notice(
                    "Update available: \(release.version.description, privacy: .public)")
                state = .available(release)
            } else {
                state = .upToDate
            }
        } catch {
            AppLog.app.info("Update check failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    private func newestRelease() async throws -> AppRelease? {
        var request = URLRequest(url: feed)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            // No releases yet is a 404, and is not a failure worth reporting.
            return nil
        }

        return try JSONDecoder().decode(GitHubRelease.self, from: data).release
    }

    // MARK: - Installing

    func installAvailableUpdate() {
        guard case .available(let release) = state, work == nil else { return }

        work = Task { [weak self] in
            guard let self else { return }
            self.state = .downloading(0)

            do {
                try await UpdateInstaller.install(release) { fraction in
                    Task { @MainActor [weak self] in
                        if case .downloading = self?.state {
                            self?.state = .downloading(fraction)
                        }
                    }
                }
                self.state = .installing
                // The replacement is done and the relaunch is scheduled; this
                // copy has to go so the new one can take over.
                NSApplication.shared.terminate(nil)
            } catch {
                AppLog.app.error(
                    "Update failed: \(error.localizedDescription, privacy: .public)")
                self.state = .failed(error.localizedDescription)
            }

            self.work = nil
        }
    }
}
