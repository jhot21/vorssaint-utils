// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A user regex that turns one link into another, usually to send it to a
/// privacy-respecting front-end. Rewrites are alternatives, so at most one is
/// active for a link.
struct RewriteRule: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    /// Routing-rule glob (host, optional path). Nil applies on every site.
    var site: String?
    var find: String
    /// NSRegularExpression template: `$1` is the first capture group.
    var replacement: String
    /// One lowercase letter, used as `⌘` plus the letter in the picker.
    var key: String
    var isEnabled: Bool
    var flag: RoutingRule.Flag?

    init(id: UUID = UUID(), name: String, site: String? = nil, find: String, replacement: String,
         key: String, isEnabled: Bool = true, flag: RoutingRule.Flag? = nil) {
        self.id = id; self.name = name; self.site = site; self.find = find
        self.replacement = replacement; self.key = key; self.isEnabled = isEnabled; self.flag = flag
    }
}

enum RewriteStore {
    static func decode(_ json: String) -> [RewriteRule] {
        (try? JSONDecoder().decode([RewriteRule].self, from: Data(json.utf8))) ?? []
    }

    static func encode(_ rules: [RewriteRule]) -> String {
        guard let data = try? JSONEncoder().encode(rules) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    static func isMalformed(_ json: String) -> Bool {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return (try? JSONDecoder().decode([RewriteRule].self, from: Data(trimmed.utf8))) == nil
    }

    static func load(_ defaults: UserDefaults = .standard) -> [RewriteRule] {
        decode(defaults.string(forKey: DefaultsKey.linkRouterRewrites) ?? "[]")
    }

    static func save(_ rules: [RewriteRule], to defaults: UserDefaults = .standard) {
        defaults.set(encode(rules), forKey: DefaultsKey.linkRouterRewrites)
    }
}

enum RewriteKeys {
    static let extractKey = "e"
    static let cleanKey = "l"
    /// Edit and window shortcuts the picker must leave to the system and the
    /// search field: quit, close, minimise, hide, copy, paste, cut, select
    /// all, undo, and the settings key.
    static let reserved: Set<String> = ["q", "w", "m", "h", "c", "v", "x", "a", "z", ","]

    static func isValid(_ key: String, among rules: [RewriteRule], editing id: UUID?) -> Bool {
        guard key.count == 1, let scalar = key.unicodeScalars.first,
              scalar.value >= 97, scalar.value <= 122,
              key != extractKey, key != cleanKey, !reserved.contains(key) else { return false }
        return !rules.contains { $0.key == key && $0.id != id }
    }

    /// The first letter of the name that is free, else any free letter.
    static func suggestion(for name: String, among rules: [RewriteRule]) -> String? {
        let letters = name.lowercased().map(String.init) + "abcdefghijklmnopqrstuvwxyz".map(String.init)
        return letters.first { isValid($0, among: rules, editing: nil) }
    }
}

enum RewriteFailure: Equatable { case invalid, timedOut, notWeb }
enum RewriteOutcome: Equatable { case rewritten(URL), unchanged, failed(RewriteFailure) }

enum LinkRewrite {
    static func applicable(_ rules: [RewriteRule], to url: URL) -> [RewriteRule] {
        guard let link = LinkCanonical.link(for: url) else { return [] }
        return rules.filter { rule in
            guard rule.isEnabled, rule.flag == nil else { return false }
            guard let site = rule.site?.trimmingCharacters(in: .whitespacesAndNewlines), !site.isEmpty else { return true }
            return GlobMatcher.matches(pattern: site, link: link)
        }
    }

    /// Whatever the regex returns is re-validated: a rewrite can only ever
    /// produce a web link, so a bad rule cannot hand a browser something else.
    static func apply(_ rule: RewriteRule, to url: URL, replacer: RegexReplacing,
                      completion: @escaping (RewriteOutcome) -> Void) {
        replacer.replace(pattern: rule.find, in: url.absoluteString, template: rule.replacement) { outcome in
            switch outcome {
            case .noMatch: completion(.unchanged)
            case .invalid: completion(.failed(.invalid))
            case .timedOut: completion(.failed(.timedOut))
            case .replaced(let text):
                guard let result = URL(string: text), LinkCanonical.isWeb(result),
                      let host = result.host, !host.isEmpty else {
                    completion(.failed(.notWeb))
                    return
                }
                completion(result == url ? .unchanged : .rewritten(result))
            }
        }
    }
}
