import Foundation

/// Typed errors surfaced across layer boundaries.
enum AppError: Error, Equatable, Sendable {
    case contentNotFound(String)
    case contentCorrupted(String)
    case database(String)
    /// The SwiftData user store (bookmarks, notes, history) failed.
    case userData(String)
    case unexpected(String)

    /// Message suitable for display to the user.
    var userMessage: String {
        switch self {
        case .contentNotFound:
            String(localized: "The requested content could not be found.")
        case .contentCorrupted:
            String(localized: "Some content could not be read. Please try again.")
        case .database:
            String(localized: "The scripture library could not be opened. Please try again.")
        case .userData:
            String(localized: "Your saved passages and notes could not be updated. Please try again.")
        case .unexpected:
            String(localized: "Something went wrong. Please try again.")
        }
    }
}
