// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum LinkRouterStorageTests {
    static func run(_ suite: TestSuite) {
        let rules = [
            RoutingRule(pattern: "github.com", browserBundleID: "com.apple.Safari"),
            RoutingRule(pattern: "^https://x\\.test/", kind: .regex, browserBundleID: "org.mozilla.firefox",
                        sourceAppBundleID: "com.apple.mail", isEnabled: false, flag: .tooSlow),
        ]
        suite.expect(RuleStore.decode(RuleStore.encode(rules)) == rules,
                     "rules survive a JSON round trip unchanged")
        suite.expect(RuleStore.decode("").isEmpty && RuleStore.decode("not json").isEmpty
                        && RuleStore.decode("[]").isEmpty,
                     "unreadable or empty stored rules decode to an empty list, never a crash")

        suite.expect(!RuleStore.isMalformed("") && !RuleStore.isMalformed("[]")
                        && !RuleStore.isMalformed(RuleStore.encode(rules))
                        && RuleStore.isMalformed("not json") && RuleStore.isMalformed("{\"a\":1}"),
                     "only non-empty text that does not decode counts as malformed")

        let name = "vorss.tests.linkrouter.storage"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        suite.expect(RuleStore.load(defaults).isEmpty, "an unset store loads as empty")
        RuleStore.save(rules, to: defaults)
        suite.expect(RuleStore.load(defaults) == rules, "saved rules load back")

        // Registered defaults and backup classification.
        let registered = Defaults.registeredDefaults
        suite.expect(registered[DefaultsKey.linkRouterEnabled] as? Bool == false
                        && registered[DefaultsKey.linkRouterRules] as? String == "[]"
                        && registered[DefaultsKey.linkRouterShowURLLine] as? Bool == true
                        && registered[DefaultsKey.linkRouterShowUndoToast] as? Bool == true
                        && registered[DefaultsKey.linkRouterPreviousDefault] as? String == ""
                        && registered[DefaultsKey.linkRouterBrowserOrder] as? [String] == []
                        && registered[DefaultsKey.linkRouterBrowserHidden] as? [String] == [],
                     "link router keys are registered with their documented defaults")

        let exported = SettingsBackupSupport.exportKeys()
        suite.expect(exported.contains(DefaultsKey.linkRouterEnabled)
                        && exported.contains(DefaultsKey.linkRouterRules)
                        && exported.contains(DefaultsKey.linkRouterShowURLLine)
                        && exported.contains(DefaultsKey.linkRouterShowUndoToast),
                     "rules and the enable and picker toggles travel in a backup")
        suite.expect(!exported.contains(DefaultsKey.linkRouterPreviousDefault)
                        && !exported.contains(DefaultsKey.linkRouterBrowserOrder)
                        && !exported.contains(DefaultsKey.linkRouterBrowserHidden),
                     "the previous default and this Mac's browser order and hidden set never travel")
    }
}
