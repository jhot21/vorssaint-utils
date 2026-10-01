// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A site whose links carry the real destination in one query parameter.
/// `site` uses the routing-rule glob syntax (host, optionally followed by a
/// path), so `www.google.*/url` covers every Google country domain.
struct WrapperEntry: Codable, Equatable, Hashable {
    var site: String
    var parameter: String

    /// Host+path+parameter: several wrappers share one host, so the host alone
    /// cannot say which one a user switched off.
    var token: String { "\(site.lowercased())|\(parameter.lowercased())" }
}

struct WrapperRules: Equatable {
    var added: [WrapperEntry] = []
    var disabled: Set<String> = []

    static let none = WrapperRules()
}

enum RedirectWrappers {
    // Seeded by hand from the simple `redirections` entries of the ClearURLs
    // rule set (https://github.com/ClearURLs/Rules, LGPL-3.0), the same data
    // URLCheck ships. Entries that need a regex or keep the destination in the
    // path are left out on purpose. Order matters: the first entry that yields
    // a web URL wins, so Google's `url` is tried before `q`.
    static let builtIn: [WrapperEntry] = [
        WrapperEntry(site: "www.google.*/url", parameter: "url"),
        WrapperEntry(site: "www.google.*/url", parameter: "q"),
        WrapperEntry(site: "www.googleadservices.com/*", parameter: "adurl"),
        WrapperEntry(site: "www.youtube.com/redirect", parameter: "q"),
        WrapperEntry(site: "l.facebook.com/l.php", parameter: "u"),
        WrapperEntry(site: "lm.facebook.com/l.php", parameter: "u"),
        WrapperEntry(site: "l.messenger.com/l.php", parameter: "u"),
        WrapperEntry(site: "out.reddit.com/*", parameter: "url"),
        WrapperEntry(site: "click.redditmail.com/*", parameter: "url"),
        WrapperEntry(site: "steamcommunity.com/linkfilter/*", parameter: "url"),
        WrapperEntry(site: "vk.com/away.php", parameter: "to"),
        WrapperEntry(site: "duckduckgo.com/l/*", parameter: "uddg"),
        WrapperEntry(site: "t.umblr.com/redirect", parameter: "z"),
        WrapperEntry(site: "www.curseforge.com/linkout", parameter: "remoteUrl"),
        WrapperEntry(site: "disq.us/url", parameter: "url"),
        WrapperEntry(site: "go.skimresources.com/*", parameter: "url"),
        WrapperEntry(site: "redirect.viglink.com/*", parameter: "u"),
        WrapperEntry(site: "rover.ebay.*/rover/*", parameter: "mpre"),
        WrapperEntry(site: "www.awin1.com/*", parameter: "ued"),
        WrapperEntry(site: "track.adform.net/C/*", parameter: "ckurl"),
        WrapperEntry(site: "*.linksynergy.com/*", parameter: "murl"),
        WrapperEntry(site: "app.adjust.com/*", parameter: "redirect"),
    ]

    static func entries(rules: WrapperRules) -> [WrapperEntry] {
        (builtIn + rules.added).filter { !rules.disabled.contains($0.token) }
    }

    /// The link a wrapper points at, or nil when the link is not a wrapper or
    /// the parameter does not hold a web URL. One level only: a destination
    /// that is itself a wrapper is not followed.
    static func destination(of url: URL, rules: WrapperRules = .none, genericFallback: Bool = false) -> URL? {
        guard let link = LinkCanonical.link(for: url),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              !items.isEmpty else { return nil }
        for entry in entries(rules: rules) where GlobMatcher.matches(pattern: entry.site, link: link) {
            // queryItems values are already percent-decoded; decoding again
            // would corrupt a destination that legitimately contains `%`.
            let wanted = entry.parameter.lowercased()
            if let value = items.first(where: { $0.name.lowercased() == wanted })?.value,
               let target = webURL(value), target != url {
                return target
            }
        }
        guard genericFallback else { return nil }
        for item in items {
            if let value = item.value, let target = webURL(value), target != url { return target }
        }
        return nil
    }

    private static func webURL(_ text: String) -> URL? {
        guard let url = URL(string: text), LinkCanonical.isWeb(url),
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}
