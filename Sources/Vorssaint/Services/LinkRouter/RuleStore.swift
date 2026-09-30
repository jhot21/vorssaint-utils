// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Rules live as one JSON string so they register a plain `String` default
/// and ride along with the settings backup.
enum RuleStore {
    static func decode(_ json: String) -> [RoutingRule] {
        (try? JSONDecoder().decode([RoutingRule].self, from: Data(json.utf8))) ?? []
    }

    static func encode(_ rules: [RoutingRule]) -> String {
        guard let data = try? JSONEncoder().encode(rules) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    /// A hand-edited backup can leave text that is not a rule list. Routing
    /// then sees no rules (it must keep working); the Links page uses this to
    /// warn instead of silently showing an empty list.
    static func isMalformed(_ json: String) -> Bool {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return (try? JSONDecoder().decode([RoutingRule].self, from: Data(trimmed.utf8))) == nil
    }

    static func load(_ defaults: UserDefaults = .standard) -> [RoutingRule] {
        decode(defaults.string(forKey: DefaultsKey.linkRouterRules) ?? "[]")
    }

    static func save(_ rules: [RoutingRule], to defaults: UserDefaults = .standard) {
        defaults.set(encode(rules), forKey: DefaultsKey.linkRouterRules)
    }
}

extension RuleStore {
    /// Reloads the stored list, applies `change`, saves and returns the result,
    /// so a view working from an older copy cannot overwrite rules added since.
    @discardableResult
    static func mutate(_ defaults: UserDefaults = .standard,
                       _ change: (inout [RoutingRule]) -> Void) -> [RoutingRule] {
        var all = load(defaults)
        change(&all)
        save(all, to: defaults)
        return all
    }
}

/// Pure edits on a rule list, keyed by rule id so a stale row is a no-op.
enum RuleEditing {
    static func setEnabled(_ id: UUID, _ enabled: Bool, in rules: inout [RoutingRule]) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[index].isEnabled = enabled
        if enabled { rules[index].flag = nil }
    }

    static func remove(_ id: UUID, from rules: inout [RoutingRule]) {
        rules.removeAll { $0.id == id }
    }

    static func move(_ id: UUID, by offset: Int, in rules: inout [RoutingRule]) {
        guard let index = rules.firstIndex(where: { $0.id == id }),
              rules.indices.contains(index + offset) else { return }
        rules.swapAt(index, index + offset)
    }

    /// Applies a drag-reordered id list. Rules missing from `ids` (added elsewhere
    /// meanwhile) keep their positions; ids no longer stored are ignored.
    static func reorder(_ ids: [UUID], in rules: inout [RoutingRule]) {
        rules = ReorderSupport.apply(order: ids.map(\.uuidString), to: rules) { $0.id.uuidString }
    }

    /// Replaces the rule with the same id (keeping its stored enabled state, and
    /// its flag unless the pattern or kind changed) or appends a new one.
    static func save(_ rule: RoutingRule, in rules: inout [RoutingRule]) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else {
            rules.append(rule)
            return
        }
        let old = rules[index]
        var updated = rule
        updated.isEnabled = old.isEnabled
        updated.flag = (old.pattern == rule.pattern && old.kind == rule.kind) ? old.flag : nil
        rules[index] = updated
    }

    static func isValidRegex(_ pattern: String) -> Bool {
        pattern.count <= RuleMatcher.maxRegexPatternLength
            && (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])) != nil
    }

    /// Glob rules always save; regex rules must compile within the length limit.
    static func canSave(_ rule: RoutingRule) -> Bool {
        rule.kind == .glob || isValidRegex(rule.pattern)
    }
}
