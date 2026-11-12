import OSLog

/// Unified logging. Messages describe failures in app machinery only; scripture text, notes, questions and
/// search queries are never logged.
enum Log {
    private static let subsystem = "com.sacredwisdom.app"
    static let database = Logger(subsystem: subsystem, category: "database")
    static let userData = Logger(subsystem: subsystem, category: "userData")
    static let downloads = Logger(subsystem: subsystem, category: "downloads")
    static let ai = Logger(subsystem: subsystem, category: "ai")
    static let speech = Logger(subsystem: subsystem, category: "speech")
}
