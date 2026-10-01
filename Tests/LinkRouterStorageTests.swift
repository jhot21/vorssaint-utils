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

        // URL line mode: an explicitly stored legacy value keeps today's behavior.
        suite.expect(LinkURLLineMode.resolve(stored: nil, legacy: nil) == .full
                        && LinkURLLineMode.resolve(stored: nil, legacy: true) == .hostPath
                        && LinkURLLineMode.resolve(stored: nil, legacy: false) == .off
                        && LinkURLLineMode.resolve(stored: "off", legacy: true) == .off
                        && LinkURLLineMode.resolve(stored: "full", legacy: false) == .full
                        && LinkURLLineMode.resolve(stored: "bogus", legacy: nil) == .full,
                     "the URL line mode defaults to full, maps a stored legacy bool, and lets the new key win")

        let prefsName = "vorss.tests.linkrouter.prefs"
        let prefsDefaults = UserDefaults(suiteName: prefsName)!
        prefsDefaults.removePersistentDomain(forName: prefsName)
        defer { prefsDefaults.removePersistentDomain(forName: prefsName) }
        suite.expect(LinkURLLineMode.current(prefsDefaults, domain: prefsName) == .full,
                     "nothing stored means full")
        prefsDefaults.set(true, forKey: DefaultsKey.linkRouterShowURLLine)
        suite.expect(LinkURLLineMode.current(prefsDefaults, domain: prefsName) == .hostPath,
                     "a stored legacy true keeps the old host and path line")
        prefsDefaults.set("off", forKey: DefaultsKey.linkRouterURLLineMode)
        suite.expect(LinkURLLineMode.current(prefsDefaults, domain: prefsName) == .off,
                     "the new key overrides the legacy one")
        prefsDefaults.removeObject(forKey: DefaultsKey.linkRouterURLLineMode)
        prefsDefaults.removeObject(forKey: DefaultsKey.linkRouterShowURLLine)

        let loaded = LinkTransformPrefs.load(prefsDefaults)
        suite.expect(loaded.defaultChips.isEmpty && loaded.rewrites.isEmpty && !loaded.settings.genericExtract,
                     "unset transform preferences load as everything off")
        prefsDefaults.set(3, forKey: DefaultsKey.linkRouterDefaultChips)
        prefsDefaults.set(true, forKey: DefaultsKey.linkRouterGenericExtract)
        WrapperStore.saveAdded([WrapperEntry(site: "a.test/go", parameter: "to")], to: prefsDefaults)
        WrapperStore.saveDisabled(["vk.com/away.php|to"], to: prefsDefaults)
        RewriteStore.save([RewriteRule(name: "R", find: "a", replacement: "b", key: "r")], to: prefsDefaults)
        let filled = LinkTransformPrefs.load(prefsDefaults)
        suite.expect(filled.defaultChips == [.extract, .clean] && filled.settings.genericExtract
                        && filled.settings.wrappers.added.count == 1
                        && filled.settings.wrappers.disabled == ["vk.com/away.php|to"]
                        && filled.rewrites.count == 1,
                     "stored transform preferences load back into one value")

        suite.expect(registered[DefaultsKey.linkRouterDefaultChips] as? Int == 0
                        && registered[DefaultsKey.linkRouterWrapperRules] as? String == "[]"
                        && registered[DefaultsKey.linkRouterWrapperDisabled] as? String == ""
                        && registered[DefaultsKey.linkRouterRewrites] as? String == "[]"
                        && registered[DefaultsKey.linkRouterGenericExtract] as? Bool == false
                        && registered[DefaultsKey.linkRouterURLLineMode] as? String == "full",
                     "the transform keys are registered with their documented defaults")
        for key in [DefaultsKey.linkRouterDefaultChips, DefaultsKey.linkRouterWrapperRules,
                    DefaultsKey.linkRouterWrapperDisabled, DefaultsKey.linkRouterRewrites,
                    DefaultsKey.linkRouterGenericExtract, DefaultsKey.linkRouterURLLineMode] {
            suite.expect(exported.contains(key), "the transform setting \(key) travels in a backup")
        }
    }
}
