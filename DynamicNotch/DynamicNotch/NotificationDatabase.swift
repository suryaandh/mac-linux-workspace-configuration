import Foundation
import SQLite3

// Notification Center's on-disk schema is private. Read-only, opt-in, and fail
// explicitly on unsupported versions; never update the system database.
actor NotificationDatabase {
    struct Entry: Sendable {
        let rowID: Int64
        let source: String
        let title: String
        let body: String
    }
    struct Batch: Sendable {
        let entries: [Entry]
        let skipped: Int
    }
    enum ReadError: Error, LocalizedError {
        case unavailable, unsupported, busy
        var errorDescription: String? {
            switch self {
            case .unavailable: "Cannot read notification database. Grant Full Disk Access to DynamicNotch and restart it."
            case .unsupported: "This notification database format is unsupported. No notifications were imported."
            case .busy: "Notification database is busy; retrying."
            }
        }
    }
    private let url: URL
    private let started: Date
    private var cursor: Int64 = 0

    init(url: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db"), started: Date = Date()) {
        self.url = url
        self.started = started
    }

    func poll() throws -> Batch {
        var connection: OpaquePointer?
        guard sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let db = connection else {
            if let connection { sqlite3_close(connection) }
            throw ReadError.unavailable
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 100)
        var maximum: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COALESCE(MAX(rowid), 0) FROM record", -1, &maximum, nil) == SQLITE_OK,
              let maximum else { throw ReadError.unsupported }
        let maximumResult = sqlite3_step(maximum)
        let maximumRow = sqlite3_column_int64(maximum, 0)
        sqlite3_finalize(maximum)
        guard maximumResult == SQLITE_ROW else { throw ReadError.busy }
        if maximumRow < cursor { cursor = 0 }
        var statement: OpaquePointer?
        // Row IDs distinguish equal message text and avoid text-based deduplication.
        let sql = "SELECT r.rowid, a.identifier, r.data FROM record r LEFT JOIN app a ON a.app_id = r.app_id WHERE r.rowid > ? AND r.delivered_date >= ? ORDER BY r.rowid LIMIT 256"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw ReadError.unsupported }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, cursor)
        sqlite3_bind_double(statement, 2, started.timeIntervalSinceReferenceDate)
        var entries: [Entry] = []
        var nextCursor = cursor
        var skipped = 0
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            let row = sqlite3_column_int64(statement, 0)
            nextCursor = max(nextCursor, row)
            let source = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? "Notification"
            let length = Int(sqlite3_column_bytes(statement, 2))
            if let bytes = sqlite3_column_blob(statement, 2), length > 0, length <= 2_000_000,
               let entry = Self.decode(Data(bytes: bytes, count: length), rowID: row, source: source) {
                entries.append(entry)
            } else { skipped += 1 }
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw ReadError.busy }
        cursor = nextCursor
        return Batch(entries: entries, skipped: skipped)
    }

    nonisolated static func decode(_ data: Data, rowID: Int64, source: String) -> Entry? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let request = plist["req"] as? [String: Any] else { return nil }
        // Do not deserialize arbitrary archived classes, attachments or hidden payloads.
        let title = request["titl"] as? String ?? ""
        let subtitle = request["subt"] as? String ?? ""
        let body = request["body"] as? String ?? ""
        guard !title.isEmpty || !subtitle.isEmpty || !body.isEmpty else { return nil }
        let bundle = plist["app"] as? String ?? source
        return Entry(rowID: rowID, source: bundle, title: title,
                     body: [subtitle, body].filter { !$0.isEmpty }.joined(separator: "\n"))
    }
}
