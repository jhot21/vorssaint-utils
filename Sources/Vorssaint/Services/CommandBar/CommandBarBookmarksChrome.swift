// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Chrome's own bookmarks, read from its profile files. No permission is
/// asked for: `~/Library/Application Support/Google/Chrome` is an ordinary,
/// unprotected folder.
final class CommandBarBookmarksChrome {
    private(set) var cachedBookmarks: [CommandBarBookmarksChromeSupport.ParsedBookmark] = []
    private var lastSignature: String?
    private let rootDirectory: URL

    /// `rootDirectory` defaults to Chrome's real profile folder; a test
    /// passes a temp directory with hand-written fixture files instead.
    init(rootDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome")) {
        self.rootDirectory = rootDirectory
    }

    /// Re-parses only when enabled and something watched has changed since
    /// the last call. Safe to call on every bar open.
    func refreshIfNeeded(enabled: Bool) {
        guard enabled else {
            if lastSignature != nil || !cachedBookmarks.isEmpty {
                lastSignature = nil
                cachedBookmarks = []
            }
            return
        }
        let localStatePath = rootDirectory.appendingPathComponent("Local State").path
        guard let profileDirectory = resolveProfileDirectory(localStatePath: localStatePath) else {
            lastSignature = nil
            cachedBookmarks = []
            return
        }
        let accountPath = profileDirectory.appendingPathComponent("AccountBookmarks").path
        let bookmarksPath = profileDirectory.appendingPathComponent("Bookmarks").path
        let backupPath = profileDirectory.appendingPathComponent("Bookmarks.bak").path
        let signature = CommandBarBookmarksSupport.signature(
            [localStatePath, accountPath, bookmarksPath].compactMap(Self.fileSignature))
        guard signature != lastSignature else { return }
        guard let parsed = parsedBookmarks(accountPath: accountPath, bookmarksPath: bookmarksPath,
                                           backupPath: backupPath) else {
            // A transient parse failure keeps both the previous bookmarks
            // and the previous signature: committing the signature here
            // would make the next `refreshIfNeeded` believe this failed
            // state was already seen, and skip retrying until the file
            // changes again.
            return
        }
        lastSignature = signature
        cachedBookmarks = Array(parsed.prefix(CommandBarBookmarksSupport.maximumBookmarks))
    }

    private func resolveProfileDirectory(localStatePath: String) -> URL? {
        let fm = FileManager.default
        var infoCache: [String: Bool] = [:]
        var lastUsed: String?
        if let data = fm.contents(atPath: localStatePath) {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            if let state = try? decoder.decode(CommandBarBookmarksChromeSupport.ChromeLocalState.self,
                                               from: data) {
                lastUsed = state.profile?.lastUsed
                for name in state.profile?.infoCache?.keys ?? [:].keys {
                    infoCache[name] = Self.hasBookmarksFile(in: rootDirectory.appendingPathComponent(name))
                }
            }
        }
        if infoCache.isEmpty {
            // Local State missing or unparseable: scan the directory itself,
            // Chrome's own fallback path.
            let children = (try? fm.contentsOfDirectory(atPath: rootDirectory.path)) ?? []
            for name in children {
                var isDirectory: ObjCBool = false
                guard fm.fileExists(atPath: rootDirectory.appendingPathComponent(name).path,
                                    isDirectory: &isDirectory), isDirectory.boolValue else { continue }
                infoCache[name] = Self.hasBookmarksFile(in: rootDirectory.appendingPathComponent(name))
            }
        }
        guard let chosen = CommandBarBookmarksChromeSupport.defaultProfileDirectory(
            infoCache: infoCache, lastUsed: lastUsed) else { return nil }
        return rootDirectory.appendingPathComponent(chosen)
    }

    private static func hasBookmarksFile(in directory: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: directory.appendingPathComponent("Bookmarks").path)
            || fm.fileExists(atPath: directory.appendingPathComponent("AccountBookmarks").path)
    }

    /// Prefers `AccountBookmarks` (present and non-empty) over `Bookmarks`,
    /// and `Bookmarks.bak` as a last resort if the primary file fails to
    /// parse — Chrome's own atomic-write fallback file.
    /// `nil` means every file failed to parse — a transient failure the
    /// caller keeps the previous cache (and signature) across, rather than
    /// blanking either.
    private func parsedBookmarks(accountPath: String, bookmarksPath: String,
                                 backupPath: String) -> [CommandBarBookmarksChromeSupport.ParsedBookmark]? {
        // AccountBookmarks is only preferred when present AND non-empty.
        if let parsed = Self.parseFile(at: accountPath), !parsed.isEmpty {
            return parsed
        }
        // Bookmarks is the primary file. If it parses at all — empty or
        // not — that result is final and correct; do NOT fall through to
        // the backup just because it's empty. Falling through here would
        // return stale data from Bookmarks.bak, which is exactly the case
        // Chrome's atomic-write mechanism can leave behind.
        if let parsed = Self.parseFile(at: bookmarksPath) {
            return parsed
        }
        // Bookmarks itself failed to parse (missing or corrupt): fall back
        // to Bookmarks.bak, Chrome's own atomic-write backup file.
        return Self.parseFile(at: backupPath)
    }

    private static func parseFile(at path: String) -> [CommandBarBookmarksChromeSupport.ParsedBookmark]? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let root = try? decoder.decode(CommandBarBookmarksChromeSupport.ChromeBookmarksRoot.self,
                                             from: data) else { return nil }
        return CommandBarBookmarksChromeSupport.flattenedBookmarks(from: root)
    }

    private static func fileSignature(_ path: String) -> CommandBarBookmarksSupport.FileSignature? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? Int,
              let modified = attributes[.modificationDate] as? Date
        else { return nil }
        return .init(path: path, size: size, modified: modified)
    }
}
