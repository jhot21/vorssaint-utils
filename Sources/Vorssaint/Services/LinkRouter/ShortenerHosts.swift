// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A host whose links redirect to the real destination. `site` uses the
/// routing-rule glob syntax (host, optionally followed by a path). Unlike a
/// `WrapperEntry` there is no parameter: the destination is in the redirect.
struct ShortenerEntry: Codable, Equatable, Hashable {
    var site: String

    var token: String { site.lowercased() }
}

struct ShortenerRules: Equatable {
    var added: [ShortenerEntry] = []
    var disabled: Set<String> = []

    static let none = ShortenerRules()
}

enum ShortenerHosts {
    // Seeded by hand from public shorteners that redirect with a plain 3xx.
    // A host is removed when the service is dead or stops redirecting; each
    // one is checked with a real lookup before a release (see the plan's
    // manual check).
    static let builtIn: [ShortenerEntry] = [
        "bit.ly", "t.co", "tinyurl.com", "ow.ly", "is.gd", "v.gd", "buff.ly", "lnkd.in",
        "cutt.ly", "rb.gy", "t.ly", "shorturl.at", "rebrand.ly", "bit.do", "s.id",
        "amzn.to", "fb.me", "wp.me", "nyti.ms", "apple.co",
    ].map { ShortenerEntry(site: $0) }

    static func entries(rules: ShortenerRules) -> [ShortenerEntry] {
        (builtIn + rules.added).filter { !rules.disabled.contains($0.token) }
    }

    /// Judged on the canonical host, so userinfo (`https://bit.ly@evil.test/`)
    /// and non-web schemes never match.
    static func isShortener(_ url: URL, rules: ShortenerRules) -> Bool {
        guard let link = LinkCanonical.link(for: url) else { return false }
        return entries(rules: rules).contains { GlobMatcher.matches(pattern: $0.site, link: link) }
    }

    /// An entry from typed text, or nil when it is empty, malformed, too broad
    /// to be a host a person means to contact, or already listed. The lookup
    /// follows hops while they stay on the list, so a broad entry would let a
    /// chain walk to arbitrary hosts.
    static func newEntry(from text: String, rules: ShortenerRules) -> ShortenerEntry? {
        let site = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !site.isEmpty, !site.contains(where: \.isWhitespace), !site.contains("://") else { return nil }
        let host = LinkCanonical.splitPattern(site).host.lowercased()
        guard !host.contains("@"), !host.contains(":") else { return nil }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        // At least two labels, a literal last label, and one literal label
        // before it (a label of only stars is not literal): `*`, `*.*`, `*.com`,
        // `**.com` and `bit.*` are all too broad.
        guard labels.count >= 2, let last = labels.last, !last.isEmpty, !last.contains("*"),
              labels.dropLast().contains(where: { $0.contains { $0 != "*" } }) else { return nil }
        let entry = ShortenerEntry(site: site)
        let known = Set(builtIn.map(\.token)).union(rules.added.map(\.token))
        return known.contains(entry.token) ? nil : entry
    }
}

enum ShortenerStore {
    static func loadAdded(_ defaults: UserDefaults = .standard) -> [ShortenerEntry] {
        let json = defaults.string(forKey: DefaultsKey.linkRouterShortenerHosts) ?? "[]"
        return (try? JSONDecoder().decode([ShortenerEntry].self, from: Data(json.utf8))) ?? []
    }

    static func saveAdded(_ entries: [ShortenerEntry], to defaults: UserDefaults = .standard) {
        let data = (try? JSONEncoder().encode(entries)) ?? Data("[]".utf8)
        defaults.set(String(decoding: data, as: UTF8.self), forKey: DefaultsKey.linkRouterShortenerHosts)
    }

    static func loadDisabled(_ defaults: UserDefaults = .standard) -> Set<String> {
        Set((defaults.string(forKey: DefaultsKey.linkRouterShortenerDisabled) ?? "")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    static func saveDisabled(_ tokens: Set<String>, to defaults: UserDefaults = .standard) {
        defaults.set(tokens.sorted().joined(separator: ","), forKey: DefaultsKey.linkRouterShortenerDisabled)
    }
}
