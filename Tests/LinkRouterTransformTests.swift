// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum LinkRouterTransformTests {
    static func run(_ suite: TestSuite) {
        runReplace(suite)
        runWrappers(suite)
        runPipeline(suite)
        runRewrites(suite)
    }

    private static func replace(_ evaluator: RegexEvaluator, _ pattern: String, _ text: String,
                                _ template: String) -> RegexReplaceOutcome? {
        var outcome: RegexReplaceOutcome?
        evaluator.replace(pattern: pattern, in: text, template: template) { outcome = $0 }
        LinkRouterTestSupport.spin { outcome != nil }
        return outcome
    }

    private static func runReplace(_ suite: TestSuite) {
        let evaluator = RegexEvaluator(deadline: 0.25)
        suite.expect(replace(evaluator, #"^https://www\.youtube\.com/watch\?v=([\w-]+).*$"#,
                             "https://www.youtube.com/watch?v=abc_123&t=5",
                             "https://yt.example.test/watch?v=$1")
                        == .replaced("https://yt.example.test/watch?v=abc_123"),
                     "a rewrite substitutes capture groups with $1")
        suite.expect(replace(evaluator, #"^https://x\.test/"#, "https://y.test/", "z") == .noMatch,
                     "a pattern that does not match reports noMatch, not an unchanged replacement")
        suite.expect(replace(evaluator, "([", "https://x.test", "z") == .invalid,
                     "an unparsable pattern is invalid")
        let quick = RegexEvaluator(deadline: 0.05)
        suite.expect(replace(quick, "(a+)+$", String(repeating: "a", count: 34) + "b", "z") == .timedOut,
                     "a catastrophic pattern times out instead of hanging")
        suite.expect(replace(evaluator, "^", "https://x.test",
                             String(repeating: "x", count: RegexEvaluator.maxReplacementLength + 1)) == .invalid,
                     "a replacement longer than the cap is rejected")
    }

    private static func runWrappers(_ suite: TestSuite) {
        let landing = "https://example.org/landing?a=1"
        func wrapped(_ entry: WrapperEntry) -> URL {
            let (hostPattern, pathPattern) = LinkCanonical.splitPattern(entry.site)
            var components = URLComponents()
            components.scheme = "https"
            components.host = hostPattern.replacingOccurrences(of: "*", with: "com")
            components.path = (pathPattern ?? "/").replacingOccurrences(of: "*", with: "x")
            components.queryItems = [URLQueryItem(name: "noise", value: "1"),
                                     URLQueryItem(name: entry.parameter, value: landing)]
            return components.url!
        }
        // Drift guard: every shipped entry must extract from a link built out of itself.
        for entry in RedirectWrappers.builtIn {
            suite.expect(RedirectWrappers.destination(of: wrapped(entry)) == URL(string: landing),
                         "built-in wrapper \(entry.site) extracts its destination")
        }
        suite.expect(Set(RedirectWrappers.builtIn.map(\.token)).count == RedirectWrappers.builtIn.count,
                     "built-in wrapper tokens are unique")

        let google = URL(string: "https://www.google.co.uk/url?sa=t&q=https%3A%2F%2Fexample.org%2Fa%3Fb%3D1&usg=x")!
        suite.expect(RedirectWrappers.destination(of: google) == URL(string: "https://example.org/a?b=1"),
                     "a percent-encoded destination is decoded exactly once")
        let doubleEncoded = URL(string: "https://l.facebook.com/l.php?u=https%253A%252F%252Fexample.org")!
        suite.expect(RedirectWrappers.destination(of: doubleEncoded) == nil,
                     "an over-encoded value is not decoded a second time and so is not a URL")

        for bad in ["javascript:alert(1)", "file:///etc/passwd", "not a url", "", "ftp://example.org/x"] {
            var components = URLComponents(string: "https://l.facebook.com/l.php")!
            components.queryItems = [URLQueryItem(name: "u", value: bad)]
            suite.expect(RedirectWrappers.destination(of: components.url!) == nil,
                         "a non-web destination value is never extracted: \(bad)")
        }
        suite.expect(RedirectWrappers.destination(of: URL(string: "https://example.com/page")!) == nil,
                     "a link with no query and no wrapper is untouched")
        suite.expect(RedirectWrappers.destination(of: URL(string: "mailto:a@b.c")!) == nil,
                     "a non-web link is untouched")

        let unknown = URL(string: "https://unknown.test/go?x=1&to=https%3A%2F%2Fexample.org%2F&y=https%3A%2F%2Fother.test")!
        suite.expect(RedirectWrappers.destination(of: unknown) == nil,
                     "an unknown host is not extracted unless the generic fallback is on")
        suite.expect(RedirectWrappers.destination(of: unknown, genericFallback: true) == URL(string: "https://example.org/"),
                     "the generic fallback takes the first URL-valued parameter in link order")

        let custom = WrapperEntry(site: "unknown.test/go", parameter: "to")
        suite.expect(RedirectWrappers.destination(of: unknown, rules: WrapperRules(added: [custom])) == URL(string: "https://example.org/"),
                     "a user wrapper rule extracts")
        let builtin = RedirectWrappers.builtIn[0]
        suite.expect(RedirectWrappers.destination(of: wrapped(builtin),
                                                  rules: WrapperRules(disabled: [builtin.token])) == nil,
                     "a disabled built-in wrapper no longer extracts")
        suite.expect(WrapperEntry(site: "A.com/X", parameter: "Q").token == "a.com/x|q",
                     "the token is lowercased host+path+parameter")
    }

    private static func runPipeline(_ suite: TestSuite) {
        let settings = TransformSettings()
        let tracked = URL(string: "https://example.com/p?id=7&utm_source=x&fbclid=y")!
        let cleaned = LinkTransform.apply(tracked, chips: [.clean], settings: settings)
        suite.expect(cleaned.url == URL(string: "https://example.com/p?id=7")!
                        && cleaned.applied == [.clean]
                        && cleaned.removedParameters.sorted() == ["fbclid", "utm_source"],
                     "Clean removes trackers and reports what it removed")
        suite.expect(LinkTransform.apply(tracked, chips: [], settings: settings).url == tracked,
                     "no chips leaves the link alone")

        let wrapper = URL(string: "https://l.facebook.com/l.php?u=https%3A%2F%2Fexample.org%2Fa%3Futm_medium%3Dz%26k%3D1")!
        let both = LinkTransform.apply(wrapper, chips: [.extract, .clean], settings: settings)
        suite.expect(both.url == URL(string: "https://example.org/a?k=1")!
                        && both.applied == [.extract, .clean]
                        && both.extractedFrom == wrapper
                        && both.beforeClean == URL(string: "https://example.org/a?utm_medium=z&k=1")!,
                     "Extract runs before Clean, so the destination is the thing that gets cleaned")
        let extractOnly = LinkTransform.apply(wrapper, chips: [.extract], settings: settings)
        suite.expect(extractOnly.url == URL(string: "https://example.org/a?utm_medium=z&k=1")!,
                     "Extract alone leaves the destination's own parameters")
        suite.expect(LinkTransform.apply(URL(string: "https://example.com/")!, chips: [.extract, .clean], settings: settings).applied == [],
                     "chips that change nothing report nothing applied")
        let again = LinkTransform.apply(both.url, chips: [.extract, .clean], settings: settings)
        suite.expect(again.url == both.url && again.applied == [], "applying the pipeline twice changes nothing more")

        suite.expect(LinkTransform.available(for: tracked, selected: [], settings: settings) == [.clean],
                     "Clean is offered on a tracked link and Extract is not")
        suite.expect(LinkTransform.available(for: wrapper, selected: [], settings: settings) == [.extract],
                     "Extract is offered on a wrapper link")
        suite.expect(LinkTransform.available(for: wrapper, selected: [.extract], settings: settings) == [.extract, .clean],
                     "with Extract on, Clean is offered when the destination is tracked")
        suite.expect(LinkTransform.available(for: URL(string: "https://example.com/")!, selected: [], settings: settings).isEmpty,
                     "a plain link offers no chips")
        // Clean must not re-encode the values it keeps.
        let encoded = LinkTransform.apply(URL(string: "https://example.com/p?utm_source=x&k=a%2Bb&u=https%3A%2F%2Fo.test%2F%3Fq%3D1")!,
                                          chips: [.clean], settings: settings)
        suite.expect(encoded.url.absoluteString == "https://example.com/p?k=a%2Bb&u=https%3A%2F%2Fo.test%2F%3Fq%3D1",
                     "Clean leaves the surviving parameters exactly as they were written")
        let onlyTracker = LinkTransform.apply(URL(string: "https://example.com/p?fbclid=y")!, chips: [.clean], settings: settings)
        suite.expect(onlyTracker.url.absoluteString == "https://example.com/p",
                     "removing the last parameter leaves no dangling question mark")
    }

    private final class FakeReplacer: RegexReplacing {
        var next: RegexReplaceOutcome = .noMatch
        var calls: [(pattern: String, text: String, template: String)] = []
        func replace(pattern: String, in text: String, template: String,
                     completion: @escaping (RegexReplaceOutcome) -> Void) {
            calls.append((pattern, text, template))
            completion(next)
        }
    }

    private static func runRewrites(_ suite: TestSuite) {
        let yt = RewriteRule(name: "YouTube to Sealant", site: "*.youtube.com",
                             find: #"^https://www\.youtube\.com/watch\?v=([\w-]+).*$"#,
                             replacement: "https://yt.example.test/watch?v=$1", key: "y")
        let anywhere = RewriteRule(name: "Any", find: "a", replacement: "b", key: "a")
        let off = RewriteRule(name: "Off", find: "a", replacement: "b", key: "o", isEnabled: false)
        var flagged = RewriteRule(name: "Flagged", find: "a", replacement: "b", key: "f")
        flagged.flag = .invalidRegex
        let url = URL(string: "https://www.youtube.com/watch?v=abc")!
        suite.expect(LinkRewrite.applicable([yt, anywhere, off, flagged], to: url).map(\.name) == ["YouTube to Sealant", "Any"],
                     "only enabled, unflagged rules whose site matches are offered")
        suite.expect(LinkRewrite.applicable([yt], to: URL(string: "https://example.com/")!).isEmpty,
                     "a site-scoped rule is hidden on other sites")

        let replacer = FakeReplacer()
        func run(_ outcome: RegexReplaceOutcome, rule: RewriteRule = yt) -> RewriteOutcome? {
            replacer.next = outcome
            var result: RewriteOutcome?
            LinkRewrite.apply(rule, to: url, replacer: replacer) { result = $0 }
            LinkRouterTestSupport.spin { result != nil }
            return result
        }
        suite.expect(run(.replaced("https://yt.example.test/watch?v=abc")) == .rewritten(URL(string: "https://yt.example.test/watch?v=abc")!),
                     "a web result becomes the rewritten link")
        suite.expect(replacer.calls.last?.text == url.absoluteString && replacer.calls.last?.template == yt.replacement,
                     "the regex sees the whole link and the template is passed through")
        suite.expect(run(.noMatch) == .unchanged, "no match leaves the link unchanged")
        suite.expect(run(.invalid) == .failed(.invalid) && run(.timedOut) == .failed(.timedOut),
                     "invalid and timed-out regexes are failures, not rewrites")
        for bad in ["javascript:alert(1)", "file:///etc/hosts", "not a url", "yt.example.test/x", ""] {
            suite.expect(run(.replaced(bad)) == .failed(.notWeb), "a non-web rewrite result is rejected: \(bad)")
        }
        suite.expect(run(.replaced(url.absoluteString)) == .unchanged,
                     "a rewrite that yields the same link counts as unchanged")

        // Keys
        suite.expect(RewriteKeys.isValid("y", among: [], editing: nil)
                        && !RewriteKeys.isValid("e", among: [], editing: nil)
                        && !RewriteKeys.isValid("l", among: [], editing: nil)
                        && !RewriteKeys.isValid("q", among: [], editing: nil)
                        && !RewriteKeys.isValid("", among: [], editing: nil)
                        && !RewriteKeys.isValid("yy", among: [], editing: nil)
                        && !RewriteKeys.isValid("1", among: [], editing: nil)
                        && !RewriteKeys.isValid("Y", among: [], editing: nil),
                     "a key is one unreserved lowercase letter that is not a built-in chip key")
        suite.expect(!RewriteKeys.isValid("y", among: [yt], editing: nil)
                        && RewriteKeys.isValid("y", among: [yt], editing: yt.id),
                     "a key already used by another rewrite is rejected, but a rule keeps its own")
        suite.expect(RewriteKeys.suggestion(for: "YouTube", among: []) == "y"
                        && RewriteKeys.suggestion(for: "YouTube", among: [yt]) == "o",
                     "the suggested key is the first free letter of the name")
        suite.expect(RewriteKeys.suggestion(for: "", among: []) != nil,
                     "an empty name still gets a free letter")

        // Storage
        suite.expect(RewriteStore.decode(RewriteStore.encode([yt])) == [yt]
                        && RewriteStore.decode("not json").isEmpty
                        && RewriteStore.isMalformed("not json") && !RewriteStore.isMalformed("[]"),
                     "rewrite rules round-trip and unreadable text decodes to none")
    }
}
