// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum LinkUnshortenTests {
    private static func u(_ text: String) -> URL { URL(string: text)! }

    static func run(_ suite: TestSuite) {
        runChipAndKeys(suite)
    }

    private static func runChipAndKeys(_ suite: TestSuite) {
        suite.expect(TransformChips.unshorten.rawValue == 4
                        && TransformChips(rawValue: 3) == [.extract, .clean],
                     "unshorten is the third bit and stored Extract/Clean values keep their meaning")
        let map = LinkPickerKeyMap.make(rewrites: [])
        suite.expect(map.chips["e"] == .extract && map.chips["l"] == .clean && map.chips["u"] == .unshorten,
                     "the picker binds Command-U to Unshorten next to E and L")
        suite.expect(!RewriteKeys.isValid("u", among: [], editing: nil),
                     "a rewrite cannot claim the Unshorten key")
        suite.expect(RewriteKeys.suggestion(for: "unshort", among: []) != "u",
                     "a suggested rewrite key is never the Unshorten key")
    }
}
