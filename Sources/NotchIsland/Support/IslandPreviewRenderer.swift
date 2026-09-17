#if DEBUG
import AppKit
import SwiftUI

/// Renders the island to PNG files so its appearance can be checked without
/// screen-recording permission, which capturing a floating panel would need.
///
/// Debug builds only; the release build that ships has no such flag.
///
///     NotchIsland --render-previews /tmp/previews
@MainActor
enum IslandPreviewRenderer {
    static var requestedDirectory: URL? {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--render-previews"),
            arguments.index(after: flag) < arguments.endIndex
        else { return nil }
        return URL(fileURLWithPath: arguments[arguments.index(after: flag)])
    }

    /// `--render-live <directory>`: renders whatever is actually playing right
    /// now, through the real pipeline rather than from sample data. This is how
    /// a layout problem that only shows up with live metadata gets diagnosed
    /// without screen-recording permission.
    static var requestedLiveDirectory: URL? {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--render-live"),
            arguments.index(after: flag) < arguments.endIndex
        else { return nil }
        return URL(fileURLWithPath: arguments[arguments.index(after: flag)])
    }

    /// `--send-command <name>`: pushes one transport command through the real
    /// app pipeline and quits. Separates "the command path is broken" from
    /// "the click never reached the view", which are otherwise hard to tell
    /// apart without a pointer.
    static var requestedCommand: PlaybackCommand? {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--send-command"),
            arguments.index(after: flag) < arguments.endIndex
        else { return nil }

        switch arguments[arguments.index(after: flag)] {
        case "next": return .next
        case "previous": return .previous
        case "playpause": return .playPause
        case "play": return .play
        case "pause": return .pause
        case let other where other.hasPrefix("seek:"):
            return .seek(Double(other.dropFirst(5)) ?? 0)
        default: return nil
        }
    }

    static func renderLive(into directory: URL, media: MediaController) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let metrics = NotchMetrics.builtInNotched() ?? fallbackMetrics
        let layout = IslandLayout(metrics: metrics)

        let description = liveDescription(media: media)

        try? Data(description.utf8).write(to: directory.appending(path: "live-state.txt"))
        FileHandle.standardOutput.write(Data((description + "\n").utf8))

