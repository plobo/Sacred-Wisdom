import Foundation

/// A value bound to, or read from, a SQLite statement.
enum SQLiteValue: Sendable, Equatable {
    case integer(Int64)
    case real(Double)
    case text(String)
    case null

    static func text(_ value: String?) -> SQLiteValue { value.map { .text($0) } ?? .null }
    static func integer(_ value: Int?) -> SQLiteValue { value.map { .integer(Int64($0)) } ?? .null }
}

/// One SQL statement with its bindings, for batch execution.
struct SQLStatement: Sendable {
    let sql: String
    let bindings: [SQLiteValue]

    init(_ sql: String, _ bindings: [SQLiteValue] = []) {
        self.sql = sql
        self.bindings = bindings
    }
}

/// A result row keyed by column name.
struct SQLiteRow: Sendable {
    let values: [String: SQLiteValue]

    func string(_ column: String) throws(AppError) -> String {
        guard case .text(let value) = values[column] else { throw Self.missing(column) }
        return value
    }

    func optionalString(_ column: String) -> String? {
        if case .text(let value) = values[column] { return value }
        return nil
    }

    func int(_ column: String) throws(AppError) -> Int {
        guard case .integer(let value) = values[column] else { throw Self.missing(column) }
        return Int(value)
    }

    func optionalInt(_ column: String) -> Int? {
        if case .integer(let value) = values[column] { return Int(value) }
        return nil
    }

    func double(_ column: String) throws(AppError) -> Double {
        switch values[column] {
        case .real(let value): return value
        case .integer(let value): return Double(value)
        default: throw Self.missing(column)
        }
    }

    private static func missing(_ column: String) -> AppError {
        .database("Missing or mistyped column \(column)")
    }
}
