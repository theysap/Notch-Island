import Observation

/// Shared state between the window controller and the SwiftUI island.
@MainActor
@Observable
final class IslandPresentation {
    var layout: IslandLayout
    var isExpanded = false

    init(layout: IslandLayout) {
        self.layout = layout
    }
}
