// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum LinkRouterBrowserTests {
    static func run(_ suite: TestSuite) {
        suite.expect(BrowserCatalogSupport.cleanName("Firefox.app") == "Firefox"
                        && BrowserCatalogSupport.cleanName("Firefox.APP") == "Firefox"
                        && BrowserCatalogSupport.cleanName("Safari") == "Safari"
                        && BrowserCatalogSupport.cleanName("My.app Browser") == "My.app Browser"
                        && BrowserCatalogSupport.cleanName(".app") == ".app",
                     "a trailing .app is stripped from display names, case-insensitively, and only at the end")
        let safari = BrowserInfo(bundleID: "com.apple.Safari", name: "Safari")
        let chrome = BrowserInfo(bundleID: "com.google.Chrome", name: "Google Chrome")
        let firefox = BrowserInfo(bundleID: "org.mozilla.firefox", name: "Firefox")
        let me = BrowserInfo(bundleID: "com.vorssaint.utils", name: "Vorssaint")
        let found = [safari, chrome, firefox, me]

        let devBuild = BrowserInfo(bundleID: "com.vorssaint.utils.dev", name: "Vorssaint Dev")
        let releaseSelf = BrowserCatalogSupport.merge(discovered: found + [devBuild], order: [], hidden: [],
                                                      excluding: "com.vorssaint.utils")
        suite.expect(!releaseSelf.all.contains(devBuild) && !releaseSelf.all.contains(me),
                     "every Vorssaint build is excluded, not only the running one")
        let devSelf = BrowserCatalogSupport.merge(discovered: found + [devBuild], order: [], hidden: [],
                                                  excluding: "com.vorssaint.utils.dev")
        suite.expect(!devSelf.all.contains(devBuild) && !devSelf.all.contains(me),
                     "the release build is excluded when the dev build runs")

        let fresh = BrowserCatalogSupport.merge(discovered: found, order: [], hidden: [],
                                                excluding: "com.vorssaint.utils")
        suite.expect(!fresh.all.contains(me) && fresh.all.count == 3,
                     "Vorssaint itself is never offered as a browser")
        suite.expect(fresh.all.map(\.name) == ["Firefox", "Google Chrome", "Safari"],
                     "with no saved order, browsers are listed alphabetically")

        let ordered = BrowserCatalogSupport.merge(discovered: found, order: ["com.apple.Safari", "org.mozilla.firefox"],
                                                  hidden: [], excluding: "com.vorssaint.utils")
        suite.expect(ordered.all.map(\.name) == ["Safari", "Firefox", "Google Chrome"],
                     "saved order comes first and newly installed browsers are appended")

        let stale = BrowserCatalogSupport.merge(discovered: [safari], order: ["gone.app", "com.apple.Safari"],
                                                hidden: ["gone.app"], excluding: "x")
        suite.expect(stale.all == [safari] && stale.visible == [safari],
                     "uninstalled browsers in the saved order are dropped")

        let hidden = BrowserCatalogSupport.merge(discovered: found, order: [], hidden: ["com.google.Chrome"],
                                                 excluding: "com.vorssaint.utils")
        suite.expect(hidden.all.count == 3 && hidden.visible.map(\.name) == ["Firefox", "Safari"],
                     "hidden browsers stay in the full list but leave the visible one")

        let duplicated = BrowserCatalogSupport.merge(discovered: [safari, safari], order: [], hidden: [], excluding: "x")
        suite.expect(duplicated.all == [safari], "a browser discovered twice is listed once")

        // Preferences round trip through a test suite.
        let name = "vorss.tests.linkrouter.browsers"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        BrowserCatalog.saveOrder(["a", "b"], defaults: defaults)
        BrowserCatalog.saveHidden(["b"], defaults: defaults)
        suite.expect(defaults.stringArray(forKey: DefaultsKey.linkRouterBrowserOrder) == ["a", "b"]
                        && Set(defaults.stringArray(forKey: DefaultsKey.linkRouterBrowserHidden) ?? []) == ["b"],
                     "order and hidden set are stored under their keys")
    }
}
