import AppKit
import SwiftUI

/// Puts the island on screen and keeps it in step with the display, the
/// pointer, and whether anything is playing.
@MainActor
final class NotchWindowController {
    private let media: MediaController
    private let settings: AppSettings
    private var presentation: IslandPresentation?
    private var panel: NotchPanel?
    private var hostingView: IslandHostingView<IslandRootView>?
    private var hoverMonitor: HoverMonitor?
    private let menuBarSpacer = MenuBarSpacer()

    init(media: MediaController, settings: AppSettings) {
        self.media = media
        self.settings = settings
    }

    func start() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.screenConfigurationChanged()
            }
        }

        build()

        // Keep the hover zone and hit testing in step with what is playing:
        // with nothing playing there is nothing to hover.
        follow { [weak self] in
            guard let self else { return }
            _ = self.settings.showsIsland(for: self.media.nowPlaying)
            _ = self.settings.reservesMenuBarSpace
            self.refreshInteractivity()
        }
    }

    // MARK: - Window

    private func build() {
        guard let metrics = NotchMetrics.builtInNotched() else {
            AppLog.window.notice("No built-in display with a notch; island stays hidden")
            teardown()
            return
        }

        let layout = IslandLayout(metrics: metrics)
        let presentation = IslandPresentation(layout: layout)
        self.presentation = presentation

        let panel = NotchPanel(contentRect: layout.windowFrame)
        let rootView = IslandRootView(media: media, presentation: presentation, settings: settings)
        let hostingView = IslandHostingView(rootView: rootView)
        hostingView.frame = CGRect(origin: .zero, size: layout.windowSize)

        panel.contentView = hostingView
        panel.setFrame(layout.windowFrame, display: true)
        panel.orderFrontRegardless()

        self.panel = panel
        self.hostingView = hostingView

        let hoverMonitor = HoverMonitor { [weak self] isInside in
            self?.setExpanded(isInside)
        }
        hoverMonitor.start()
        self.hoverMonitor = hoverMonitor

        refreshInteractivity()
        AppLog.window.info(
            "Island placed on notched display: notch \(metrics.notchWidth, format: .fixed(precision: 0))×\(metrics.notchHeight, format: .fixed(precision: 1))"
        )
    }

    private func teardown() {
        menuBarSpacer.remove()
        hoverMonitor?.stop()
        hoverMonitor = nil
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
        presentation = nil
    }

    private func screenConfigurationChanged() {
        // Closing the lid, plugging in a display, or changing resolution can
        // all move or remove the notch. Rebuilding is cheap and avoids trying
        // to reason about which of those happened.
        AppLog.window.info("Screen configuration changed; rebuilding island")
        let wasExpanded = presentation?.isExpanded ?? false
        teardown()
        build()
        if wasExpanded {
            setExpanded(false)
        }
    }

    // MARK: - State

    private func setExpanded(_ expanded: Bool) {
        guard let presentation,
            settings.showsIsland(for: media.nowPlaying) || !expanded
        else { return }
        guard presentation.isExpanded != expanded else { return }

        presentation.isExpanded = expanded
        if !expanded {
            presentation.resetInteraction()
        }
        refreshInteractivity()
    }

    /// Updates the hover zone, and lets the panel take mouse events only while
    /// the island is open. Collapsed, everything passes through to the menu bar
    /// underneath.
    private func refreshInteractivity() {
        guard let presentation, let panel, let hostingView else { return }

        let isVisible = settings.showsIsland(for: media.nowPlaying)
        let expanded = presentation.isExpanded && isVisible

        if !isVisible && presentation.isExpanded {
            presentation.isExpanded = false
            presentation.resetInteraction()
        }

        hoverMonitor?.zone =
            isVisible
            ? presentation.layout.hoverZone(expanded: expanded)
            : .zero

        // Reserved only while the island is actually on screen, so the menu
        // bar is not permanently narrowed when nothing is playing.
        menuBarSpacer.reserve(
            width: isVisible && settings.reservesMenuBarSpace
                ? presentation.layout.menuBarReservation
                : nil
        )

        panel.ignoresMouseEvents = !expanded
        hostingView.interactiveRect =
            expanded
            ? presentation.layout.islandRectInWindow(expanded: true)
            : .zero
    }
}
