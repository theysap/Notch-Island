import SwiftUI

/// Placeholder activity mark. Replaced by the per-kind waveforms.
struct ActivityIndicator: View {
    let kind: MediaKind
    let isPlaying: Bool
    let tint: Color

    var body: some View {
        Image(systemName: kind.symbolName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .opacity(isPlaying ? 1 : 0.45)
    }
}
