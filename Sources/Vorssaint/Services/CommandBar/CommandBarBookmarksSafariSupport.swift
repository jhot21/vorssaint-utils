// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Parsing Safari's own `Bookmarks.plist`. Pure: given an already-decoded
/// tree, produces a flat list. Reading the file (behind Full Disk Access)
/// lives in `CommandBarBookmarksSafari`, outside this test harness.
enum CommandBarBookmarksSafariSupport {
    struct ParsedBookmark: Equatable {
        let id: String
        let title: String
        let url: String
        let folder: String
    }

    struct SafariNode: Decodable {
        struct URIDictionary: Decodable {
            let title: String?
        }
        let webBookmarkType: String
        let webBookmarkUUID: String?
        let title: String?
        let children: [SafariNode]?
        let urlString: String?
        let uriDictionary: URIDictionary?

        private enum CodingKeys: String, CodingKey {
            case webBookmarkType = "WebBookmarkType"
            case webBookmarkUUID = "WebBookmarkUUID"
            case title = "Title"
            case children = "Children"
            case urlString = "URLString"
            case uriDictionary = "URIDictionary"
        }
    }

    /// Safari's own names for its fixed roots, matching what the app itself
    /// shows: the bookmarks bar reads as "Favourites", not its internal key.
    private static func friendlyRootName(_ rawTitle: String) -> String {
        switch rawTitle {
        case "BookmarksBar": return "Favourites"
        case "BookmarksMenu": return "Bookmarks Menu"
        case "com.apple.ReadingList": return "Reading List"
        default: return rawTitle
        }
    }

    static func flattenedBookmarks(from root: SafariNode) -> [ParsedBookmark] {
        var results: [ParsedBookmark] = []
        for child in root.children ?? [] {
            walk(child, path: [], into: &results)
        }
        return results
    }

    private static func walk(_ node: SafariNode, path: [String], into results: inout [ParsedBookmark]) {
        if node.webBookmarkType == "WebBookmarkTypeLeaf" {
            guard let uuid = node.webBookmarkUUID, let url = node.urlString else { return }
            let title = node.uriDictionary?.title.flatMap { $0.isEmpty ? nil : $0 } ?? url
            results.append(ParsedBookmark(id: uuid, title: title, url: url,
                                          folder: path.joined(separator: "/")))
            return
        }
        guard node.webBookmarkType == "WebBookmarkTypeList", let children = node.children else { return }
        let ownName = node.title.map(friendlyRootName)
        let nextPath = ownName.map { path + [$0] } ?? path
        for child in children { walk(child, path: nextPath, into: &results) }
    }
}
