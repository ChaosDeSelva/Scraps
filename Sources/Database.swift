import Foundation
import SQLite3

enum StorageError: LocalizedError {
    case unavailable(String)
    case newerVersion
    case invalidItem

    var errorDescription: String? {
        switch self {
        case .unavailable(let detail): return "Scraps couldn’t access its local library. \(detail)"
        case .newerVersion: return "This library was created by a newer version of Scraps. Update the app to open it."
        case .invalidItem: return "An item in the library could not be read. Your original database has been left intact."
        }
    }
}

final class Database {
    private var handle: OpaquePointer?
    let url: URL

    init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let error = failure()
            sqlite3_close(handle)
            handle = nil
            throw error
        }
        do {
            sqlite3_busy_timeout(handle, 3_000)
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK else { throw failure() }
            let version = sqlite3_step(statement) == SQLITE_ROW ? sqlite3_column_int(statement, 0) : -1
            sqlite3_finalize(statement)
            guard version >= 0 else { throw failure() }
            guard version <= 1 else { throw StorageError.newerVersion }
            try execute("PRAGMA journal_mode = WAL")
            try execute("PRAGMA synchronous = FULL")
            try execute("CREATE TABLE IF NOT EXISTS scraps (id TEXT PRIMARY KEY NOT NULL, payload BLOB NOT NULL)")
            try execute("PRAGMA user_version = 1")
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            sqlite3_close(handle)
            handle = nil
            throw error
        }
    }

    deinit { sqlite3_close(handle) }

    func load() throws -> [Scrap] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT payload FROM scraps", -1, &statement, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(statement) }
        var items: [Scrap] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else { throw failure() }
            guard let bytes = sqlite3_column_blob(statement, 0) else { throw StorageError.invalidItem }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
            guard let item = try? JSONDecoder().decode(Scrap.self, from: data) else { throw StorageError.invalidItem }
            items.append(item)
        }
        return items
    }

    func save(_ item: Scrap) throws {
        let data = try JSONEncoder().encode(item)
        var statement: OpaquePointer?
        let sql = "INSERT INTO scraps(id,payload) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload"
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, 1, item.id.uuidString, -1, transient) == SQLITE_OK else { throw failure() }
        let bound = data.withUnsafeBytes { sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32($0.count), transient) }
        guard bound == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }

    private func failure() -> StorageError {
        .unavailable(handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open the database.")
    }
}
