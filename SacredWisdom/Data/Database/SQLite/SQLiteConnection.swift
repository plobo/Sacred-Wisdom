import Foundation
import SQLite3

/// Serialized access to one SQLite database handle. All SQL in the app goes through this actor.
actor SQLiteConnection {
    enum Location: Sendable, Equatable {
        case inMemory
        case file(URL)
    }

    /// Tells SQLite to copy bound text immediately.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Owns the raw handle and closes it when the connection is released.
    /// `@unchecked Sendable` is sound: the pointer is only ever used from inside this actor.
    private final class Handle: @unchecked Sendable {
        let pointer: OpaquePointer
        init(_ pointer: OpaquePointer) { self.pointer = pointer }
        deinit { sqlite3_close_v2(pointer) }
    }

    private let owner: Handle
    private var handle: OpaquePointer { owner.pointer }

    init(location: Location) throws(AppError) {
        let path: String
        switch location {
        case .inMemory: path = ":memory:"
        case .file(let url): path = url.path
        }
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close_v2(db)
            throw .database("open \(path): \(message)")
        }
        owner = Handle(db)
        try Self.exec(db, "PRAGMA foreign_keys = ON;")
        if case .file = location {
            try Self.exec(db, "PRAGMA journal_mode = WAL;")
        }
    }

    /// Runs one or more SQL statements without bindings (schema scripts, pragmas).
    func execute(_ sql: String) throws(AppError) {
        try Self.exec(handle, sql)
    }

    /// Runs a single statement with bindings, ignoring any result rows.
    func run(_ sql: String, _ bindings: [SQLiteValue] = []) throws(AppError) {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement, sql: sql)
        try step(statement, sql: sql, collect: false)
    }

    /// Runs a single statement and returns its rows.
    func query(_ sql: String, _ bindings: [SQLiteValue] = []) throws(AppError) -> [SQLiteRow] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement, sql: sql)
        return try step(statement, sql: sql, collect: true)
    }

    /// Runs all statements in one transaction. Any failure rolls everything back.
    func transaction(_ statements: [SQLStatement]) throws(AppError) {
        try Self.exec(handle, "BEGIN IMMEDIATE;")
        var cache: [String: OpaquePointer] = [:]
        defer { cache.values.forEach { sqlite3_finalize($0) } }
        do {
            for statement in statements {
                let prepared: OpaquePointer
                if let cached = cache[statement.sql] {
                    sqlite3_reset(cached)
                    sqlite3_clear_bindings(cached)
                    prepared = cached
                } else {
                    prepared = try prepare(statement.sql)
                    cache[statement.sql] = prepared
                }
                try bind(statement.bindings, to: prepared, sql: statement.sql)
                try step(prepared, sql: statement.sql, collect: false)
            }
            try Self.exec(handle, "COMMIT;")
        } catch {
            try? Self.exec(handle, "ROLLBACK;")
            throw error
        }
    }

    // MARK: Private

    private static func exec(_ db: OpaquePointer, _ sql: String) throws(AppError) {
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &message) == SQLITE_OK else {
            let text = message.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(message)
            throw .database(text)
        }
    }

    private func prepare(_ sql: String) throws(AppError) -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw .database("prepare: \(errorMessage) — \(sql)")
        }
        return statement
    }

    private func bind(_ values: [SQLiteValue], to statement: OpaquePointer, sql: String) throws(AppError) {
        guard Int(sqlite3_bind_parameter_count(statement)) == values.count else {
            throw .database("Expected \(sqlite3_bind_parameter_count(statement)) bindings, got \(values.count) — \(sql)")
        }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .integer(let v): result = sqlite3_bind_int64(statement, index, v)
            case .real(let v): result = sqlite3_bind_double(statement, index, v)
            case .text(let v): result = sqlite3_bind_text(statement, index, v, -1, Self.transient)
            case .null: result = sqlite3_bind_null(statement, index)
            }
            guard result == SQLITE_OK else { throw .database("bind: \(errorMessage)") }
        }
    }

    @discardableResult
    private func step(_ statement: OpaquePointer, sql: String, collect: Bool) throws(AppError) -> [SQLiteRow] {
        var rows: [SQLiteRow] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                if collect { rows.append(row(from: statement)) }
            case SQLITE_DONE:
                return rows
            default:
                throw .database("step: \(errorMessage) — \(sql)")
            }
        }
    }

    private func row(from statement: OpaquePointer) -> SQLiteRow {
        var values: [String: SQLiteValue] = [:]
        for column in 0..<sqlite3_column_count(statement) {
            let name = String(cString: sqlite3_column_name(statement, column))
            switch sqlite3_column_type(statement, column) {
            case SQLITE_INTEGER: values[name] = .integer(sqlite3_column_int64(statement, column))
            case SQLITE_FLOAT: values[name] = .real(sqlite3_column_double(statement, column))
            case SQLITE_TEXT: values[name] = .text(String(cString: sqlite3_column_text(statement, column)))
            default: values[name] = .null
            }
        }
        return SQLiteRow(values: values)
    }

    private var errorMessage: String { String(cString: sqlite3_errmsg(handle)) }
}
