// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum LinkRouterCoreTests {
    private final class FakeEnv: LinkRouterEnvironment {
        var isFeatureOn = true
        var rules: [RoutingRule] = []
        var visibleBrowsers = [BrowserInfo(bundleID: "com.apple.Safari", name: "Safari"),
                               BrowserInfo(bundleID: "org.mozilla.firefox", name: "Firefox")]
        var previousDefaultBundleID: String? = "org.mozilla.firefox"
        var isScreenLocked = false
        var installed: Set<String> = ["com.apple.Safari", "org.mozilla.firefox", "com.work"]
        var events: [String] = []
        func isInstalled(bundleID: String) -> Bool { installed.contains(bundleID) }
        func open(_ url: URL, inBundleID bundleID: String) { events.append("open:\(url.absoluteString)@\(bundleID)") }
        func openNonWeb(_ url: URL) { events.append("nonweb:\(url.absoluteString)") }
        func noBrowserAvailable(for url: URL) { events.append("none:\(url.absoluteString)") }
        func showPicker(for url: URL, waiting: Int) { events.append("picker:\(url.absoluteString)/\(waiting)") }
        func hidePicker() { events.append("hide") }
        func addRule(_ rule: RoutingRule) { rules.append(rule); events.append("rule:\(rule.pattern)@\(rule.browserBundleID)") }
        func flagRule(id: UUID, flag: RoutingRule.Flag) { events.append("flag:\(flag.rawValue)") }
        var transformPrefs = LinkTransformPrefs(defaultChips: [], settings: TransformSettings(), rewrites: [])
        func flagRewrite(id: UUID, flag: RoutingRule.Flag) { events.append("flagRewrite:\(flag.rawValue)") }
    }

    private final class DeferredReplacer: RegexReplacing {
        var pending: [(RegexReplaceOutcome) -> Void] = []
        func replace(pattern: String, in text: String, template: String,
                     completion: @escaping (RegexReplaceOutcome) -> Void) { pending.append(completion) }
        func complete(_ outcome: RegexReplaceOutcome) { let p = pending; pending = []; p.forEach { $0(outcome) } }
    }

    private final class NeverRegex: RegexEvaluating {
        var outcome: RegexOutcome = .noMatch
        func evaluate(pattern: String, in text: String, completion: @escaping (RegexOutcome) -> Void) { completion(outcome) }
    }

    private final class DeferredRegex: RegexEvaluating {
        var pending: [(RegexOutcome) -> Void] = []
        func evaluate(pattern: String, in text: String, completion: @escaping (RegexOutcome) -> Void) { pending.append(completion) }
        func complete(_ outcome: RegexOutcome) { let p = pending; pending = []; p.forEach { $0(outcome) } }
    }

    private static func make(_ configure: (FakeEnv) -> Void = { _ in }) -> (FakeEnv, LinkRouterCore, NeverRegex) {
        let env = FakeEnv()
        configure(env)
        let regex = NeverRegex()
        let core = LinkRouterCore(environment: env, evaluator: regex, selfBundleID: "me")
        core.setReady()
        env.events = []
        return (env, core, regex)
    }

    private static func req(_ s: String, from sender: String? = nil) -> LinkRequest {
        LinkRequest(urls: [URL(string: s)!], senderBundleID: sender)
    }

    static func run(_ suite: TestSuite) {
        // Non-web links never enter the router.
        var (env, core, _) = make()
        core.route(req("mailto:a@b.c"))
        suite.expect(env.events == ["nonweb:mailto:a@b.c"], "non-web links pass straight through")

        // A rule hit opens silently.
        (env, core, _) = make { $0.rules = [RoutingRule(pattern: "*.company.com", browserBundleID: "com.work")] }
        core.route(req("https://a.company.com/x"))
        suite.expect(env.events == ["open:https://a.company.com/x@com.work"], "a rule hit opens in the rule's browser with no picker")

        // No match shows the picker.
        (env, core, _) = make()
        core.route(req("https://example.com"))
        suite.expect(env.events == ["picker:https://example.com/0"], "no rule match shows the picker")

        // A rule whose browser is gone falls back to the picker.
        (env, core, _) = make {
            $0.rules = [RoutingRule(pattern: "example.com", browserBundleID: "com.gone")]
        }
        core.route(req("https://example.com"))
        suite.expect(env.events == ["picker:https://example.com/0"], "a rule for an uninstalled browser shows the picker")

        // A rule pointing at Vorssaint itself is never followed (no self-loop).
        (env, core, _) = make {
            $0.rules = [RoutingRule(pattern: "example.com", browserBundleID: "me")]
            $0.installed.insert("me")
        }
        core.route(req("https://example.com"))
        suite.expect(env.events == ["picker:https://example.com/0"], "a rule targeting Vorssaint itself shows the picker")

        // Feature off goes to the fallback browser, never a bare open.
        (env, core, _) = make { $0.isFeatureOn = false }
        core.route(req("https://example.com"))
        suite.expect(env.events == ["open:https://example.com@org.mozilla.firefox"], "with the feature off links go to the previous default")

        // Cold launch: requests before ready are buffered, then routed in order.
        let coldEnv = FakeEnv()
        let cold = LinkRouterCore(environment: coldEnv, evaluator: NeverRegex(), selfBundleID: "me")
        cold.route(req("https://one.test"))
        cold.route(req("https://two.test"))
        suite.expect(coldEnv.events.isEmpty, "links arriving before the router is ready are not acted on yet")
        cold.setReady()
        suite.expect(coldEnv.events == ["picker:https://one.test/0", "picker:https://one.test/1"],
                     "buffered links are routed once ready, the second waiting behind the first")

        // Picker queue: choose, then the next appears; cancel discards the link.
        (env, core, _) = make()
        core.route(req("https://a.test"))
        core.route(req("https://b.test"))
        suite.expect(env.events == ["picker:https://a.test/0", "picker:https://a.test/1"],
                     "a second link waits behind the open picker and the chip count updates")
        env.events = []
        core.pickerDidChoose(URL(string: "https://a.test")!, bundleID: "com.apple.Safari", saveRule: false)
        suite.expect(env.events == ["open:https://a.test@com.apple.Safari", "picker:https://b.test/0"],
                     "choosing opens the link and brings up the next waiting one")
        env.events = []
        core.pickerDidCancel(URL(string: "https://b.test")!)
        suite.expect(env.events == ["hide"],
                     "cancelling discards the link (nothing is opened) and closes the picker")

        // Cancelling the current link with one waiting shows the waiting one, opening nothing.
        (env, core, _) = make()
        core.route(req("https://a.test"))
        core.route(req("https://b.test"))
        env.events = []
        core.pickerDidCancel(URL(string: "https://a.test")!)
        suite.expect(env.events == ["picker:https://b.test/0"],
                     "cancelling with a link waiting discards the current one and shows the next, with no open")

        // Saving a rule from the picker.
        (env, core, _) = make()
        core.route(req("https://www.Example.com/docs?x=1"))
        env.events = []
        core.pickerDidChoose(URL(string: "https://www.Example.com/docs?x=1")!, bundleID: "com.apple.Safari", saveRule: true)
        suite.expect(env.events == ["open:https://www.Example.com/docs?x=1@com.apple.Safari",
                                    "rule:www.example.com@com.apple.Safari", "hide"],
                     "an option-pick opens the link and saves a host-only rule for the exact host")
        suite.expect(GlobMatcher.matches(pattern: env.rules[0].pattern,
                                         link: LinkCanonical.link(for: URL(string: "https://www.Example.com")!)!),
                     "the rule saved from the picker matches the bare host it came from")

        // Internal links (the repository, coffee or update page) never pop a picker.
        (env, core, _) = make()
        core.route(LinkRequest(urls: [URL(string: "https://github.com/x")!], senderBundleID: nil, allowsPicker: false))
        suite.expect(env.events == ["open:https://github.com/x@org.mozilla.firefox"],
                     "an in-app link with no matching rule opens in the fallback browser, not the picker")
        (env, core, _) = make { $0.rules = [RoutingRule(pattern: "github.com", browserBundleID: "com.work")] }
        core.route(LinkRequest(urls: [URL(string: "https://github.com/x")!], senderBundleID: nil, allowsPicker: false))
        suite.expect(env.events == ["open:https://github.com/x@com.work"],
                     "an in-app link still follows the person's rules")

        // Overflow past the cap goes to the fallback without prompting.
        (env, core, _) = make()
        for i in 0...(LinkRouterCore.queueCap + 1) { core.route(req("https://q\(i).test")) }
        let opened = env.events.filter { $0.hasPrefix("open:") }
        suite.expect(opened == ["open:https://q\(LinkRouterCore.queueCap + 1).test@org.mozilla.firefox"],
                     "links beyond the queue cap skip the picker and use the fallback browser")

        // Locked screen and empty browser list skip the picker.
        (env, core, _) = make { $0.isScreenLocked = true }
        core.route(req("https://example.com"))
        suite.expect(env.events == ["open:https://example.com@org.mozilla.firefox"], "a locked screen skips the picker")
        (env, core, _) = make { $0.visibleBrowsers = [] }
        core.route(req("https://example.com"))
        suite.expect(env.events == ["open:https://example.com@org.mozilla.firefox"], "with no visible browsers the fallback is used")

        // Fallback chain.
        (env, core, _) = make { $0.previousDefaultBundleID = "me"; $0.installed.insert("me") }
        suite.expect(core.fallbackBundleID() == "com.apple.Safari",
                     "a previous default that is Vorssaint itself is skipped for the first visible browser")
        (env, core, _) = make {
            $0.previousDefaultBundleID = "me"
            $0.installed.insert("me")
            $0.visibleBrowsers = [BrowserInfo(bundleID: "me", name: "Me"), BrowserInfo(bundleID: "org.mozilla.firefox", name: "Firefox")]
        }
        suite.expect(core.fallbackBundleID() == "org.mozilla.firefox",
                     "a visible browser that is Vorssaint itself is skipped too")
        (env, core, _) = make { $0.previousDefaultBundleID = nil; $0.visibleBrowsers = [] }
        suite.expect(core.fallbackBundleID() == "com.apple.Safari", "Safari is the last resort when installed")
        (env, core, _) = make { $0.previousDefaultBundleID = nil; $0.visibleBrowsers = []; $0.installed = [] }
        core.route(req("https://example.com"))
        suite.expect(env.events == ["none:https://example.com"],
                     "with no browser at all the link is reported, never bare-opened")

        // Regex failures are flagged.
        let slowSetup = make { $0.rules = [RoutingRule(pattern: "(a+)+$", kind: .regex, browserBundleID: "com.work")] }
        (env, core) = (slowSetup.0, slowSetup.1)
        slowSetup.2.outcome = .timedOut
        core.route(req("https://example.com"))
        suite.expect(env.events == ["flag:tooSlow", "picker:https://example.com/0"],
                     "a slow regex rule is flagged and routing continues to the picker")

        // Stopping drains the picker into the fallback.
        (env, core, _) = make()
        core.route(req("https://a.test"))
        core.route(req("https://b.test"))
        env.events = []
        core.stopAll()
        suite.expect(env.events == ["open:https://a.test@org.mozilla.firefox",
                                    "open:https://b.test@org.mozilla.firefox", "hide"],
                     "stopping the router sends every pending link to the fallback browser")
        env.events = []
        core.route(req("https://c.test"))
        suite.expect(env.events == ["picker:https://c.test/0"], "after stopping, a new link gets a fresh picker")

        // After a cancel, stopping sends only the links still pending to the fallback.
        (env, core, _) = make()
        core.route(req("https://a.test"))
        core.route(req("https://b.test"))
        core.route(req("https://c.test"))
        core.pickerDidCancel(URL(string: "https://a.test")!)
        env.events = []
        core.stopAll()
        suite.expect(env.events == ["open:https://b.test@org.mozilla.firefox",
                                    "open:https://c.test@org.mozilla.firefox", "hide"],
                     "stopping after a cancel sends only the remaining pending links to the fallback, not the discarded one")

        // Late picker callbacks after stopAll do nothing.
        (env, core, _) = make()
        core.route(req("https://a.test"))
        core.stopAll()
        env.events = []
        core.pickerDidCancel(URL(string: "https://a.test")!)
        core.pickerDidChoose(URL(string: "https://a.test")!, bundleID: "com.apple.Safari", saveRule: true)
        suite.expect(env.events.isEmpty, "late picker callbacks after stopping are ignored")

        // A late cancel after a choose neither acts on the link nor skips the next one.
        (env, core, _) = make()
        core.route(req("https://a.test"))
        core.route(req("https://b.test"))
        core.pickerDidChoose(URL(string: "https://a.test")!, bundleID: "com.apple.Safari", saveRule: false)
        env.events = []
        core.pickerDidCancel(URL(string: "https://a.test")!)
        suite.expect(env.events.isEmpty, "a late cancel after a choose does nothing and does not advance")
        core.pickerDidCancel(URL(string: "https://b.test")!)
        suite.expect(env.events == ["hide"],
                     "the next waiting link is still current after the stale cancel, and cancelling it discards it")

        // A late choose after a cancel does nothing.
        (env, core, _) = make()
        core.route(req("https://a.test"))
        core.pickerDidCancel(URL(string: "https://a.test")!)
        env.events = []
        core.pickerDidChoose(URL(string: "https://a.test")!, bundleID: "com.apple.Safari", saveRule: true)
        suite.expect(env.events.isEmpty, "a late choose after a cancel does nothing")

        // In-flight regex completions are reconciled with stopAll and the feature toggle.
        let rx = DeferredRegex()
        let regexRule = RoutingRule(pattern: "a", kind: .regex, browserBundleID: "com.work")
        let asyncEnv = FakeEnv()
        asyncEnv.rules = [regexRule]
        let asyncCore = LinkRouterCore(environment: asyncEnv, evaluator: rx, selfBundleID: "me")
        asyncCore.setReady()
        asyncCore.route(req("https://a.test"))
        asyncCore.stopAll()
        asyncEnv.events = []
        rx.complete(.match)
        suite.expect(asyncEnv.events == ["open:https://a.test@org.mozilla.firefox"],
                     "a regex completing after stopping sends the link to the fallback, no picker, rule not followed")

        asyncCore.route(req("https://b.test"))
        asyncEnv.isFeatureOn = false
        asyncEnv.events = []
        rx.complete(.noMatch)
        suite.expect(asyncEnv.events == ["open:https://b.test@org.mozilla.firefox"],
                     "a regex completing after the feature is turned off uses the fallback")

        asyncEnv.isFeatureOn = true
        asyncCore.route(req("https://c.test"))
        asyncEnv.events = []
        rx.complete(.match)
        suite.expect(asyncEnv.events == ["open:https://c.test@com.work"], "a normal regex completion still follows the rule")
        asyncCore.route(req("https://d.test"))
        asyncEnv.events = []
        rx.complete(.noMatch)
        suite.expect(asyncEnv.events == ["picker:https://d.test/0"], "a normal regex non-match still shows the picker")

        runTransforms(suite)
    }

    private static func runTransforms(_ suite: TestSuite) {
        // Auto-open applies the rule's chips; unset chips use the global default.
        do {
            let env = FakeEnv()
            env.rules = [RoutingRule(pattern: "example.com", browserBundleID: "com.work", chips: [.clean])]
            let core = LinkRouterCore(environment: env, evaluator: NeverRegex(), selfBundleID: "me")
            core.setReady(); env.events = []
            core.route(req("https://example.com/p?id=1&utm_source=x"))
            suite.expect(env.events == ["open:https://example.com/p?id=1@com.work"],
                         "an auto-open rule applies its own chips before opening")
        }
        do {
            let env = FakeEnv()
            env.transformPrefs.defaultChips = [.clean]
            env.rules = [RoutingRule(pattern: "example.com", browserBundleID: "com.work"),
                         RoutingRule(pattern: "other.com", browserBundleID: "com.work", chips: [])]
            let core = LinkRouterCore(environment: env, evaluator: NeverRegex(), selfBundleID: "me")
            core.setReady(); env.events = []
            core.route(req("https://example.com/p?utm_source=x"))
            core.route(req("https://other.com/p?utm_source=x"))
            suite.expect(env.events == ["open:https://example.com/p@com.work", "open:https://other.com/p?utm_source=x@com.work"],
                         "unset rule chips follow the global default and an empty set overrides it")
        }
        // Auto-open with a rewrite: waits for the result, falls back if the router stopped meanwhile.
        do {
            let env = FakeEnv()
            let rewrite = RewriteRule(name: "R", find: "x", replacement: "y", key: "r")
            env.transformPrefs.rewrites = [rewrite]
            env.rules = [RoutingRule(pattern: "example.com", browserBundleID: "com.work", rewriteID: rewrite.id)]
            let replacer = DeferredReplacer()
            let core = LinkRouterCore(environment: env, evaluator: NeverRegex(), selfBundleID: "me", replacer: replacer)
            core.setReady(); env.events = []
            core.route(req("https://example.com/a"))
            suite.expect(env.events.isEmpty, "nothing opens while the rewrite is pending")
            replacer.complete(.replaced("https://front.test/a"))
            suite.expect(env.events == ["open:https://front.test/a@com.work"],
                         "the rewritten link opens in the rule's browser")

            env.events = []
            core.route(req("https://example.com/b"))
            core.stopAll()
            env.events = []
            replacer.complete(.replaced("https://front.test/b"))
            suite.expect(env.events == ["open:https://example.com/b@org.mozilla.firefox"],
                         "a router stopped while a rewrite was pending opens the original link once via the fallback")

            env.events = []
            core.route(req("https://example.com/c"))
            replacer.complete(.timedOut)
            suite.expect(env.events == ["flagRewrite:tooSlow", "open:https://example.com/c@com.work"],
                         "a failed rewrite flags the rule and still opens the unmodified link")

            env.events = []
            core.route(req("https://example.com/d"))
            replacer.complete(.noMatch)
            suite.expect(env.events == ["open:https://example.com/d@com.work"],
                         "a rewrite that changes nothing opens the edited link")
        }
        // Picker choice opens the transformed link; remembering saves the original host.
        do {
            let (env, core, _) = make()
            let wrapper = URL(string: "https://l.facebook.com/l.php?u=https%3A%2F%2Fexample.org%2F")!
            core.route(LinkRequest(urls: [wrapper], senderBundleID: nil))
            core.pickerDidChoose(wrapper, bundleID: "com.apple.Safari", saveRule: true,
                                 opening: URL(string: "https://example.org/")!, chips: [.extract])
            suite.expect(env.events.contains("open:https://example.org/@com.apple.Safari")
                            && env.events.contains("rule:l.facebook.com@com.apple.Safari")
                            && env.rules.first?.chips == [.extract],
                         "the picker opens the final link, saves the rule for the original host, and keeps the chips")
        }
        do {
            let (env, core, _) = make()
            env.transformPrefs.defaultChips = [.clean]
            core.route(req("https://a.test/"))
            core.pickerDidChoose(URL(string: "https://a.test/")!, bundleID: "com.apple.Safari", saveRule: true, chips: [.clean])
            suite.expect(env.rules.first?.chips == nil, "chips equal to the global default are saved as unset")
        }
    }
}
