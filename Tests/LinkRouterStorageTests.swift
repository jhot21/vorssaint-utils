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

        // Rules stored before chips existed still decode, and new fields round-trip.
        let legacyJSON = #"[{"id":"00000000-0000-0000-0000-000000000001","pattern":"a.com","kind":"glob","browserBundleID":"b","isEnabled":true}]"#
        let legacy = RuleStore.decode(legacyJSON)
        suite.expect(legacy.count == 1 && legacy[0].chips == nil && legacy[0].rewriteID == nil,
                     "a stored rule without chips or rewrite decodes with both unset")
        let rewriteID = UUID()
        let rich = RoutingRule(pattern: "a.com", browserBundleID: "b", chips: [.extract, .clean], rewriteID: rewriteID)
        suite.expect(RuleStore.decode(RuleStore.encode([rich])) == [rich],
                     "chips and the rewrite id survive an encode/decode round trip")
        suite.expect(RuleStore.decode(RuleStore.encode([RoutingRule(pattern: "a.com", browserBundleID: "b", chips: [])]))[0].chips == [],
                     "an explicitly empty chip set is kept distinct from unset")
    }
}
