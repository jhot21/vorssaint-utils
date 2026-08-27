// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The rules every browser's bookmark reader shares: which URLs are worth
/// offering, what a row is ranked against, and how a reader decides its
/// cached list is stale. Pure, so these are pinned by tests rather than
/// discovered against one person's browser profile.
enum CommandBarBookmarksSupport {
    /// The most bookmarks any one reader keeps cached. A library with tens
    /// or hundreds of thousands of bookmarks (Raycast's own extension had to
    /// raise its plist parser's ceiling for a 250k-bookmark library) would
    /// otherwise produce that many `CommandBarEntry` values, each holding a
    /// closure, rebuilt on every bar open — the bar's own `index(_:)` is
    /// designed for roughly 10^3 rows, not 10^4-10^5.
    static let maximumBookmarks = 2000

    /// A bookmarklet, a `data:` URL or anything else with no page to open is
    /// filtered out here rather than handed to `NSWorkspace.open` from data
    /// read out of a file this app does not control.
    static func isOfferableURL(_ raw: String, allowFileScheme: Bool = false) -> Bool {
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased() else { return false }
        if scheme == "http" || scheme == "https" { return true }
        return allowFileScheme && scheme == "file"
    }

    /// What a row is ranked against beyond its own title: the domain and the
    /// folder it lives in, both invisible to the fuzzy matcher otherwise.
    static func keywords(title: String, url: String, folder: String) -> String {
        let host = URL(string: url)?.host ?? ""
        return [title, host, folder].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// One file a reader depends on, at the moment it last looked.
    struct FileSignature: Equatable {
        let path: String
        let size: Int
        let modified: Date
    }

    /// A single value that changes if, and only if, any watched file's path,
    /// size or modification time changed. A reader compares this to the
    /// value from its last successful parse to decide whether to re-parse.
    static func signature(_ files: [FileSignature]) -> String {
        files.map { "\($0.path)|\($0.size)|\($0.modified.timeIntervalSince1970)" }
            .joined(separator: "\u{0}")
    }
}
