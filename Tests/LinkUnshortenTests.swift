// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum LinkUnshortenTests {
    private static func u(_ text: String) -> URL { URL(string: text)! }

    static func run(_ suite: TestSuite) {
        runChipAndKeys(suite)
        runShortenerHosts(suite)
        runTransformSplit(suite)
        runChain(suite)
        runFetcher(suite)
        runPipeline(suite)
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

    private final class ScriptedFetcher: HopFetching {
        let respond: (URL, String) -> HopResponse?
        private(set) var calls: [String] = []
        private(set) var cancelled = false
        init(_ respond: @escaping (URL, String) -> HopResponse?) { self.respond = respond }
        func fetch(_ url: URL, method: String, completion: @escaping (HopResponse) -> Void) {
            calls.append("\(method) \(url.absoluteString)")
            guard let response = respond(url, method) else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.cancelled else { return }
                completion(response)
            }
        }
        func cancel() { cancelled = true }
    }

    private static func resolve(_ link: String, rules: ShortenerRules = .none, budget: TimeInterval = 2,
                                _ respond: @escaping (URL, String) -> HopResponse?)
        -> (outcome: UnshortenOutcome?, fetcher: ScriptedFetcher, completions: Int) {
        let fetcher = ScriptedFetcher(respond)
        let service = LinkUnshortener(budget: budget) { fetcher }
        var outcome: UnshortenOutcome?
        var completions = 0
        service.resolve(u(link), shorteners: rules) { outcome = $0; completions += 1 }
        LinkRouterTestSupport.spin(timeout: 3) { outcome != nil }
        LinkRouterTestSupport.spin(timeout: 0.15) { false }
        return (outcome, fetcher, completions)
    }

    private static func runChain(_ suite: TestSuite) {
        let go: (URL, String) -> HopResponse? = { url, _ in
            url.host == "bit.ly" ? .redirect(u("https://example.org/page")) : .failed
        }
        let single = resolve("https://bit.ly/a", go)
        suite.expect(single.outcome == .resolved(u("https://example.org/page"))
                        && single.fetcher.calls == ["HEAD https://bit.ly/a"] && single.fetcher.cancelled,
                     "a HEAD redirect to an ordinary host resolves in one request, and the destination is never fetched")

        let chain = resolve("https://bit.ly/a") { url, _ in
            switch url.host {
            case "bit.ly": return .redirect(u("https://tinyurl.com/b"))
            case "tinyurl.com": return .redirect(u("https://example.org/final"))
            default: return .failed
            }
        }
        suite.expect(chain.outcome == .resolved(u("https://example.org/final"))
                        && chain.fetcher.calls == ["HEAD https://bit.ly/a", "HEAD https://tinyurl.com/b"],
                     "a chain of shorteners is followed hop by hop and stops at the first ordinary host")

        let retry = resolve("https://bit.ly/a") { url, method in
            method == "HEAD" ? .noRedirect : .redirect(u("https://example.org/p"))
        }
        suite.expect(retry.outcome == .resolved(u("https://example.org/p"))
                        && retry.fetcher.calls == ["HEAD https://bit.ly/a", "GET https://bit.ly/a"],
                     "a HEAD that does not redirect is retried once as GET")

        let none = resolve("https://bit.ly/a") { _, _ in .noRedirect }
        suite.expect(none.outcome == .noRedirect && none.fetcher.calls.count == 2,
                     "a GET that does not redirect reports noRedirect")

        let stalled = resolve("https://bit.ly/a") { url, _ in
            url.host == "bit.ly" ? .redirect(u("https://tinyurl.com/b")) : .noRedirect
        }
        suite.expect(stalled.outcome == .noRedirect,
                     "a shortener that stops redirecting mid-chain is noRedirect, never a resolved short link")

        let custom = ShortenerRules(added: [ShortenerEntry(site: "*.s.test")], disabled: [])
        let endless = resolve("https://h0.s.test/x", rules: custom) { url, _ in
            let next = (Int(url.host!.dropFirst().prefix(while: \.isNumber)) ?? 0) + 1
            return .redirect(u("https://h\(next).s.test/x"))
        }
        suite.expect(endless.outcome == .failed(.tooManyHops) && endless.fetcher.calls.count == LinkUnshortener.maxHops,
                     "a chain that stays on shorteners stops at the hop cap")

        let loop = resolve("https://bit.ly/a") { url, _ in
            url.host == "bit.ly" ? .redirect(u("https://tinyurl.com/b")) : .redirect(u("https://bit.ly/a"))
        }
        suite.expect(loop.outcome == .failed(.loop), "a redirect loop is detected")

        let deepLink = resolve("https://bit.ly/a") { _, _ in .redirect(u("myapp://open")) }
        suite.expect(deepLink.outcome == .failed(.notWeb),
                     "a redirect to a non-web scheme fails and is never followed")

        let broken = resolve("https://bit.ly/a") { _, _ in .failed }
        suite.expect(broken.outcome == .failed(.network), "a failed request reports a network failure")

        let slow = resolve("https://bit.ly/a", budget: 0.1) { _, _ in nil }
        suite.expect(slow.outcome == .failed(.timedOut) && slow.fetcher.cancelled && slow.completions == 1,
                     "the total budget ends a lookup that never answers, cancels it, and completes once")

        // Cache: successes are remembered for the app run, failures are not.
        var made = 0
        let service = LinkUnshortener(budget: 2) {
            made += 1
            return ScriptedFetcher(go)
        }
        for _ in 0..<2 {
            var outcome: UnshortenOutcome?
            service.resolve(u("https://bit.ly/a"), shorteners: .none) { outcome = $0 }
            LinkRouterTestSupport.spin(timeout: 3) { outcome != nil }
            suite.expect(outcome == .resolved(u("https://example.org/page")), "the cached lookup still resolves")
        }
        suite.expect(made == 1, "a resolved short link is looked up once per app run")
        made = 0
        let failing = LinkUnshortener(budget: 2) { made += 1; return ScriptedFetcher { _, _ in .failed } }
        for _ in 0..<2 {
            var outcome: UnshortenOutcome?
            failing.resolve(u("https://bit.ly/a"), shorteners: .none) { outcome = $0 }
            LinkRouterTestSupport.spin(timeout: 3) { outcome != nil }
        }
        suite.expect(made == 2, "a failed lookup is not cached")
    }

    private static func runFetcher(_ suite: TestSuite) {
        let config = URLSessionHopFetcher.makeConfiguration()
        suite.expect(!config.httpShouldSetCookies && config.httpCookieStorage == nil && config.urlCache == nil
                        && config.httpCookieAcceptPolicy == .never,
                     "the lookup session keeps no cookies and no cache")
        let request = URLSessionHopFetcher.makeRequest(for: u("https://bit.ly/a"), method: "HEAD")
        suite.expect(request.httpMethod == "HEAD" && request.value(forHTTPHeaderField: "Referer") == nil
                        && request.value(forHTTPHeaderField: "Cookie") == nil
                        && request.value(forHTTPHeaderField: "User-Agent") == URLSessionHopFetcher.userAgent
                        && !request.httpShouldHandleCookies,
                     "the request is a HEAD with no Referer, no cookies and the fixed user agent")

        func response(_ status: Int, location: String? = nil) -> HopResponse {
            let fields = location.map { ["Location": $0] } ?? [:]
            let http = HTTPURLResponse(url: u("https://bit.ly/a"), statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: fields)!
            return URLSessionHopFetcher.hopResponse(for: http)
        }
        suite.expect(response(301, location: "https://example.org/p") == .redirect(u("https://example.org/p")),
                     "an absolute Location is the redirect target")
        suite.expect(response(302, location: "/next") == .redirect(u("https://bit.ly/next")),
                     "a relative Location resolves against the current hop")
        suite.expect(response(307, location: "//example.org/p") == .redirect(u("https://example.org/p")),
                     "a protocol-relative Location resolves against the current hop's scheme")
        suite.expect(response(301) == .noRedirect && response(200) == .noRedirect
                        && response(405) == .noRedirect && response(304, location: "https://x.test/") == .noRedirect,
                     "no Location, a 2xx, 405 and 304 are all noRedirect")
        suite.expect(URLSessionHopFetcher.hopResponse(for: URLResponse(url: u("https://bit.ly/a"), mimeType: nil,
                                                                       expectedContentLength: 0,
                                                                       textEncodingName: nil)) == .failed,
                     "a non-HTTP response is a failure")

        // The redirect is declined: the 3xx response itself is what is delivered.
        let fetcher = URLSessionHopFetcher()
        let session = URLSession(configuration: URLSessionHopFetcher.makeConfiguration())
        var next: URLRequest? = URLRequest(url: u("https://example.org/"))
        var called = false
        fetcher.urlSession(session, task: session.dataTask(with: u("https://bit.ly/a")),
                           willPerformHTTPRedirection: HTTPURLResponse(url: u("https://bit.ly/a"), statusCode: 301,
                                                                       httpVersion: nil, headerFields: nil)!,
                           newRequest: URLRequest(url: u("https://example.org/"))) { replacement in
            next = replacement
            called = true
        }
        suite.expect(called && next == nil, "a redirect is never followed")
        session.invalidateAndCancel()
    }

    private final class CannedUnshortener: LinkUnshortening {
        let outcome: UnshortenOutcome
        private(set) var requested: [URL] = []
        init(_ outcome: UnshortenOutcome) { self.outcome = outcome }
        func resolve(_ url: URL, shorteners: ShortenerRules, completion: @escaping (UnshortenOutcome) -> Void) {
            requested.append(url)
            DispatchQueue.main.async { [outcome] in completion(outcome) }
        }
    }

    private static func runPipeline(_ suite: TestSuite) {
        let settings = TransformSettings()
        func pipeline(_ link: String, _ chips: TransformChips, _ unshortener: LinkUnshortening?) -> PipelineOutcome {
            var outcome: PipelineOutcome?
            LinkPipeline.run(u(link), chips: chips, settings: settings, unshortener: unshortener) { outcome = $0 }
            LinkRouterTestSupport.spin(timeout: 3) { outcome != nil }
            return outcome!
        }

        // Clean sees the unshortened destination.
        let canned = CannedUnshortener(.resolved(u("https://example.org/p?id=1&utm_source=x")))
        let both = pipeline("https://bit.ly/a", [.unshorten, .clean], canned)
        suite.expect(both.result.url == u("https://example.org/p?id=1")
                        && both.result.unshortenedFrom == u("https://bit.ly/a")
                        && both.result.beforeClean == u("https://example.org/p?id=1&utm_source=x")
                        && both.result.removedParameters == ["utm_source"]
                        && both.result.applied == [.unshorten, .clean] && both.unshorten == .resolved,
                     "Clean runs on the unshortened destination and the result remembers the short link")

        // A wrapper whose destination is a shortener: Extract first, then Unshorten.
        let wrapped = CannedUnshortener(.resolved(u("https://example.org/p")))
        let extracted = pipeline("https://l.facebook.com/l.php?u=https%3A%2F%2Fbit.ly%2Fabc", [.extract, .unshorten], wrapped)
        suite.expect(wrapped.requested == [u("https://bit.ly/abc")]
                        && extracted.result.extractedFrom != nil && extracted.result.unshortenedFrom == u("https://bit.ly/abc"),
                     "the shortener found by Extract is the one looked up")

        // Failure leaves the short link, and Clean still runs on it.
        let failed = pipeline("https://bit.ly/a?utm_source=x", [.unshorten, .clean], CannedUnshortener(.failed(.timedOut)))
        suite.expect(failed.result.url == u("https://bit.ly/a") && failed.result.unshortenedFrom == nil
                        && failed.unshorten == .failed && failed.result.applied == [.clean],
                     "a failed lookup keeps the short link and the other selected chips still apply")
        let still = pipeline("https://bit.ly/a", [.unshorten], CannedUnshortener(.noRedirect))
        suite.expect(still.unshorten == .noRedirect && still.result.url == u("https://bit.ly/a"),
                     "a short link that does not redirect is reported and left alone")

        // No lookup unless it is selected, offered by the link, and possible.
        let idle = CannedUnshortener(.resolved(u("https://example.org/")))
        _ = pipeline("https://bit.ly/a", [.clean], idle)
        _ = pipeline("https://example.org/a", [.unshorten], idle)
        suite.expect(idle.requested.isEmpty, "an unselected chip or a non-shortener never contacts anything")
        suite.expect(pipeline("https://bit.ly/a", [.unshorten], nil).unshorten == .notRun,
                     "without an unshortener the step is simply not run")

        // The shared predicate.
        suite.expect(LinkPipeline.needsLookup(u("https://bit.ly/a"), chips: [.unshorten], settings: settings)
                        && !LinkPipeline.needsLookup(u("https://bit.ly/a"), chips: [.clean], settings: settings)
                        && !LinkPipeline.needsLookup(u("https://example.org/a"), chips: [.unshorten], settings: settings),
                     "a lookup is needed only when the chip is on and the link is a listed shortener")

        // Preview.
        var unshortened = TransformResult(url: u("https://example.org/p"), beforeClean: u("https://example.org/p"))
        unshortened.unshortenedFrom = u("https://bit.ly/a")
        let segments = LinkURLPreview.segments(mode: .full, result: unshortened, rewritten: nil)
        suite.expect(segments.contains(URLSegment(text: "example.org", style: .changed)),
                     "the preview highlights the host of an unshortened link")
    }
}
