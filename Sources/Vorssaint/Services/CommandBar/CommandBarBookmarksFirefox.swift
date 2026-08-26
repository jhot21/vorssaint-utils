// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SQLite3

/// Firefox's own bookmarks, read from `places.sqlite`. No permission is
/// asked for: `~/Library/Application Support/Firefox` is an ordinary,
/// unprotected folder.
///
/// `places.sqlite` also holds Firefox's history, so its modification time
/// changes on ordinary browsing, not just on a bookmark edit. `refreshIfNeeded`
/// still checks the file's mtime on every call (a `stat()`, effectively
/// free), but only re-parses — real work — at most once every
/// `minimumReparseInterval`, so opening the bar repeatedly during active
/// browsing does not turn into repeated SQLite reads.
final class CommandBarBookmarksFirefox {
    private(set) var cachedBookmarks: [CommandBarBookmarksFirefoxSupport.ParsedBookmark] = []
    private var lastSignature: String?
    private var lastParseDate: Date?
    private let rootDirectory: URL
    private let minimumReparseInterval: TimeInterval

    init(rootDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Firefox"),
         minimumReparseInterval: TimeInterval = 5) {
        self.rootDirectory = rootDirectory
        self.minimumReparseInterval = minimumReparseInterval
    }

    func refreshIfNeeded(enabled: Bool) {
        guard enabled else {
            if lastSignature != nil || !cachedBookmarks.isEmpty {
                lastSignature = nil
                cachedBookmarks = []
            }
            return
        }
        let profilesIniPath = rootDirectory.appendingPathComponent("profiles.ini").path
        guard let profilesIni = try? String(contentsOfFile: profilesIniPath, encoding: .utf8),
              let profilePath = CommandBarBookmarksFirefoxSupport.defaultProfilePath(profilesIni: profilesIni)
        else {
            lastSignature = nil
            cachedBookmarks = []
            return
        }
        let dbPath = rootDirectory.appendingPathComponent(profilePath)
            .appendingPathComponent("places.sqlite").path
        guard let signatureFile = Self.fileSignature(dbPath) else {
            lastSignature = nil
            cachedBookmarks = []
            return
        }
        let signature = CommandBarBookmarksSupport.signature([signatureFile])
        guard signature != lastSignature else { return }
        if let lastParseDate, Date().timeIntervalSince(lastParseDate) < minimumReparseInterval {
            return
        }
        lastSignature = signature
        lastParseDate = Date()
        cachedBookmarks = Self.readBookmarks(atPath: dbPath) ?? cachedBookmarks
    }

    /// Opens read-only, tolerant of Firefox already holding the file open:
    /// `?immutable=1` skips SQLite's own locking, at the cost of possibly
    /// missing a bookmark added moments ago before Firefox checkpoints its
    /// WAL file — an acceptable tradeoff for a search feature.
    private static func readBookmarks(atPath path: String) -> [CommandBarBookmarksFirefoxSupport.ParsedBookmark]? {
        guard let uri = "file:\(path)?immutable=1".cString(using: .utf8) else { return nil }
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        guard sqlite3_open_v2(uri, &db, flags, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }

        let folderRows = query(db, sql: """
            SELECT id, parent, title, guid FROM moz_bookmarks
            WHERE type = 2 AND fk IS NULL AND title IS NOT NULL AND title <> '';
            """) { statement -> (id: Int, parentId: Int, title: String, guid: String)? in
            let id = Int(sqlite3_column_int(statement, 0))
            let parentId = Int(sqlite3_column_int(statement, 1))
            guard let titlePointer = sqlite3_column_text(statement, 2),
                  let guidPointer = sqlite3_column_text(statement, 3) else { return nil }
            return (id, parentId, String(cString: titlePointer), String(cString: guidPointer))
        }
        let bookmarkRows = query(db, sql: """
            SELECT moz_bookmarks.id, moz_bookmarks.parent, moz_bookmarks.title, moz_places.url
            FROM moz_bookmarks LEFT JOIN moz_places ON moz_bookmarks.fk = moz_places.id
            WHERE moz_bookmarks.type = 1 AND moz_bookmarks.title IS NOT NULL
              AND moz_places.url IS NOT NULL;
            """) { statement -> (id: Int, parentId: Int, title: String, url: String)? in
            let id = Int(sqlite3_column_int(statement, 0))
            let parentId = Int(sqlite3_column_int(statement, 1))
            guard let titlePointer = sqlite3_column_text(statement, 2),
                  let urlPointer = sqlite3_column_text(statement, 3) else { return nil }
            return (id, parentId, String(cString: titlePointer), String(cString: urlPointer))
        }
        let folderPaths = CommandBarBookmarksFirefoxSupport.buildFolderPaths(folderRows: folderRows)
        return CommandBarBookmarksFirefoxSupport.parsedBookmarks(bookmarkRows: bookmarkRows,
                                                                  folderPaths: folderPaths)
    }

    private static func query<T>(_ db: OpaquePointer, sql: String,
                                 row: (OpaquePointer) -> T?) -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return []
        }
        defer { sqlite3_finalize(statement) }
        var results: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let value = row(statement) { results.append(value) }
        }
        return results
    }

    private static func fileSignature(_ path: String) -> CommandBarBookmarksSupport.FileSignature? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? Int,
              let modified = attributes[.modificationDate] as? Date
        else { return nil }
        return .init(path: path, size: size, modified: modified)
    }
}
