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

    init(plistPath: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Safari/Bookmarks.plist")) {
        self.plistPath = plistPath
    }

    func refreshIfNeeded(enabled: Bool, fullDiskAccess: Bool) {
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
        // A transient parse failure keeps both the previous bookmarks and
        // the previous signature: committing the signature here would make
        // the next `refreshIfNeeded` believe this failed state was already
        // seen, and skip retrying until the file changes again.
        guard let parsed = Self.parse(at: plistPath) else { return }
        lastSignature = signature
        cachedBookmarks = Array(parsed.prefix(CommandBarBookmarksSupport.maximumBookmarks))
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
