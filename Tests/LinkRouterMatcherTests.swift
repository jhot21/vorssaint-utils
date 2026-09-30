// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum LinkRouterMatcherTests {
    static func run(_ suite: TestSuite) {
        runGlob(suite)
    }

    private static func glob(_ pattern: String, _ url: String) -> Bool {
        guard let link = LinkCanonical.link(for: URL(string: url)!) else { return false }
        return GlobMatcher.matches(pattern: pattern, link: link)
    }

    private static func runGlob(_ suite: TestSuite) {
        // MARK: Canonical form

        suite.expect(LinkCanonical.link(for: URL(string: "https://GitHub.com:443/a/b?x=1#f")!)
                        == CanonicalLink(host: "github.com", path: "/a/b"),
                     "host is lowercased; port, query and fragment are not part of the canonical link")
        suite.expect(LinkCanonical.link(for: URL(string: "https://github.com")!)
                        == CanonicalLink(host: "github.com", path: "/"),
                     "a bare host canonicalizes to the root path")
        suite.expect(LinkCanonical.link(for: URL(string: "https://Example.COM./p")!)?.host == "example.com",
                     "a trailing dot on the host is removed")
        suite.expect(LinkCanonical.link(for: URL(string: "https://user:pw@example.com/p")!)?.host == "example.com",
                     "userinfo is ignored")
        suite.expect(LinkCanonical.link(for: URL(string: "https://m\u{00FC}nchen.de/x")!)?.host == "xn--mnchen-3ya.de",
                     "a Unicode host canonicalizes to punycode")
        suite.expect(LinkCanonical.link(for: URL(string: "mailto:a@b.c")!) == nil
                        && !LinkCanonical.isWeb(URL(string: "mailto:a@b.c")!)
                        && !LinkCanonical.isWeb(URL(string: "zoommtg://x")!)
                        && LinkCanonical.isWeb(URL(string: "HTTP://a.com")!),
                     "only http and https are web links")

        // MARK: Wildcard

        suite.expect(Wildcard.matches(pattern: "a*b*c", text: "axbxbc")
                        && Wildcard.matches(pattern: "a*b*c", text: "abc")
                        && !Wildcard.matches(pattern: "a*b*c", text: "axbxb")
                        && Wildcard.matches(pattern: "*a*", text: "bab")
                        && !Wildcard.matches(pattern: "a*b*c", text: "acb"),
                     "several wildcards backtrack correctly, with no false negatives")
        suite.expect(Wildcard.matches(pattern: "a*c", text: "abc")
                        && Wildcard.matches(pattern: "a*c", text: "ac")
                        && !Wildcard.matches(pattern: "a*c", text: "abd")
                        && Wildcard.matches(pattern: "*", text: "")
                        && Wildcard.matches(pattern: "*x*y*", text: "1x2y3")
                        && !Wildcard.matches(pattern: "abc", text: "abcd"),
                     "wildcard matching is anchored and star matches any run including empty")

        // MARK: Glob semantics (the spec's table)

        suite.expect(glob("github.com", "https://github.com")
                        && glob("github.com", "https://github.com/a/b?x=1"),
                     "a host-only pattern matches any path, including the bare host")
        suite.expect(!glob("github.com", "https://www.github.com"),
                     "a host-only pattern is exact on the host")
        suite.expect(glob("*.company.com", "https://sub.company.com/x"),
                     "a leading wildcard label matches a subdomain")
        suite.expect(!glob("*.company.com", "https://company.com"),
                     "a leading wildcard label does not match the bare domain")
        suite.expect(!glob("*.company.com", "https://company.com.evil.com")
                        && !glob("*.company.com", "https://evil-company.com"),
                     "lookalike hosts never match a wildcard rule")
        suite.expect(glob("a*b*c.test", "https://axbxbc.test") && !glob("a*b*c.test", "https://axbxb.test"),
                     "a host pattern with two wildcards matches through backtracking")
        suite.expect(glob("docs.google.com/*", "https://docs.google.com/document/d/1")
                        && glob("docs.google.com/*", "https://docs.google.com")
                        && !glob("docs.google.com/*", "https://meet.google.com/abc"),
                     "a path pattern matches the host and any path under it, nothing else")
        suite.expect(glob("github.com/myorg/*", "https://github.com/myorg/repo/pulls")
                        && !glob("github.com/myorg/*", "https://github.com/other/repo"),
                     "a path prefix pattern matches only that prefix")
        suite.expect(glob("m\u{00FC}nchen.de", "https://xn--mnchen-3ya.de")
                        && glob("xn--mnchen-3ya.de", "https://m\u{00FC}nchen.de"),
                     "Unicode and punycode spellings of a host match each other")
        suite.expect(glob("GitHub.com", "https://github.com")
                        && !glob("github.com/Docs", "https://github.com/docs"),
                     "host matching ignores case, path matching keeps it")
        suite.expect(glob("https://github.com", "https://github.com/x"),
                     "a typed scheme prefix in a pattern is ignored")
        suite.expect(glob("localhost:3000", "http://localhost:8080/x"),
                     "ports are ignored in matching")
        suite.expect(!glob("", "https://github.com"),
                     "an empty pattern matches nothing")

        // MARK: Round trip (the picker creates exactly this pattern)

        for raw in ["https://github.com", "https://www.Example.com/a?b=1", "http://m\u{00FC}nchen.de/x"] {
            let url = URL(string: raw)!
            let host = LinkCanonical.link(for: url)!.host
            suite.expect(glob(host, raw), "a rule created from \(raw) matches the URL it came from")
        }
    }
}
