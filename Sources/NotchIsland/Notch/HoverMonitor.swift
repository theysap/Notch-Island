import AppKit

/// Reports when the pointer enters and leaves the island's hover zone.
///
/// The panel ignores mouse events while collapsed, so that clicks on the menu
/// bar underneath still land — which rules out tracking areas for detecting the
/// initial hover. Watching the pointer's location instead keeps the collapsed
/// island completely passive.
///
/// Mouse movement monitors need no permissions; only keyboard monitoring does.
@MainActor
final class HoverMonitor {
    /// The area to watch, in screen coordinates. Empty disables the monitor's
    /// effect without tearing it down.
    var zone: CGRect = .zero {
        didSet {
            updatePolling()
            evaluate()
        }
    }

    /// Time the pointer must linger before the island opens. Without it, moving
    /// the pointer across the menu bar on the way somewhere else would open the
    /// player every time.
    var openDelay: Duration = .milliseconds(140)

    /// Grace period before closing, so briefly clipping a corner while reaching
    /// for a button does not dismiss it.
    var closeDelay: Duration = .milliseconds(220)

    private(set) var isInside = false

    private let onChange: (Bool) -> Void
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pollTimer: Timer?
    private var pendingChange: Task<Void, Never>?

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    /// Isolated so it can reach the main-actor state it needs to release.
    isolated deinit {
        stop()
    }

    func start() {
        guard globalMonitor == nil else { return }

        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]

        // Pointer moving over other applications.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }

        // Pointer moving over the island itself, which the global monitor does
        // not see.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            Task { @MainActor in self?.evaluate() }
            return event
        }

        updatePolling()
        evaluate()
    }

    /// Polls the pointer while there is a zone to watch.
    ///
    /// The monitors above cover most movement, but not all of it: a global
    /// monitor only sees events delivered to *another* application, and the
    /// strip of menu bar beside the camera housing does not always have one.
    /// Nor do the monitors fire when the pointer never moves — a window
    /// opening underneath it, a space switch, or a warp.
    ///
    /// The poll is the only thing covering those, so it runs often enough to
    /// feel immediate, and only while something is actually on screen to open.
    private func updatePolling() {
        let wanted = !zone.isEmpty
        guard wanted != (pollTimer != nil) else { return }

        guard wanted else {
            pollTimer?.invalidate()
            pollTimer = nil
            return
        }

        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        pollTimer?.invalidate()
        pollTimer = nil
        pendingChange?.cancel()
        pendingChange = nil
    }

    private func evaluate() {
        let inside = !zone.isEmpty && zone.contains(NSEvent.mouseLocation)
        guard inside != isInside else {
            // The pointer settled back where it was, so cancel a pending flip.
            pendingChange?.cancel()
            pendingChange = nil
            return
        }

        guard pendingChange == nil else { return }

        let delay = inside ? openDelay : closeDelay
        pendingChange = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }

            self.pendingChange = nil

            // Re-check: the pointer may have moved on during the delay.
            let stillInside = !self.zone.isEmpty && self.zone.contains(NSEvent.mouseLocation)
            guard stillInside == inside, stillInside != self.isInside else { return }

            self.isInside = inside
            self.onChange(inside)
        }
    }
}
