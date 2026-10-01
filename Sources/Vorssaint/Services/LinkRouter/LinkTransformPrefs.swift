// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum LinkURLLineMode: String {
    case off, hostPath, full

    /// The new key wins. Without it, a legacy `linkRouterShowURLLine` that the
    /// user explicitly stored keeps its old meaning (true was host and path),
    /// so upgrading does not change what they see. With neither, full.
    static func resolve(stored: String?, legacy: Bool?) -> LinkURLLineMode {
        if let stored, let mode = LinkURLLineMode(rawValue: stored) { return mode }
        switch legacy {
        case true?: return .hostPath
        case false?: return .off
        case nil: return .full
        }
    }

    /// `object(forKey:)` would also return registered defaults, which would
    /// make a fresh install look like a stored `true`; the persistent domain
    /// holds only what was actually written.
    static func current(_ defaults: UserDefaults = .standard,
                        domain: String? = Bundle.main.bundleIdentifier) -> LinkURLLineMode {
        let saved = domain.flatMap { defaults.persistentDomain(forName: $0) } ?? [:]
        return resolve(stored: saved[DefaultsKey.linkRouterURLLineMode] as? String,
                       legacy: saved[DefaultsKey.linkRouterShowURLLine] as? Bool)
    }
}

enum WrapperStore {
    static func loadAdded(_ defaults: UserDefaults = .standard) -> [WrapperEntry] {
        let json = defaults.string(forKey: DefaultsKey.linkRouterWrapperRules) ?? "[]"
        return (try? JSONDecoder().decode([WrapperEntry].self, from: Data(json.utf8))) ?? []
    }

    static func saveAdded(_ entries: [WrapperEntry], to defaults: UserDefaults = .standard) {
        let data = (try? JSONEncoder().encode(entries)) ?? Data("[]".utf8)
        defaults.set(String(decoding: data, as: UTF8.self), forKey: DefaultsKey.linkRouterWrapperRules)
    }

    static func loadDisabled(_ defaults: UserDefaults = .standard) -> Set<String> {
        Set((defaults.string(forKey: DefaultsKey.linkRouterWrapperDisabled) ?? "")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    static func saveDisabled(_ tokens: Set<String>, to defaults: UserDefaults = .standard) {
        defaults.set(tokens.sorted().joined(separator: ","), forKey: DefaultsKey.linkRouterWrapperDisabled)
    }
}

/// Everything the transform pipeline reads from preferences, loaded in one
/// place so the router and the picker cannot disagree.
struct LinkTransformPrefs: Equatable {
    var defaultChips: TransformChips
    var settings: TransformSettings
    var rewrites: [RewriteRule]

    static func load(_ defaults: UserDefaults = .standard) -> LinkTransformPrefs {
        let cleaning = URLCleaning.rules(
            globalNames: defaults.string(forKey: DefaultsKey.urlCleanerCustomParameters),
            siteNames: defaults.string(forKey: DefaultsKey.urlCleanerSiteParameters),
            disabledNames: defaults.string(forKey: DefaultsKey.urlCleanerDisabledParameters))
        return LinkTransformPrefs(
            defaultChips: TransformChips(rawValue: defaults.integer(forKey: DefaultsKey.linkRouterDefaultChips)),
            settings: TransformSettings(
                wrappers: WrapperRules(added: WrapperStore.loadAdded(defaults),
                                       disabled: WrapperStore.loadDisabled(defaults)),
                cleaning: cleaning,
                genericExtract: defaults.bool(forKey: DefaultsKey.linkRouterGenericExtract)),
            rewrites: RewriteStore.load(defaults))
    }
}
