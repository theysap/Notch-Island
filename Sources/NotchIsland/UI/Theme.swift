import SwiftUI

enum Theme {
    /// The island's fill.
    ///
    /// Stated as an explicit sRGB triple rather than `Color.black`, which is
    /// defined in whatever colour space the view is rendered into and can pick
    /// up a colour-management shift. This has to be exactly #000000 so the
    /// island is indistinguishable from the camera housing beside it.
    static let islandBackground = Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1)
}
