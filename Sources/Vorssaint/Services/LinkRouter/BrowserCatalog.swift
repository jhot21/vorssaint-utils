// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

struct BrowserInfo: Equatable, Identifiable {
    let bundleID: String
    let name: String
    var id: String { bundleID }
}

/// Ordering and visibility rules, free of AppKit discovery so they can be
/// tested: saved order first, new browsers appended alphabetically,
/// uninstalled ones dropped, every Vorssaint build never offered.
enum BrowserCatalogSupport {
    /// Release, development and leftover copies all share this prefix, and
    /// none of them may be offered as, or fall back to, a browser.
    static func isVorssaint(_ bundleID: String) -> Bool {
        bundleID.hasPrefix("com.vorssaint.utils")
    }

    /// Finder shows some apps with their extension ("Firefox.app"); the list
    /// reads better without it. Only a trailing ".app" is removed.
    static func cleanName(_ name: String) -> String {
        guard name.count > 4, name.lowercased().hasSuffix(".app") else { return name }
        return String(name.dropLast(4))
    }

    static func merge(discovered: [BrowserInfo], order: [String], hidden: Set<String>,
                      excluding selfBundleID: String) -> (all: [BrowserInfo], visible: [BrowserInfo]) {
        var unique: [BrowserInfo] = []
        for browser in discovered where browser.bundleID != selfBundleID && !isVorssaint(browser.bundleID)
            && !unique.contains(where: { $0.bundleID == browser.bundleID }) {
            unique.append(browser)
        }
        var all: [BrowserInfo] = []
        for id in order {
            if let browser = unique.first(where: { $0.bundleID == id }), !all.contains(browser) {
                all.append(browser)
            }
        }
        let remaining = unique.filter { candidate in !all.contains(where: { $0.bundleID == candidate.bundleID }) }
        all += remaining.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return (all, all.filter { !hidden.contains($0.bundleID) })
    }
}

enum BrowserDiscovery {
    /// Every installed app that opens http or https links, the same universe
    /// System Settings' default-browser picker draws from. Both schemes are
    /// probed so an app registered for only one is not missed.
    static func installed() -> [BrowserInfo] {
        var browsers: [BrowserInfo] = []
        for probe in ["https://example.com", "http://example.com"] {
            guard let url = URL(string: probe) else { continue }
            for appURL in NSWorkspace.shared.urlsForApplications(toOpen: url) {
                guard let identifier = Bundle(url: appURL)?.bundleIdentifier,
                      !browsers.contains(where: { $0.bundleID == identifier }) else { continue }
                browsers.append(BrowserInfo(bundleID: identifier,
                                            name: BrowserCatalogSupport.cleanName(FileManager.default.displayName(atPath: appURL.path))))
            }
        }
        return browsers
    }
}

enum BrowserCatalog {
    static var ownBundleID: String { Bundle.main.bundleIdentifier ?? "com.vorssaint.utils" }

    static func current(defaults: UserDefaults = .standard,
                        selfBundleID: String = BrowserCatalog.ownBundleID) -> (all: [BrowserInfo], visible: [BrowserInfo]) {
        BrowserCatalogSupport.merge(
            discovered: BrowserDiscovery.installed(),
            order: defaults.stringArray(forKey: DefaultsKey.linkRouterBrowserOrder) ?? [],
            hidden: Set(defaults.stringArray(forKey: DefaultsKey.linkRouterBrowserHidden) ?? []),
            excluding: selfBundleID)
    }

    static func saveOrder(_ ids: [String], defaults: UserDefaults = .standard) {
        defaults.set(ids, forKey: DefaultsKey.linkRouterBrowserOrder)
    }

    static func saveHidden(_ ids: Set<String>, defaults: UserDefaults = .standard) {
        defaults.set(Array(ids).sorted(), forKey: DefaultsKey.linkRouterBrowserHidden)
    }
}
