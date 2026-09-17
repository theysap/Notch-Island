import Foundation

/// Owns the bridge host process: launches it, streams its output, writes
/// commands to it, and brings it back if it dies.
///
/// The host process also watches its own stdin, so if this app is force-quit
/// and never gets to call ``stop()``, the pipe closes and the host exits on its
/// own rather than lingering.
actor MediaBridgeConnection {
    private var process: Process?
    private var standardInput: FileHandle?
    private var continuation: AsyncStream<BridgeMessage>.Continuation?
    private var relaunchTask: Task<Void, Never>?
    private var consecutiveFailures = 0
    private var isRunning = false

    private var fetchTask: Task<Void, Never>?
    /// Set when a fetch is asked for while one is already running, so a burst
    /// of notifications produces one more fetch rather than a pile of them.
    private var fetchAgain = false

    /// Back-off between relaunch attempts. A bridge that dies immediately and
    /// repeatedly is almost always a broken install, and hammering it would
    /// only burn battery.
    private static let relaunchDelays: [Duration] = [
        .milliseconds(500), .seconds(1), .seconds(2), .seconds(5), .seconds(15),
    ]

    /// Starts the bridge and returns its message stream. Calling this more than
    /// once replaces the previous stream.
    func start() -> AsyncStream<BridgeMessage> {
        let (stream, continuation) = AsyncStream<BridgeMessage>.makeStream(
            bufferingPolicy: .bufferingNewest(64)
        )
        self.continuation?.finish()
        self.continuation = continuation
        isRunning = true

        continuation.onTermination = { [weak self] _ in
            Task { await self?.stop() }
        }

        launch()
        return stream
    }

    func stop() {
        isRunning = false
        fetchTask?.cancel()
        fetchTask = nil
        relaunchTask?.cancel()
        relaunchTask = nil
        teardownProcess()
        continuation?.finish()
        continuation = nil
    }

    func send(_ command: PlaybackCommand) {
        guard let data = command.wireFormat, let handle = standardInput else { return }
        do {
            try handle.write(contentsOf: data)
        } catch {
            // A broken pipe means the host died; the termination handler will
            // already be bringing it back.
            AppLog.bridge.error(
                "Failed to send \(String(describing: command)): \(error.localizedDescription)")
        }
    }

    // MARK: - One-shot metadata fetches

    /// Runs a fresh helper to fetch the now-playing dictionary.
    ///
    /// A new process each time is not an optimisation choice — it is the only
    /// thing that works. `MRMediaRemoteGetNowPlayingInfo` hands its dictionary
    /// to a given process once and then ignores it: measured at 13 asks and 0
    /// replies from a long-lived process across two track changes, while fresh
    /// processes answered correctly at the same moments.
    func fetchMetadata() {
        guard isRunning else {
            AppLog.bridge.notice("fetchMetadata ignored: connection not running")
            return
        }
        guard fetchTask == nil else {
            fetchAgain = true
            return
        }

        fetchTask = Task { [weak self] in
            guard let self else { return }
            await self.runFetchBurst()
            await self.finishFetch()
        }
    }

    private func finishFetch() {
        fetchTask = nil
        if fetchAgain {
            fetchAgain = false
            fetchMetadata()
        }
    }

    /// Fetches, and tries again shortly after if nothing came back.
    ///
    /// A notification arrives before the daemon is ready to hand over the new
    /// dictionary — asking the instant a track changes reliably returns
    /// nothing, while asking a second later returns the new track. So a change
    /// gets a short burst of attempts rather than one, and stops as soon as one
    /// of them answers.
    private static let fetchDelays: [Duration] = [
        .zero, .milliseconds(600), .milliseconds(900), .seconds(2),
    ]

    private func runFetchBurst() async {
        for (index, delay) in Self.fetchDelays.enumerated() {
            if delay != .zero {
                try? await Task.sleep(for: delay)
            }
            guard isRunning, !Task.isCancelled else {
                AppLog.bridge.info("fetch burst stopped early at attempt \(index + 1)")
                return
            }

            let produced = await runOneShot()
            AppLog.bridge.info("fetch attempt \(index + 1): metadata=\(produced)")
            if produced {
                return
            }
        }
    }

    /// Returns true when the helper produced track metadata.
    @discardableResult
    private func runOneShot() async -> Bool {
        guard let resources = try? BridgeResources.locate() else { return false }

        let process = Process()
        process.executableURL = resources.host
        process.arguments = [resources.script.path, resources.library.path]

        var environment = ProcessInfo.processInfo.environment
        environment["NOTCH_BRIDGE_ONCE"] = "1"
        process.environment = environment

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            AppLog.bridge.error("One-shot fetch failed to launch: \(error.localizedDescription)")
            return false
        }

        // The helper gives up on an unanswered query after 1.5s; this is the
        // backstop for a helper that wedges instead.
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(4))
            if process.isRunning {
                process.terminate()
            }
        }

        let data: Data = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let collected = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: collected)
            }
        }
        watchdog.cancel()

        var producedMetadata = false
        for line in data.split(separator: 0x0A) where !line.isEmpty {
            guard let message = BridgeMessage.decode(line: Data(line)) else {
                // Silently dropping these once hid a decoding bug that made
                // every track update disappear.
                AppLog.bridge.notice(
                    "Could not decode helper output: \(String(decoding: line.prefix(200), as: UTF8.self), privacy: .public)"
                )
                continue
            }
            if case .state = message {
                producedMetadata = true
            }
            continuation?.yield(message)
        }

        return producedMetadata
    }

    // MARK: - Process lifecycle

    private func launch() {
        guard isRunning else { return }

        let resources: BridgeResources
        do {
            resources = try BridgeResources.locate()
        } catch {
            AppLog.bridge.fault("Cannot locate bridge resources: \(error.localizedDescription)")
            continuation?.yield(.failure(error.localizedDescription))
            return
        }

        let process = Process()
        process.executableURL = resources.host
        process.arguments = [resources.script.path, resources.library.path]

        let output = Pipe()
        let input = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardInput = input
        process.standardError = errors

        let accumulator = LineAccumulator()
        let continuation = self.continuation

        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            for line in accumulator.append(chunk) {
                if let message = BridgeMessage.decode(line: line) {
                    continuation?.yield(message)
                }
            }
        }

        // The host writes nothing to stderr in normal operation; anything here
        // is a load failure worth seeing in the log.
        errors.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty,
                let text = String(data: chunk, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                !text.isEmpty
            else { return }
            AppLog.bridge.error("bridge stderr: \(text, privacy: .public)")
        }

        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            Task { await self?.handleTermination(status: status) }
        }

        do {
            try process.run()
        } catch {
            AppLog.bridge.error("Failed to launch bridge: \(error.localizedDescription)")
            scheduleRelaunch()
            return
        }

        self.process = process
        self.standardInput = input.fileHandleForWriting
        AppLog.bridge.info("Media bridge started (pid \(process.processIdentifier))")
    }

    private func handleTermination(status: Int32) {
        guard isRunning else { return }
        AppLog.bridge.notice("Media bridge exited with status \(status); restarting")
        teardownProcess()
        scheduleRelaunch()
    }

    private func scheduleRelaunch() {
        guard isRunning, relaunchTask == nil else { return }

        let index = min(consecutiveFailures, Self.relaunchDelays.count - 1)
        let delay = Self.relaunchDelays[index]
        consecutiveFailures += 1

        relaunchTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.relaunch()
        }
    }

    private func relaunch() {
        relaunchTask = nil
        launch()
    }

    /// Called once the bridge produces usable output, so an occasional crash
    /// after hours of running does not inherit a long back-off.
    func noteHealthy() {
        consecutiveFailures = 0
    }

    private func teardownProcess() {
        if let process {
            process.terminationHandler = nil
            (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
            (process.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil
            if process.isRunning {
                process.terminate()
            }
        }
        try? standardInput?.close()
        standardInput = nil
        process = nil
    }
}
