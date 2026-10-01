// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The host and path a rule is matched against. Query, fragment, port and
/// userinfo are deliberately not part of it.
struct CanonicalLink: Equatable {
    /// Lowercased ASCII (punycode) host without a trailing dot.
    let host: String
    /// Never empty: a bare host canonicalizes to "/".
    let path: String
}

/// One canonical form shared by the matcher and by rule creation, so a rule
/// the picker writes always matches the link it was created from.
enum LinkCanonical {
    static func isWeb(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    static func link(for url: URL) -> CanonicalLink? {
        guard isWeb(url), let host = url.host, !host.isEmpty else { return nil }
        // URL.host already hands back the punycode form of a Unicode host.
        return CanonicalLink(host: normalize(host: host), path: url.path.isEmpty ? "/" : url.path)
    }

    static func normalize(host: String) -> String {
        var value = host.lowercased()
        while value.hasSuffix(".") { value.removeLast() }
        return value
    }

    /// A pattern host may hold `*` and Unicode; Foundation punycodes the
    /// labels and leaves `*` alone, so both spellings of a host compare equal.
    static func normalizePatternHost(_ host: String) -> String {
        normalize(host: URL(string: "https://" + host)?.host ?? host)
    }

    /// `github.com/x/*` becomes ("github.com", "/x/*"); a pattern without a
    /// slash has no path part and so matches every path. A typed scheme is
    /// dropped.
    static func splitPattern(_ pattern: String) -> (host: String, path: String?) {
        var text = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        for scheme in ["https://", "http://"] where text.lowercased().hasPrefix(scheme) {
            text.removeFirst(scheme.count)
        }
        guard let slash = text.firstIndex(of: "/") else { return (text, nil) }
        return (String(text[..<slash]), String(text[slash...]))
    }
}

/// Anchored wildcard matching where `*` matches any run of characters,
/// including none. Iterative with a single backtrack point, so it is linear
/// in practice and can never blow up the way a regex can.
enum Wildcard {
    static func matches(pattern: String, text: String) -> Bool {
        let p = Array(pattern), t = Array(text)
        var pi = 0, ti = 0, star = -1, mark = 0
        while ti < t.count {
            if pi < p.count, p[pi] == "*" {
                star = pi; mark = ti; pi += 1
            } else if pi < p.count, p[pi] == t[ti] {
                pi += 1; ti += 1
            } else if star >= 0 {
                pi = star + 1; mark += 1; ti = mark
            } else {
                return false
            }
        }
        while pi < p.count, p[pi] == "*" { pi += 1 }
        return pi == p.count
    }
}

enum GlobMatcher {
    static func matches(pattern: String, link: CanonicalLink) -> Bool {
        let (hostPattern, pathPattern) = LinkCanonical.splitPattern(pattern)
        guard !hostPattern.isEmpty,
              Wildcard.matches(pattern: LinkCanonical.normalizePatternHost(hostPattern), text: link.host)
        else { return false }
        guard let pathPattern else { return true }
        return Wildcard.matches(pattern: pathPattern, text: link.path)
    }
}
