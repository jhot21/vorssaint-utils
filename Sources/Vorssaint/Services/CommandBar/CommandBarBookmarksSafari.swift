// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Safari's own bookmarks, read from its plist. Gated on Full Disk Access,
/// same as the uninstaller's deeper scan — `Library/Safari` is already one
/// of `Permissions.fdaGatedDirectories`, so this is a new consumer of an
/// existing permission path, not a new one.
final class CommandBarBookmarksSafari {
    private(set) var cachedBookmarks: [CommandBarBookmarksSafariSupport.ParsedBookmark] = []
    private var lastSignature: String?
    private let plistPath: URL
    /// See the identical property on `CommandBarBookmarksChrome`.
    private var refreshGeneration = 0
    private let parseQueue = DispatchQueue(label: "com.vorssaint.commandbar.bookmarks.safari",
                                           qos: .userInitiated)

    init(plistPath: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Safari/Bookmarks.plist")) {
        self.plistPath = plistPath
    }

    /// Signature check stays synchronous; the plist decode moves to a
    /// background queue — see the identical split on
    /// `CommandBarBookmarksChrome.refreshIfNeeded`.
    func refreshIfNeeded(enabled: Bool, fullDiskAccess: Bool, completion: @escaping () -> Void = {}) {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        guard enabled, fullDiskAccess else {
            if lastSignature != nil || !cachedBookmarks.isEmpty {
                lastSignature = nil
                cachedBookmarks = []
            }
            return
        }
        guard let signatureFile = Self.fileSignature(plistPath.path) else {
            lastSignature = nil
            cachedBookmarks = []
            return
        }
        let signature = CommandBarBookmarksSupport.signature([signatureFile])
        guard signature != lastSignature else { return }
        let plistPath = self.plistPath
        parseQueue.async { [weak self] in
            let parsed = Self.parse(at: plistPath)
            DispatchQueue.main.async {
                guard let self, self.refreshGeneration == generation else { return }
                // A transient parse failure keeps the previous bookmarks and
                // signature — see the identical note in
                // CommandBarBookmarksChrome.refreshIfNeeded.
                guard let parsed else { return }
                self.lastSignature = signature
                // Filtered before capping — see the identical note in
                // CommandBarBookmarksChrome.refreshIfNeeded. allowFileScheme
                // is true here: Safari's Reading List can carry file:// entries.
                self.cachedBookmarks = Array(
                    parsed.filter { CommandBarBookmarksSupport.isOfferableURL($0.url, allowFileScheme: true) }
                        .prefix(CommandBarBookmarksSupport.maximumBookmarks))
                completion()
            }
        }
    }

    private static func parse(at url: URL) -> [CommandBarBookmarksSafariSupport.ParsedBookmark]? {
        guard let data = try? Data(contentsOf: url),
              let root = try? PropertyListDecoder().decode(
                CommandBarBookmarksSafariSupport.SafariNode.self, from: data)
        else { return nil }
        return CommandBarBookmarksSafariSupport.flattenedBookmarks(from: root)
    }

    private static func fileSignature(_ path: String) -> CommandBarBookmarksSupport.FileSignature? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? Int,
              let modified = attributes[.modificationDate] as? Date
        else { return nil }
        return .init(path: path, size: size, modified: modified)
    }
}
