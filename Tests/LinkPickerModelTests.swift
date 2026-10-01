// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum LinkPickerModelTests {
    private final class DeferredReplacer: RegexReplacing {
        var pending: [(RegexReplaceOutcome) -> Void] = []
        func replace(pattern: String, in text: String, template: String,
                     completion: @escaping (RegexReplaceOutcome) -> Void) { pending.append(completion) }
        func complete(_ outcome: RegexReplaceOutcome) { let p = pending; pending = []; p.forEach { $0(outcome) } }
    }

    private static let safari = BrowserInfo(bundleID: "com.apple.Safari", name: "Safari")
    private static let firefox = BrowserInfo(bundleID: "org.mozilla.firefox", name: "Firefox")

    private static func model(_ link: String, rewrites: [RewriteRule] = [], defaultChips: TransformChips = [],
                              replacer: RegexReplacing = DeferredReplacer()) -> LinkPickerModel {
        let prefs = LinkTransformPrefs(defaultChips: defaultChips, settings: TransformSettings(), rewrites: rewrites)
        return LinkPickerModel(url: URL(string: link)!, browsers: [safari, firefox], prefs: prefs, mode: .full,
                               waiting: 0, replacer: replacer, flagRewrite: { _, _ in })
    }

    static func run(_ suite: TestSuite) {
        let rewrite = RewriteRule(name: "Front-end", site: "*.youtube.com", find: "x", replacement: "y", key: "f")

        // A browser chosen while a rewrite is pending opens once, when the rewrite lands.
        do {
            let replacer = DeferredReplacer()
            let m = model("https://www.youtube.com/watch?v=1", rewrites: [rewrite], replacer: replacer)
            var opened: [String] = []
            m.choose = { _, _, url, _, _ in opened.append(url.absoluteString) }
            m.toggleRewrite(rewrite.id)
            m.commit(safari, remember: false)
            suite.expect(opened.isEmpty, "choosing while a rewrite is pending waits for it")
            // Clicks after the choice must not cancel the pending open.
            m.toggleRewrite(rewrite.id)
            m.toggleChip(.clean)
            replacer.complete(.replaced("https://front.test/watch?v=1"))
            suite.expect(opened == ["https://front.test/watch?v=1"],
                         "the pending open fires once with the rewritten link even after later clicks")
            m.commit(firefox, remember: false)
            suite.expect(opened.count == 1, "a second choice after committing is ignored")
        }
        do {
            let m = model("https://www.youtube.com/watch?v=1", rewrites: [rewrite])
            m.commit(safari, remember: false)
            let before = m.state
            m.toggleChip(.clean)
            m.toggleRewrite(rewrite.id)
            _ = m.activate()
            suite.expect(m.state == before, "once a browser is chosen the chips, rewrites and highlight are frozen")
        }

        // A queued link for the same URL must not rebuild the picker.
        let m = model("https://example.com/a")
        suite.expect(m.matches(URL(string: "https://example.com/a")!) && !m.matches(URL(string: "https://example.com/b")!),
                     "the model recognises a re-presentation of the link it already shows")

        // Rewrite scope follows the link as it will be after Extract and Clean.
        let wrapper = "https://l.facebook.com/l.php?u=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3D1"
        let scoped = model(wrapper, rewrites: [rewrite])
        suite.expect(scoped.state.rewrites.isEmpty,
                     "a rewrite scoped to the destination's site is not offered on the wrapper link")
        scoped.toggleChip(.extract)
        suite.expect(scoped.state.rewrites.map(\.id) == [rewrite.id],
                     "turning Extract on offers the rewrite scoped to the destination's site")
        scoped.toggleRewrite(rewrite.id)
        scoped.toggleChip(.extract)
        suite.expect(scoped.state.rewrites.isEmpty && scoped.state.activeRewrite == nil,
                     "turning Extract off drops an active rewrite that no longer applies")
        let preset = model(wrapper, rewrites: [rewrite], defaultChips: [.extract])
        suite.expect(preset.state.rewrites.map(\.id) == [rewrite.id],
                     "default chips are applied before the rewrites are chosen")
    }
}
