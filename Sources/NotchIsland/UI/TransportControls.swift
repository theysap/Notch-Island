import SwiftUI

/// Previous, play/pause, next.
struct TransportControls: View {
    let media: MediaController
    let presentation: IslandPresentation
    let isPlaying: Bool
    let tint: Color

    var body: some View {
        HStack(spacing: 22) {
            button(.previous, symbol: "backward.fill", size: 13) {
                media.previousTrack()
            }

            button(
                .playPause,
                symbol: isPlaying ? "pause.fill" : "play.fill",
                size: 17,
                tint: tint
            ) {
                media.togglePlayPause()
            }
            // Keeps the row from shifting as the symbol changes width.
            .frame(width: 24)

            button(.next, symbol: "forward.fill", size: 13) {
                media.nextTrack()
            }
        }
    }

    private func button(
        _ control: TransportControl,
        symbol: String,
        size: Double,
        tint: Color = .white,
        action: @escaping () -> Void
    ) -> some View {
        let isHovering = presentation.hoveredControl == control

        return Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(isHovering ? tint : .white.opacity(0.88))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size + 12, height: size + 12)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.12 : 1)
        .onHover { hovering in
            if hovering {
                presentation.hoveredControl = control
            } else if presentation.hoveredControl == control {
                presentation.hoveredControl = nil
            }
        }
        .animation(.snappy(duration: 0.16), value: isHovering)
    }
}
