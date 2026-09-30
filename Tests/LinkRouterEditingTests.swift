// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum LinkRouterEditingTests {
    static func run(_ suite: TestSuite) {
        let name = "vorss.tests.linkrouter.editing"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }

        let a = RoutingRule(pattern: "a.test", browserBundleID: "b.one")
        let b = RoutingRule(pattern: "b.test", browserBundleID: "b.two")
        let c = RoutingRule(pattern: "c.test", browserBundleID: "b.one")
        RuleStore.save([a, b], to: defaults)

        // A rule stored behind the page's back survives a later change made from a stale view.
        RuleStore.save([a, b, c], to: defaults)
        let afterToggle = RuleStore.mutate(defaults) { RuleEditing.setEnabled(a.id, false, in: &$0) }
        suite.expect(afterToggle.map(\.id) == [a.id, b.id, c.id] && !afterToggle[0].isEnabled
                        && RuleStore.load(defaults) == afterToggle,
                     "a mutation applies to the stored list, keeps unseen rules and saves the result")

        let afterRemove = RuleStore.mutate(defaults) { RuleEditing.remove(b.id, from: &$0) }
        suite.expect(afterRemove.map(\.id) == [a.id, c.id], "remove is keyed by id")
        let noop = RuleStore.mutate(defaults) {
            RuleEditing.remove(b.id, from: &$0)
            RuleEditing.move(b.id, by: 1, in: &$0)
            RuleEditing.setEnabled(b.id, true, in: &$0)
        }
        suite.expect(noop == afterRemove, "an id that no longer exists is a no-op")

        var list = [a, b, c]
        RuleEditing.move(a.id, by: -1, in: &list)
        RuleEditing.move(c.id, by: 1, in: &list)
        suite.expect(list.map(\.id) == [a.id, b.id, c.id], "moves past either end are ignored")
        RuleEditing.move(c.id, by: -1, in: &list)
        suite.expect(list.map(\.id) == [a.id, c.id, b.id], "move swaps with the neighbour")

        // Enabling clears the flag; disabling keeps it.
        var flagged = [RoutingRule(id: a.id, pattern: "x", browserBundleID: "b", isEnabled: false, flag: .tooSlow)]
        RuleEditing.setEnabled(a.id, false, in: &flagged)
        suite.expect(flagged[0].flag == .tooSlow, "disabling keeps the flag")
        RuleEditing.setEnabled(a.id, true, in: &flagged)
        suite.expect(flagged[0].isEnabled && flagged[0].flag == nil, "enabling clears the flag")

        // Saving from the editor.
        var saveList = [RoutingRule(id: a.id, pattern: "old", browserBundleID: "b", isEnabled: false, flag: .tooSlow)]
        var edited = saveList[0]
        edited.browserBundleID = "other"
        edited.isEnabled = true
        RuleEditing.save(edited, in: &saveList)
        suite.expect(!saveList[0].isEnabled && saveList[0].flag == .tooSlow && saveList[0].browserBundleID == "other",
                     "saving keeps the stored enabled state and keeps the flag when the pattern is unchanged")
        edited.pattern = "new"
        RuleEditing.save(edited, in: &saveList)
        suite.expect(saveList[0].flag == nil && !saveList[0].isEnabled && saveList[0].pattern == "new",
                     "changing the pattern clears the flag")
        saveList[0].flag = .invalidRegex
        edited.kind = .regex
        RuleEditing.save(edited, in: &saveList)
        suite.expect(saveList[0].flag == nil, "changing the kind clears the flag")
        let fresh = RoutingRule(pattern: "n", browserBundleID: "b")
        RuleEditing.save(fresh, in: &saveList)
        suite.expect(saveList.count == 2 && saveList[1] == fresh, "a new rule is appended as given")

        // Regex validation.
        suite.expect(RuleEditing.isValidRegex("^https://a\\.test/") && RuleEditing.isValidRegex("(?i)x"),
                     "a compilable regex is valid")
        suite.expect(!RuleEditing.isValidRegex("(unclosed") && !RuleEditing.isValidRegex("[a-"),
                     "a regex that does not compile is invalid")
        suite.expect(RuleEditing.isValidRegex(String(repeating: "a", count: RuleMatcher.maxRegexPatternLength))
                        && !RuleEditing.isValidRegex(String(repeating: "a", count: RuleMatcher.maxRegexPatternLength + 1)),
                     "a regex over the length limit is invalid")
        suite.expect(RuleEditing.canSave(RoutingRule(pattern: "(", kind: .glob, browserBundleID: "b"))
                        && !RuleEditing.canSave(RoutingRule(pattern: "(", kind: .regex, browserBundleID: "b")),
                     "only regex rules are validated on save")
    }
}