        for expanded in [false, true] {
            let presentation = IslandPresentation(layout: layout)
            presentation.isExpanded = expanded

            let view = PreviewStage(layout: layout) {
                IslandRootView(media: media, presentation: presentation, settings: AppSettings())
            }

            let name = "live-\(expanded ? "expanded" : "compact").png"
            write(view: view, size: layout.windowSize, to: directory.appending(path: name))
        }
    }

    /// Written alongside the images so the rendered state can be compared
    /// against what the pipeline actually delivered.
    private static func liveDescription(media: MediaController) -> String {
        guard let track = media.nowPlaying else { return "nothing playing" }

        let artwork: String
        if media.artwork == nil {
            artwork = "(none)"
        } else if media.artworkIsSourceIcon {
            artwork = "application icon"
        } else {
            artwork = "real artwork"
        }

        var lines: [String] = []
        lines.append("title: " + (track.title.isEmpty ? "(empty)" : track.title))
        lines.append("artist: " + (track.artist ?? "(none)"))
        lines.append("album: " + (track.album ?? "(none)"))
        lines.append("kind: " + track.kind.rawValue)
        lines.append("source: " + (track.sourceName ?? "(none)"))
        lines.append("bundle: " + (track.sourceBundleIdentifier ?? "(none)"))
        lines.append("duration: " + (track.duration.map { String($0) } ?? "(none)"))
        lines.append("isPlaying: " + String(track.isPlaying))
        lines.append("artwork: " + artwork)
        return lines.joined(separator: "\n")
    }

    private static var fallbackMetrics: NotchMetrics {
        NotchMetrics(
            screenFrame: CGRect(x: 0, y: 0, width: 1710, height: 1112),
            notchWidth: 208,
            notchHeight: 37.5,
            centreX: 855
        )
    }

    static func render(into directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let metrics =
            NotchMetrics.builtInNotched()
            ?? NotchMetrics(
                screenFrame: CGRect(x: 0, y: 0, width: 1710, height: 1112),
                notchWidth: 208,
                notchHeight: 37.5,
                centreX: 855
            )
        let layout = IslandLayout(metrics: metrics)

        for sample in Sample.all {
            for expanded in [false, true] {
                let controller = MediaController.preview(
                    track: sample.track,
                    artwork: sample.artwork
                )
                let presentation = IslandPresentation(layout: layout)
                presentation.isExpanded = expanded
                // Renders the scrubber in its hovered state, which is when the
                // knob is shown.
                presentation.isScrubBarHovered = expanded

                let view = PreviewStage(layout: layout) {
                    IslandRootView(
                        media: controller,
                        presentation: presentation,
                        settings: AppSettings()
                    )
                }

                let name = "\(sample.name)-\(expanded ? "expanded" : "compact").png"
                write(view: view, size: layout.windowSize, to: directory.appending(path: name))
            }
        }

        writeMenuBarIcon(to: directory.appending(path: "menu-bar-icon.png"))

        FileHandle.standardOutput.write(
            Data("Rendered \(Sample.all.count * 2) previews into \(directory.path)\n".utf8)
        )
    }

    /// The status item icon, drawn over a mid grey so the template's shape is
    /// visible in the file.
    private static func writeMenuBarIcon(to url: URL) {
        let icon = MenuBarIcon.image
        let scale = 8.0
        let size = CGSize(width: icon.size.width * scale, height: icon.size.height * scale)

        let view = ZStack {
            Color(white: 0.55)
            Image(nsImage: icon)
                .resizable()
                .frame(width: icon.size.width * scale, height: icon.size.height * scale)
        }
        .frame(width: size.width, height: size.height)

        write(view: view, size: size, to: url)
    }

    private static func write(view: some View, size: CGSize, to url: URL) {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 2

        guard let image = renderer.cgImage,
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL, "public.png" as CFString, 1, nil
            )
        else { return }

        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }

    /// A stand-in for the desktop behind the menu bar, so the island's black is
    /// actually visible in the rendered file.
    private struct PreviewStage<Content: View>: View {
        let layout: IslandLayout
        @ViewBuilder var content: Content

        var body: some View {
            ZStack(alignment: .top) {
                LinearGradient(
                    colors: [
                        Color(red: 0.22, green: 0.26, blue: 0.34),
                        Color(red: 0.42, green: 0.34, blue: 0.46),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Where the menu bar sits, for a sense of scale.
                Rectangle()
                    .fill(.black.opacity(0.18))
                    .frame(height: layout.metrics.notchHeight)

                content
            }
        }
    }

    private struct Sample {
        let name: String
        let track: NowPlaying
        let artwork: NSImage?

        static let all: [Sample] = [
            Sample(
                name: "music",
                track: make(
                    title: "Gudilo Badilo Madilo",
                    artist: "Anirudh Ravichander",
                    album: "Jailer",
                    kind: .music,
                    duration: 264,
                    elapsed: 78
                ),
                artwork: artwork(from: [.systemPink, .systemOrange])
            ),
            Sample(
                name: "video",
                track: make(
                    title: "How the Notch Actually Works",
                    artist: "Some Channel",
                    album: nil,
                    kind: .video,
                    duration: 842,
                    elapsed: 300
                ),
                artwork: artwork(from: [.systemBlue, .systemTeal])
            ),
            Sample(
                name: "podcast",
                track: make(
                    title: "Episode 412: Shipping on Apple Silicon",
                    artist: "The Overcast",
                    album: nil,
                    kind: .podcast,
                    duration: 4820,
                    elapsed: 1200
                ),
                artwork: artwork(from: [.systemPurple, .systemIndigo])
            ),
            // Reproduces what Apple Music publishes while stopped: a
            // registered client with no metadata at all.
            Sample(
                name: "empty-metadata",
                track: make(
                    title: "",
                    artist: nil,
                    album: nil,
                    kind: .music,
                    duration: 0,
                    elapsed: 0,
                    isPlaying: false
                ),
                artwork: artwork(from: [.systemRed, .systemPink])
            ),
            Sample(
                name: "paused",
                track: make(
                    title: "Nothing Much",
                    artist: "Quiet Hours",
                    album: "Stillness",
                    kind: .music,
                    duration: 200,
                    elapsed: 44,
                    isPlaying: false
                ),
                artwork: artwork(from: [.systemGray, .darkGray])
            ),
        ]

        private static func make(
            title: String,
            artist: String?,
            album: String?,
            kind: MediaKind,
            duration: TimeInterval,
            elapsed: TimeInterval,
            isPlaying: Bool = true
        ) -> NowPlaying {
            // Zero means unknown, matching how the bridge reports it.
            let resolvedDuration: TimeInterval? = duration > 0 ? duration : nil
            return NowPlaying(
                title: title,
                artist: artist,
                album: album,
                kind: kind,
                sourceBundleIdentifier: nil,
                sourceName: "Preview",
                duration: resolvedDuration,
                isPlaying: isPlaying,
                reportedElapsed: elapsed,
                reportedAt: .now,
                playbackRate: isPlaying ? 1 : 0,
                trackIdentifier: title
            )
        }

        private static func artwork(from colors: [NSColor]) -> NSImage {
            let size = NSSize(width: 256, height: 256)
            let image = NSImage(size: size)
            image.lockFocus()
            NSGradient(colors: colors)?.draw(
                in: NSRect(origin: .zero, size: size),
                angle: 45
            )
            image.unlockFocus()
            return image
        }
    }
}
#endif
