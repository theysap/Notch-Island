import Foundation
import Observation

/// Which transport button the pointer is over.
enum TransportControl: Hashable, Sendable {
    case previous
    case playPause
    case next
}

/// Shared state between the window controller and the SwiftUI island,
/// including the small pieces of interaction state the views need to remember
/// between redraws.
///
/// That state lives here rather than in the views because `@State` is a macro
/// in the macOS 27 SDK and its plugin ships only with Xcode, not with the
/// Command Line Tools this project builds against. Keeping it in an
/// `@Observable` model costs nothing here — there is exactly one island — and
/// avoids falling back to `ObservableObject`.
@MainActor
@Observable
final class IslandPresentation {
    var layout: IslandLayout
    var isExpanded = false

    /// Transport button currently under the pointer.
    var hoveredControl: TransportControl?

    /// True while the progress bar is being dragged.
    var isScrubbing = false

    /// True while the pointer is over the progress bar, which thickens it.
    var isScrubBarHovered = false

    init(layout: IslandLayout) {
        self.layout = layout
    }

    /// Clears interaction state when the island closes, so it does not reopen
    /// with a button still lit.
    func resetInteraction() {
        hoveredControl = nil
        isScrubbing = false
        isScrubBarHovered = false
    }
}
