// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum ClipboardLinkTests {
    static func run(_ suite: TestSuite) {
        func url(_ entry: ClipboardHistoryEntry, routerOn: Bool = true) -> String? {
            ClipboardLinkSupport.routableURL(for: entry, routerOn: routerOn)?.absoluteString
        }
        suite.expect(url(ClipboardHistoryEntry(text: "https://example.com/a?b=1")) == "https://example.com/a?b=1",
                     "a copied web address can open in the browser")
        suite.expect(url(ClipboardHistoryEntry(text: "  https://example.com\n")) == "https://example.com",
                     "surrounding whitespace is ignored")
        suite.expect(url(ClipboardHistoryEntry(text: "example.com/page")) == "https://example.com/page",
                     "a bare domain gets https")
        suite.expect(url(ClipboardHistoryEntry(text: "see https://example.com for more")) == nil,
                     "a link inside prose is not offered")
        suite.expect(url(ClipboardHistoryEntry(text: "mailto:a@example.com")) == nil,
                     "non-web schemes are not offered")
        suite.expect(url(ClipboardHistoryEntry(text: "notes.txt")) == nil,
                     "a filename is not offered")
        suite.expect(url(ClipboardHistoryEntry(text: "https://example.com/a\nhttps://example.com/b")) == nil,
                     "multi-line text is not offered")
        suite.expect(url(ClipboardHistoryEntry(text: "https://example.com/" + String(repeating: "a", count: 3000))) == nil,
                     "very long text is not scanned")
        suite.expect(url(ClipboardHistoryEntry(text: "https://example.com"), routerOn: false) == nil,
                     "nothing is offered while the link router is off")
        suite.expect(url(ClipboardHistoryEntry(text: "", kind: .files, filePaths: ["/tmp/https://example.com"])) == nil,
                     "file entries are not offered")
    }
}
