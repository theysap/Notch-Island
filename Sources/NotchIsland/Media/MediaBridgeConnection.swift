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
            AppLog.bridge.error("Failed to send \(String(describing: command)): \(error.localizedDescription)")
        }
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
