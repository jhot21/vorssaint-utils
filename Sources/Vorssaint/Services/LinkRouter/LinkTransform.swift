// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct TransformSettings: Equatable {
    var wrappers: WrapperRules = .none
    var cleaning: URLCleaning.Rules = .none
    var genericExtract = false
}

struct TransformResult: Equatable {
    var url: URL
    /// The steps that actually changed the link.
    var applied: TransformChips = []
    var removedParameters: [String] = []
    /// The wrapper link, when Extract replaced it.
    var extractedFrom: URL?
    /// The link after Extract and before Clean, for previews that show what
    /// Clean took out.
    var beforeClean: URL
}

/// The synchronous steps of the pipeline. Rewrites are asynchronous (regex
/// cannot be cancelled) and live in `LinkRewrite`; they always run after this.
enum LinkTransform {
    static func apply(_ url: URL, chips: TransformChips, settings: TransformSettings) -> TransformResult {
        var result = TransformResult(url: url, beforeClean: url)
        if chips.contains(.extract),
           let target = RedirectWrappers.destination(of: url, rules: settings.wrappers,
                                                     genericFallback: settings.genericExtract) {
            result.extractedFrom = url
            result.url = target
            result.beforeClean = target
            result.applied.insert(.extract)
        }
        if chips.contains(.clean), let cleaned = clean(result.url, settings: settings) {
            result.removedParameters = cleaned.removed
            result.url = cleaned.url
            result.applied.insert(.clean)
        }
        return result
    }

    /// Which chips would change this link. Clean is judged on the link as it
    /// will be once the selected Extract has run, because that is what Clean
    /// would see.
    static func available(for url: URL, selected: TransformChips, settings: TransformSettings) -> TransformChips {
        var offered: TransformChips = []
        let destination = RedirectWrappers.destination(of: url, rules: settings.wrappers,
                                                       genericFallback: settings.genericExtract)
        if destination != nil { offered.insert(.extract) }
        let base = selected.contains(.extract) ? (destination ?? url) : url
        if clean(base, settings: settings) != nil { offered.insert(.clean) }
        return offered
    }

    /// Nil unless cleaning removes at least one parameter. Not judged by
    /// `URLCleaning.outcome`: re-serialising the query rewrites the
    /// percent-encoding of values like a wrapper's `u=https%3A%2F%2F...` even
    /// when nothing is removed, which would offer a Clean chip on such links
    /// and then alter them for no benefit.
    private static func clean(_ url: URL, settings: TransformSettings) -> (url: URL, removed: [String])? {
        guard let result = URLCleaning.clean(url.absoluteString, rules: settings.cleaning),
              !result.removed.isEmpty,
              let cleaned = URL(string: result.url) else { return nil }
        return (cleaned, result.removed)
    }
}
