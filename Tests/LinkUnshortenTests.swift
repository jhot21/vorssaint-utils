// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum LinkUnshortenTests {
    private static func u(_ text: String) -> URL { URL(string: text)! }

    static func run(_ suite: TestSuite) {
        runChipAndKeys(suite)
        runShortenerHosts(suite)
        runTransformSplit(suite)
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

    private static func runShortenerHosts(_ suite: TestSuite) {
        for entry in ShortenerHosts.builtIn {
            let (host, path) = LinkCanonical.splitPattern(entry.site)
            suite.expect(path == nil && !host.contains("*") && host.split(separator: ".").count >= 2,
                         "built-in shortener \(entry.site) is a plain host")
            suite.expect(ShortenerHosts.isShortener(u("https://\(entry.site)/abc"), rules: .none),
                         "built-in shortener \(entry.site) matches its own links")
        }
        suite.expect(Set(ShortenerHosts.builtIn.map(\.token)).count == ShortenerHosts.builtIn.count,
                     "built-in shortener hosts are unique")
        suite.expect(ShortenerHosts.isShortener(u("https://bit.ly/x"), rules: .none)
                        && !ShortenerHosts.isShortener(u("https://example.com/x"), rules: .none),
                     "only listed hosts count as shorteners")
        suite.expect(!ShortenerHosts.isShortener(u("https://bit.ly@evil.test/x"), rules: .none),
                     "userinfo cannot pass another host off as a shortener")
        suite.expect(!ShortenerHosts.isShortener(u("mailto:a@bit.ly"), rules: .none)
                        && !ShortenerHosts.isShortener(u("ftp://bit.ly/x"), rules: .none),
                     "only web links count as shorteners")
        suite.expect(!ShortenerHosts.isShortener(u("https://bit.ly/x"),
                                                 rules: ShortenerRules(added: [], disabled: ["bit.ly"])),
                     "a disabled built-in host is no longer a shortener")
        suite.expect(ShortenerHosts.isShortener(u("https://a.go.test/x"),
                                                rules: ShortenerRules(added: [ShortenerEntry(site: "*.go.test")],
                                                                      disabled: [])),
                     "an added host glob matches")

        func accepted(_ text: String) -> Bool { ShortenerHosts.newEntry(from: text, rules: .none) != nil }
        suite.expect(accepted("short.example") && accepted("*.go.example") && accepted("go.example/x/*"),
                     "plain hosts, subdomain globs and host/path globs are accepted")
        for bad in ["", "   ", "*", "*.*", "*.com", "bit.*", "https://x.example", "a b.example",
                    "localhost", "a@b.example", "BIT.LY", "**.com", "***.com", "**.*.com"] {
            suite.expect(!accepted(bad), "the host '\(bad)' is rejected")
        }
        let existing = ShortenerRules(added: [ShortenerEntry(site: "short.example")], disabled: [])
        suite.expect(ShortenerHosts.newEntry(from: "Short.Example", rules: existing) == nil,
                     "a duplicate of an added host is rejected")
    }

    private static func runTransformSplit(_ suite: TestSuite) {
        let settings = TransformSettings()
        let link = u("https://l.facebook.com/l.php?u=https%3A%2F%2Fexample.org%2Fp%3Futm_source%3Dx")
        let chips: TransformChips = [.extract, .clean]
        let split = LinkTransform.cleaned(LinkTransform.extract(link, chips: chips, settings: settings),
                                          chips: chips, settings: settings)
        suite.expect(split == LinkTransform.apply(link, chips: chips, settings: settings)
                        && split.url == u("https://example.org/p")
                        && split.extractedFrom == link && split.unshortenedFrom == nil,
                     "apply is Extract then Clean, and the split helpers compose to the same result")
        let extracted = LinkTransform.extract(link, chips: chips, settings: settings)
        suite.expect(extracted.url == u("https://example.org/p?utm_source=x")
                        && extracted.beforeClean == extracted.url && extracted.applied == [.extract],
                     "extract alone leaves Clean undone")

        // Availability.
        let short = u("https://bit.ly/abc")
        suite.expect(LinkTransform.available(for: short, selected: [], settings: settings) == [.unshorten],
                     "a listed shortener offers Unshorten")
        suite.expect(LinkTransform.available(for: u("https://example.org/p"), selected: [], settings: settings).isEmpty,
                     "an ordinary link offers nothing")
        let wrapped = u("https://l.facebook.com/l.php?u=https%3A%2F%2Fbit.ly%2Fabc")
        suite.expect(LinkTransform.available(for: wrapped, selected: [], settings: settings) == [.extract],
                     "a wrapper around a shortener does not offer Unshorten until Extract is selected")
        suite.expect(LinkTransform.available(for: wrapped, selected: [.extract], settings: settings)
                        == [.extract, .unshorten],
                     "once Extract is selected, Unshorten is judged on the destination")
        suite.expect(LinkTransform.available(for: short, selected: [.unshorten], settings: settings,
                                             unshortenPending: true) == [.unshorten, .clean],
                     "Clean is offered optimistically while Unshorten is pending")
        suite.expect(LinkTransform.available(for: short, selected: [.unshorten], settings: settings,
                                             resolved: u("https://example.org/p?utm_source=x")) == [.unshorten, .clean],
                     "Clean is judged on the resolved destination")
        suite.expect(LinkTransform.available(for: short, selected: [.unshorten], settings: settings,
                                             resolved: u("https://example.org/p")) == [.unshorten],
                     "a clean resolved destination does not offer Clean")
    }
}
