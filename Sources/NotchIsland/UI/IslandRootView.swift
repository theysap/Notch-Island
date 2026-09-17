import SwiftUI

/// The island. Draws nothing at all when nothing is playing, so the menu bar is
/// left exactly as it was.
struct IslandRootView: View {
    let media: MediaController
    let presentation: IslandPresentation

    private var layout: IslandLayout { presentation.layout }
    private var isExpanded: Bool { presentation.isExpanded && media.nowPlaying != nil }

    var body: some View {
        VStack(spacing: 0) {
            if let track = media.nowPlaying {
                island(for: track)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.bouncy(duration: 0.42, extraBounce: 0.08), value: isExpanded)
        .animation(.smooth(duration: 0.34), value: media.nowPlaying == nil)
    }

    private func island(for track: NowPlaying) -> some View {
        let size = layout.size(expanded: isExpanded)

        return ZStack(alignment: .top) {
            NotchShape(
                shoulderRadius: layout.shoulderRadius,
                bottomRadius: isExpanded ? layout.expandedCornerRadius : layout.compactCornerRadius
            )
            .fill(.black)
            // The shape is what casts the shadow, so the shadow follows the
            // island's outline instead of the window's rectangle.
            .shadow(color: .black.opacity(isExpanded ? 0.55 : 0.3), radius: isExpanded ? 22 : 8, y: 6)

            content(for: track)
                .padding(.horizontal, layout.shoulderRadius)
        }
        .frame(width: size.width, height: size.height)
        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
    }

    @ViewBuilder
    private func content(for track: NowPlaying) -> some View {
        if isExpanded {
            ExpandedPlayerView(media: media, layout: layout, track: track)
                .transition(.opacity)
        } else {
            CompactIslandView(media: media, layout: layout, track: track)
                .transition(.opacity)
        }
    }
}
