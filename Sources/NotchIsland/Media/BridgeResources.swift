import Foundation

/// Everything needed to launch the media bridge.
struct BridgeResources: Sendable {
    /// The Apple-signed host process. MediaRemote only answers queries from
    /// binaries Apple signed, which is the entire reason this indirection
    /// exists.
    let host: URL
    let script: URL
    let library: URL

    enum LocationError: LocalizedError {
        case missingHost
        case missingScript
        case missingLibrary

        var errorDescription: String? {
            switch self {
            case .missingHost:
                "The system Perl interpreter at /usr/bin/perl is missing."
            case .missingScript:
                "The media bridge script is missing from the application bundle."
            case .missingLibrary:
                "The media bridge library is missing from the application bundle."
            }
        }
    }

    private static let hostURL = URL(fileURLWithPath: "/usr/bin/perl")
    private static let scriptName = "notch-media-bridge"
    private static let libraryName = "libNotchMediaBridge.dylib"

    static func locate() throws -> BridgeResources {
        let fileManager = FileManager.default

        guard fileManager.isExecutableFile(atPath: hostURL.path) else {
            throw LocationError.missingHost
        }

        guard let script = firstExisting(scriptCandidates()) else {
            throw LocationError.missingScript
        }
        guard let library = firstExisting(libraryCandidates()) else {
            throw LocationError.missingLibrary
        }

        return BridgeResources(host: hostURL, script: script, library: library)
    }

    /// Directory holding the running executable. In a bundle that is
    /// `Contents/MacOS`; during development it is `.build/<config>`.
    private static var executableDirectory: URL? {
        Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent()
    }

    private static func scriptCandidates() -> [URL] {
        var candidates: [URL] = []

        if let override = ProcessInfo.processInfo.environment["NOTCH_BRIDGE_SCRIPT"] {
            candidates.append(URL(fileURLWithPath: override))
        }
        if let bundled = Bundle.main.url(forResource: scriptName, withExtension: "pl") {
            candidates.append(bundled)
        }
        // Running straight out of `swift build`. The build directory sits at a
        // different depth depending on whether the path went through the
        // `.build/debug` symlink, so walk up looking for the package's
        // Resources directory rather than assuming one.
        if let directory = executableDirectory {
            var ancestor = directory
            for _ in 0..<5 {
                candidates.append(ancestor.appending(path: "Resources/\(scriptName).pl"))
                let parent = ancestor.deletingLastPathComponent()
                if parent == ancestor { break }
                ancestor = parent
            }
        }
        return candidates
    }

    private static func libraryCandidates() -> [URL] {
        var candidates: [URL] = []

        if let override = ProcessInfo.processInfo.environment["NOTCH_BRIDGE_LIBRARY"] {
            candidates.append(URL(fileURLWithPath: override))
        }
        if let frameworks = Bundle.main.privateFrameworksURL {
            candidates.append(frameworks.appending(path: libraryName))
        }
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appending(path: libraryName))
        }
        if let directory = executableDirectory {
            candidates.append(directory.appending(path: libraryName))
        }
        return candidates
    }

    private static func firstExisting(_ candidates: [URL]) -> URL? {
        candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
