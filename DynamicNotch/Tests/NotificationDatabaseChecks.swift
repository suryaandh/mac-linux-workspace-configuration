import Foundation
import SQLite3

@main struct NotificationDatabaseChecks {
    static func main() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("notch-notifications-\(UUID()).db")
        defer { try? FileManager.default.removeItem(at: url) }
        var connection: OpaquePointer?
        precondition(sqlite3_open(url.path, &connection) == SQLITE_OK)
        let db = connection!
        defer { sqlite3_close(db) }
        precondition(sqlite3_exec(db, "CREATE TABLE app(app_id INTEGER, identifier TEXT); CREATE TABLE record(app_id INTEGER, delivered_date REAL, data BLOB); INSERT INTO app VALUES(1, 'com.burbn.instagram');", nil, nil, nil) == SQLITE_OK)
        let now = Date()
        func insert(_ title: String, date: Date, valid: Bool = true) throws {
            let plist: [String: Any] = valid ? ["app": "com.burbn.instagram", "req": ["titl": title, "subt": "Sender", "body": "Hello"]] : ["unsupported": true]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
            var statement: OpaquePointer?
            precondition(sqlite3_prepare_v2(db, "INSERT INTO record VALUES(1, ?, ?)", -1, &statement, nil) == SQLITE_OK)
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_double(statement, 1, date.timeIntervalSinceReferenceDate)
            let inserted = data.withUnsafeBytes { bytes -> Int32 in
                sqlite3_bind_blob(statement, 2, bytes.baseAddress, Int32(bytes.count), nil)
                return sqlite3_step(statement)
            }
            precondition(inserted == SQLITE_DONE)
        }
        try insert("Old private history", date: now.addingTimeInterval(-100))
        let reader = NotificationDatabase(url: url, started: now)
        let initial = try await reader.poll()
        precondition(initial.entries.isEmpty, "Never replay pre-session history")
        try insert("Same notification", date: now)
        try insert("Same notification", date: now)
        try insert("Malformed", date: now, valid: false)
        let batch = try await reader.poll()
        precondition(batch.entries.count == 2 && batch.skipped == 1)
        precondition(batch.entries[0].rowID != batch.entries[1].rowID)
        precondition(batch.entries[0].source == "com.burbn.instagram")
        precondition(batch.entries[0].body == "Sender\nHello")
        let repeated = try await reader.poll()
        precondition(repeated.entries.isEmpty)
        for _ in 0..<257 { try insert("Burst", date: now) }
        let firstPage = try await reader.poll()
        let secondPage = try await reader.poll()
        precondition(firstPage.entries.count == 256 && secondPage.entries.count == 1)
        precondition(sqlite3_exec(db, "DELETE FROM record", nil, nil, nil) == SQLITE_OK)
        let cleared = try await reader.poll()
        precondition(cleared.entries.isEmpty)
        try insert("After reset", date: now)
        let reset = try await reader.poll()
        precondition(reset.entries.count == 1)
        let missing = url.appendingPathExtension("missing")
        do {
            _ = try await NotificationDatabase(url: missing).poll()
            preconditionFailure("Missing database must fail")
        } catch NotificationDatabase.ReadError.unavailable { }
        precondition(!FileManager.default.fileExists(atPath: missing.path), "Read-only open must not create databases")
        print("Database checks passed: read-only, no history replay, equal-text arrivals, decoding, pagination, reset and denied access")
    }
}
