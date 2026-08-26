// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Parsing Firefox's `profiles.ini` and turning `moz_bookmarks`/`moz_places`
/// rows (already read by `CommandBarBookmarksFirefox`) into a flat list.
/// Pure: given rows, produces bookmarks. Opening `places.sqlite` and running
/// the SQL live outside this file.
enum CommandBarBookmarksFirefoxSupport {
    struct ParsedBookmark: Equatable {
        let id: String
        let title: String
        let url: String
        let folder: String
    }

    /// The profile `places.sqlite` lives in, resolved the way Firefox itself
    /// resolves it: the `Install*` section's `Default` key, not a
    /// per-profile flag. Falls back to the first profile section found if
    /// there is no `Install*` section at all.
    static func defaultProfilePath(profilesIni: String) -> String? {
        let sections = parseINI(profilesIni)
        if let installSection = sections.first(where: { $0.name.hasPrefix("Install") }),
           let path = installSection.values["Default"], !path.isEmpty {
            return path
        }
        return sections.first(where: { $0.name.hasPrefix("Profile") })?.values["Path"]
    }

    private static func parseINI(_ text: String) -> [(name: String, values: [String: String])] {
        var sections: [(name: String, values: [String: String])] = []
        var currentName: String?
        var currentValues: [String: String] = [:]
        func flush() {
            if let currentName { sections.append((currentName, currentValues)) }
        }
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("["), line.hasSuffix("]") {
                flush()
                currentName = String(line.dropFirst().dropLast())
                currentValues = [:]
            } else if let equals = line.firstIndex(of: "=") {
                let key = String(line[line.startIndex..<equals]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
                currentValues[key] = value
            }
        }
        flush()
        return sections
    }

    /// Firefox's four fixed root folders read as raw guids; every other
    /// folder keeps the title the person gave it.
    static func friendlyRootName(_ rawTitle: String) -> String {
        switch rawTitle {
        case "toolbar": return "Bookmarks Toolbar"
        case "menu": return "Bookmarks Menu"
        case "unfiled": return "Other Bookmarks"
        case "mobile": return "Mobile Bookmarks"
        default: return rawTitle
        }
    }

    /// Every folder's full path, resolved by walking `parentId` up to the
    /// root once per folder rather than recursing a tree — `moz_bookmarks`
    /// hands back a flat table, not nested JSON.
    static func buildFolderPaths(
        folderRows: [(id: Int, parentId: Int, title: String, guid: String)]
    ) -> [Int: String] {
        let byID = Dictionary(uniqueKeysWithValues: folderRows.map { ($0.id, $0) })
        var resolved: [Int: String] = [:]

        func resolve(_ id: Int) -> String {
            if let cached = resolved[id] { return cached }
            guard let row = byID[id] else { return "" }
            let ownName = friendlyRootName(row.title)
            guard let parent = byID[row.parentId], parent.id != row.id else {
                resolved[id] = ownName
                return ownName
            }
            let parentPath = resolve(parent.id)
            let full = parentPath.isEmpty ? ownName : "\(parentPath)/\(ownName)"
            resolved[id] = full
            return full
        }
        for row in folderRows { _ = resolve(row.id) }
        return resolved
    }

    static func parsedBookmarks(
        bookmarkRows: [(id: Int, parentId: Int, title: String, url: String)],
        folderPaths: [Int: String]
    ) -> [ParsedBookmark] {
        bookmarkRows.map { row in
            ParsedBookmark(id: String(row.id), title: row.title, url: row.url,
                           folder: folderPaths[row.parentId] ?? "")
        }
    }
}
