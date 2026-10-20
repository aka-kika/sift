import Foundation
import SQLite3

/// What went wrong opening the data store at launch, for the alert ContentView shows.
enum DataStoreOpenIssue: Equatable {
    /// The file was damaged: it was moved to `URL` and a fresh, empty store started.
    case setAside(URL)
    /// The file could not be opened but is not damaged (for example, a newer Sift
    /// wrote it). It stays untouched at `URL`; this session keeps changes in memory.
    case leftInPlace(URL)

    var title: String {
        switch self {
        case .setAside: return "Sift started with an empty library"
        case .leftInPlace: return "Sift could not open its library"
        }
    }

    var message: String {
        switch self {
        case .setAside(let url):
            return "The library file was damaged, so Sift moved it aside and started fresh. Nothing was deleted: the old file is \(url.lastPathComponent) in \(url.deletingLastPathComponent().path). Licence keys are in the Keychain and were not touched."
        case .leftInPlace(let url):
            return "The library file at \(url.path) could not be opened, but it is not damaged, so Sift left it as it is. It may come from a newer version of Sift: install the latest version. Until then, changes you make are not saved."
        }
    }

    var fileURL: URL {
        switch self {
        case .setAside(let url), .leftInPlace(let url): return url
        }
    }
}

/// Decides whether a store that failed to open is really damaged. A failed open
/// alone is not proof: a store from a newer build, or a file held by another
/// process, fails the same way and must not be moved.
enum DataStoreRecovery {
    /// True only when SQLite itself reports the file as damaged or not a database.
    /// A missing file is not damaged.
    static func isCorrupt(storeURL: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return false }
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        let openStatus = sqlite3_open_v2(storeURL.path, &db, SQLITE_OPEN_READONLY, nil)
        if openStatus == SQLITE_CORRUPT || openStatus == SQLITE_NOTADB { return true }
        guard openStatus == SQLITE_OK else { return false }

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let prepareStatus = sqlite3_prepare_v2(db, "PRAGMA quick_check", -1, &statement, nil)
        if prepareStatus == SQLITE_CORRUPT || prepareStatus == SQLITE_NOTADB { return true }
        guard prepareStatus == SQLITE_OK else { return false }

        let stepStatus = sqlite3_step(statement)
        if stepStatus == SQLITE_CORRUPT || stepStatus == SQLITE_NOTADB { return true }
        guard stepStatus == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { return false }
        return String(cString: text) != "ok"
    }

    /// Moves the store and its -wal and -shm files to `<name>.broken-<stamp>`, never
    /// deleting. Returns the new path of the main file, or nil when it could not move.
    static func setAside(storeURL: URL, now: Date = Date()) -> URL? {
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        let dir = storeURL.deletingLastPathComponent()
        let name = storeURL.lastPathComponent
        let target = dir.appendingPathComponent("\(name).broken-\(stamp)")
        do {
            try FileManager.default.moveItem(at: storeURL, to: target)
        } catch {
            return nil
        }
        for suffix in ["-wal", "-shm"] {
            try? FileManager.default.moveItem(
                at: dir.appendingPathComponent(name + suffix),
                to: dir.appendingPathComponent("\(name).broken-\(stamp)\(suffix)")
            )
        }
        return target
    }
}
