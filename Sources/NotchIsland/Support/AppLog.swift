import OSLog

/// Subsystem-wide loggers. Everything the app reports goes through os.Logger so
/// a user can collect diagnostics with `log stream --predicate` without the app
/// writing files of its own.
enum AppLog {
    private static let subsystem = "com.notchisland.app"

    static let bridge = Logger(subsystem: subsystem, category: "bridge")
    static let media = Logger(subsystem: subsystem, category: "media")
    static let window = Logger(subsystem: subsystem, category: "window")
    static let app = Logger(subsystem: subsystem, category: "app")
}
