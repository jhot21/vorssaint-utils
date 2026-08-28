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
    /// Bumped on every call, so a background parse that finishes after a
    /// newer call already started — the source got disabled, or changed
    /// again before the first parse returned — never overwrites a decision
    /// made after it.
    private var refreshGeneration = 0
    private let parseQueue = DispatchQueue(label: "com.vorssaint.commandbar.bookmarks.chrome",
                                           qos: .userInitiated)

    /// `rootDirectory` defaults to Chrome's real profile folder; a test
    /// passes a temp directory with hand-written fixture files instead.
    init(rootDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome")) {
        self.rootDirectory = rootDirectory
    }

    /// Re-parses only when enabled and something watched has changed since
    /// the last call. Safe to call on every bar open: resolving the profile
    /// and checking signatures is cheap and stays synchronous, but the
    /// bookmarks parse itself runs on a background queue, with `completion`
    /// firing on the main queue once fresh results land.
    func refreshIfNeeded(enabled: Bool, completion: @escaping () -> Void = {}) {
        refreshGeneration &+= 1
        let generation = refreshGeneration
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
            [localStatePath, accountPath, bookmarksPath, backupPath].compactMap(Self.fileSignature))
        guard signature != lastSignature else { return }
        parseQueue.async { [weak self] in
            let parsed = Self.parsedBookmarks(accountPath: accountPath, bookmarksPath: bookmarksPath,
                                              backupPath: backupPath)
            DispatchQueue.main.async {
                guard let self, self.refreshGeneration == generation else { return }
                guard let parsed else {
                    // A transient parse failure keeps both the previous
                    // bookmarks and the previous signature: committing the
                    // signature here would make the next `refreshIfNeeded`
                    // believe this failed state was already seen, and skip
                    // retrying until the file changes again.
                    return
                }
                self.lastSignature = signature
                // Filtered before capping, not after: a bookmarklet or other
                // non-offerable URL never becomes a row anyway
                // (CommandBarCatalog's bookmarkEntries filters the same
                // way), so letting one spend a cap slot ahead of a real,
                // openable bookmark would be wrong on a large library.
                self.cachedBookmarks = Array(
                    parsed.filter { CommandBarBookmarksSupport.isOfferableURL($0.url) }
                        .prefix(CommandBarBookmarksSupport.maximumBookmarks))
                completion()
            }
        }
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
    /// blanking either. `static`, and reading no instance state, so it can
    /// run safely on the background parse queue.
    private static func parsedBookmarks(accountPath: String, bookmarksPath: String,
                                        backupPath: String) -> [CommandBarBookmarksChromeSupport.ParsedBookmark]? {
        // AccountBookmarks is only preferred when present AND non-empty.
        if let parsed = parseFile(at: accountPath), !parsed.isEmpty {
            return parsed
        }
        // Bookmarks is the primary file. If it parses at all — empty or
        // not — that result is final and correct; do NOT fall through to
        // the backup just because it's empty. Falling through here would
        // return stale data from Bookmarks.bak, which is exactly the case
        // Chrome's atomic-write mechanism can leave behind.
        if let parsed = parseFile(at: bookmarksPath) {
            return parsed
        }
        // Bookmarks itself failed to parse (missing or corrupt): fall back
        // to Bookmarks.bak, Chrome's own atomic-write backup file.
        return parseFile(at: backupPath)
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
