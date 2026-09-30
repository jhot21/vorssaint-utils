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
