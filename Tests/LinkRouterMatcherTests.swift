// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum LinkRouterMatcherTests {
    static func run(_ suite: TestSuite) {
        runGlob(suite)
        runRules(suite)
        runRegexEvaluator(suite)
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

    /// Completes synchronously with a canned outcome per pattern.
    private final class FakeRegex: RegexEvaluating {
        var outcomes: [String: RegexOutcome] = [:]
        private(set) var evaluated: [String] = []
        func evaluate(pattern: String, in text: String, completion: @escaping (RegexOutcome) -> Void) {
            evaluated.append(pattern)
            completion(outcomes[pattern] ?? .noMatch)
        }
    }

    private static func match(_ url: String, source: String? = nil, _ rules: [RoutingRule],
                              _ regex: FakeRegex = FakeRegex()) -> RuleMatchResult {
        var result: RuleMatchResult?
        RuleMatcher.firstMatch(url: URL(string: url)!, sourceApp: source, rules: rules,
                               evaluator: regex) { result = $0 }
        return result ?? RuleMatchResult(rule: nil, failures: [])
    }

    private static func runRules(_ suite: TestSuite) {
        let work = RoutingRule(pattern: "*.company.com", browserBundleID: "com.work")
        let docs = RoutingRule(pattern: "docs.google.com/*", browserBundleID: "com.docs")
        let all = RoutingRule(pattern: "*", browserBundleID: "com.catchall")

        suite.expect(match("https://a.company.com/x", [work, docs]).rule?.id == work.id,
                     "a matching glob rule is returned")
        suite.expect(match("https://other.com", [work, docs]).rule == nil,
                     "no rule matches an unrelated URL")
        suite.expect(match("https://a.company.com/x", [all, work]).rule?.id == all.id,
                     "the first matching rule in list order wins")

        var disabled = work
        disabled.isEnabled = false
        suite.expect(match("https://a.company.com", [disabled]).rule == nil,
                     "disabled rules never match")

        let slack = RoutingRule(pattern: "github.com", browserBundleID: "com.slack",
                                sourceAppBundleID: "com.tinyspeck.slackmacgap")
        suite.expect(match("https://github.com", source: "com.tinyspeck.slackmacgap", [slack]).rule?.id == slack.id,
                     "a source-app rule matches its sender")
        suite.expect(match("https://github.com", source: "com.apple.mail", [slack]).rule == nil,
                     "a source-app rule does not match another sender")
        suite.expect(match("https://github.com", source: nil, [slack]).rule == nil,
                     "a source-app rule does not match when the sender is unknown")

        suite.expect(match("mailto:a@b.c", [all]).rule == nil,
                     "non-web URLs never match a rule")

        // Regex rules go through the evaluator, in list order.
        let regex = FakeRegex()
        regex.outcomes["^https://x\\.test/.*$"] = .match
        let rx = RoutingRule(pattern: "^https://x\\.test/.*$", kind: .regex, browserBundleID: "com.rx")
        suite.expect(match("https://x.test/a", [work, rx], regex).rule?.id == rx.id
                        && regex.evaluated == ["^https://x\\.test/.*$"],
                     "a regex rule matches through the evaluator")
        suite.expect(match("https://x.test/a", [rx, work]).rule == nil
                        && match("https://a.company.com", [rx, work]).rule?.id == work.id,
                     "a regex that does not match falls through to later rules")

        // Failures are reported and never block later rules.
        let slow = RoutingRule(pattern: "(a+)+$", kind: .regex, browserBundleID: "com.slow")
        let bad = RoutingRule(pattern: "([", kind: .regex, browserBundleID: "com.bad")
        let failing = FakeRegex()
        failing.outcomes["(a+)+$"] = .timedOut
        failing.outcomes["(["] = .invalid
        let outcome = match("https://a.company.com", [slow, bad, work], failing)
        suite.expect(outcome.rule?.id == work.id
                        && outcome.failures == [RuleFailure(id: slow.id, flag: .tooSlow),
                                                RuleFailure(id: bad.id, flag: .invalidRegex)],
                     "a timed-out or invalid regex is reported and routing continues")

        // Length caps: an over-long pattern is invalid; over-long text just skips the regex rule.
        let long = RoutingRule(pattern: String(repeating: "a", count: RuleMatcher.maxRegexPatternLength + 1),
                               kind: .regex, browserBundleID: "com.long")
        let longResult = match("https://a.company.com", [long, work])
        suite.expect(longResult.failures == [RuleFailure(id: long.id, flag: .invalidRegex)]
                        && longResult.rule?.id == work.id,
                     "an over-long regex pattern is flagged invalid without being evaluated")
        let longURL = "https://a.company.com/" + String(repeating: "p", count: RuleMatcher.maxRegexTextLength)
        let skipped = FakeRegex()
        suite.expect(match(longURL, [rx, work], skipped).rule?.id == work.id && skipped.evaluated.isEmpty,
                     "an over-long URL skips regex rules instead of evaluating them")

        // Codable: old JSON without `flag` still decodes.
        let legacy = #"{"id":"8D6B1B0E-7C9B-4C75-9D0B-0F6E1B6A1E11","pattern":"a.com","kind":"glob","browserBundleID":"b","isEnabled":true}"#
        let decoded = try? JSONDecoder().decode(RoutingRule.self, from: Data(legacy.utf8))
        suite.expect(decoded?.pattern == "a.com" && decoded?.flag == nil && decoded?.sourceAppBundleID == nil,
                     "a rule saved without optional fields decodes")
    }

    /// Runs the main run loop until `done` or a timeout, so main-queue
    /// completions can be observed from a synchronous test.
    private static func spin(timeout: TimeInterval = 5, until done: () -> Bool) {
        let end = Date().addingTimeInterval(timeout)
        while !done() && Date() < end { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
    }

    private static func runRegexEvaluator(_ suite: TestSuite) {
        func evaluate(_ evaluator: RegexEvaluator, _ pattern: String, _ text: String) -> RegexOutcome? {
            var outcome: RegexOutcome?
            evaluator.evaluate(pattern: pattern, in: text) { outcome = $0 }
            spin { outcome != nil }
            return outcome
        }
        let evaluator = RegexEvaluator(deadline: 0.25)
        suite.expect(evaluate(evaluator, "^https://x\\.test/", "https://x.test/a") == .match,
                     "the real evaluator reports a match")
        suite.expect(evaluate(evaluator, "^https://x\\.test/", "https://y.test/a") == .noMatch,
                     "the real evaluator reports no match")
        suite.expect(evaluate(evaluator, "HTTPS://X\\.TEST", "https://x.test/a") == .match,
                     "regex matching is case-insensitive")
        suite.expect(evaluate(evaluator, "([", "https://x.test") == .invalid,
                     "an unparsable expression is invalid")
        let quick = RegexEvaluator(deadline: 0.05)
        let started = Date()
        let slow = evaluate(quick, "(a+)+$", String(repeating: "a", count: 34) + "b")
        suite.expect(slow == .timedOut && Date().timeIntervalSince(started) < 2,
                     "a catastrophic expression is reported as timed out near the deadline, not waited for")
    }
}
