// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Parsing Chrome's own `Bookmarks`/`AccountBookmarks` JSON and `Local
/// State` profile registry. Pure: given already-read JSON, produces a flat
/// list. The file reads, the `AccountBookmarks`-over-`Bookmarks` preference,
/// and the directory-scan fallback all live in `CommandBarBookmarksChrome`,
/// which is not part of this test harness.
enum CommandBarBookmarksChromeSupport {
    struct ParsedBookmark: Equatable {
        let id: String
        let title: String
        let url: String
        let folder: String
    }

    struct ChromeBookmarkNode: Decodable {
        let guid: String?
        let name: String
        let type: String
        let url: String?
        let children: [ChromeBookmarkNode]?
    }

    struct ChromeBookmarksRoot: Decodable {
        struct Roots: Decodable {
            let bookmarkBar: ChromeBookmarkNode?
            let other: ChromeBookmarkNode?
            let synced: ChromeBookmarkNode?
        }
        let roots: Roots
    }

    /// Every leaf under `bookmark_bar`, `other` and `synced`, each carrying
    /// the joined titles of the folders above it — including the root's own
    /// name, which is what a person actually sees as "Bookmarks bar" in
    /// Chrome.
    static func flattenedBookmarks(from root: ChromeBookmarksRoot) -> [ParsedBookmark] {
        var results: [ParsedBookmark] = []
        for node in [root.roots.bookmarkBar, root.roots.other, root.roots.synced].compactMap({ $0 }) {
            walk(node, path: [], into: &results)
        }
        return results
    }

    private static func walk(_ node: ChromeBookmarkNode, path: [String],
                             into results: inout [ParsedBookmark]) {
        if node.type == "url", let url = node.url, !node.name.isEmpty {
            results.append(ParsedBookmark(id: node.guid ?? url, title: node.name,
                                          url: url, folder: path.joined(separator: "/")))
            return
        }
        guard node.type == "folder", let children = node.children else { return }
        let nextPath = path + [node.name]
        for child in children { walk(child, path: nextPath, into: &results) }
    }

    struct ChromeLocalState: Decodable {
        struct Profile: Decodable {
            let infoCache: [String: ProfileInfo]?
            let lastUsed: String?
        }
        struct ProfileInfo: Decodable {}
        let profile: Profile?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            profile = try container.decodeIfPresent(Profile.self, forKey: .profile)
        }
        private enum CodingKeys: String, CodingKey { case profile }
    }

    /// Which profile directory to read: the last-used one if it actually has
    /// a bookmarks file, else `Default` if that has one, else the
    /// alphabetically first eligible directory, else nothing to read.
    /// `infoCache` maps a profile's directory name to whether the caller
    /// already found a bookmarks file for it.
    static func defaultProfileDirectory(infoCache: [String: Bool], lastUsed: String?) -> String? {
        if let lastUsed, infoCache[lastUsed] == true { return lastUsed }
        if infoCache["Default"] == true { return "Default" }
        return infoCache.filter { $0.value }.keys.sorted().first
    }
}
