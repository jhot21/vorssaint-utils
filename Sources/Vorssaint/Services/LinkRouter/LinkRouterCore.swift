// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct LinkRequest: Equatable {
    var urls: [URL]
    var senderBundleID: String?
    /// False for links Vorssaint opens itself (the repository, coffee or update
    /// page): rules still apply, but with no match they open in the fallback
    /// browser instead of popping a picker at the cursor.
    var allowsPicker: Bool = true
}

/// Everything the core needs from the outside world. Note there is no
/// "open this web URL with the system default": inside Vorssaint that would
/// loop straight back into the router once it is the default browser.
protocol LinkRouterEnvironment: AnyObject {
    var isFeatureOn: Bool { get }
    var rules: [RoutingRule] { get }
    var visibleBrowsers: [BrowserInfo] { get }
    var previousDefaultBundleID: String? { get }
    var isScreenLocked: Bool { get }
    func isInstalled(bundleID: String) -> Bool
    func open(_ url: URL, inBundleID bundleID: String)
    func openNonWeb(_ url: URL)
    func noBrowserAvailable(for url: URL)
    func showPicker(for url: URL, waiting: Int)
    func hidePicker()
    func addRule(_ rule: RoutingRule)
    func flagRule(id: UUID, flag: RoutingRule.Flag)
}

/// Decides what happens to each link. Call it from the main thread only.
final class LinkRouterCore {
    static let queueCap = 10
    private static let lastResortBundleID = "com.apple.Safari"

    private weak var environment: LinkRouterEnvironment?
    private let evaluator: RegexEvaluating
    private let selfBundleID: String

    private(set) var isReady = false
    private var buffered: [(url: URL, sender: String?, allowsPicker: Bool)] = []
    private var current: URL?
    private var waiting: [URL] = []

    init(environment: LinkRouterEnvironment, evaluator: RegexEvaluating, selfBundleID: String) {
        self.environment = environment
        self.evaluator = evaluator
        self.selfBundleID = selfBundleID
    }

    /// Called once settings and services are loaded; drains links that
    /// arrived earlier (a click can launch the app).
    func setReady() {
        isReady = true
        let pending = buffered
        buffered = []
        for item in pending { route(url: item.url, sender: item.sender, allowsPicker: item.allowsPicker) }
    }

    func route(_ request: LinkRequest) {
        for url in request.urls { route(url: url, sender: request.senderBundleID, allowsPicker: request.allowsPicker) }
    }

    private func route(url: URL, sender: String?, allowsPicker: Bool) {
        guard let environment else { return }
        guard LinkCanonical.isWeb(url) else { environment.openNonWeb(url); return }
        guard isReady else { buffered.append((url, sender, allowsPicker)); return }
        guard environment.isFeatureOn else { openFallback(url); return }
        RuleMatcher.firstMatch(url: url, sourceApp: sender, rules: environment.rules,
                               evaluator: evaluator) { [weak self] result in
            guard let self, let environment = self.environment else { return }
            for failure in result.failures { environment.flagRule(id: failure.id, flag: failure.flag) }
            if let rule = result.rule,
               rule.browserBundleID != self.selfBundleID,
               environment.isInstalled(bundleID: rule.browserBundleID) {
                environment.open(url, inBundleID: rule.browserBundleID)
            } else if allowsPicker {
                self.enqueue(url)
            } else {
                self.openFallback(url)
            }
        }
    }

    // MARK: Picker queue

    private func enqueue(_ url: URL) {
        guard let environment else { return }
        if environment.isScreenLocked || environment.visibleBrowsers.isEmpty {
            openFallback(url)
            return
        }
        if current == nil {
            current = url
            environment.showPicker(for: url, waiting: waiting.count)
        } else if waiting.count < Self.queueCap {
            waiting.append(url)
            if let current { environment.showPicker(for: current, waiting: waiting.count) }
        } else {
            openFallback(url)
        }
    }

    func pickerDidChoose(_ url: URL, bundleID: String, saveRule: Bool) {
        guard let environment else { return }
        environment.open(url, inBundleID: bundleID)
        if saveRule, let host = LinkCanonical.link(for: url)?.host {
            environment.addRule(RoutingRule(pattern: host, browserBundleID: bundleID))
        }
        advance()
    }

    func pickerDidCancel(_ url: URL) {
        openFallback(url)
        advance()
    }

    /// The feature is going away: nothing pending may be lost.
    func stopAll() {
        let pending = [current].compactMap { $0 } + waiting
        current = nil
        waiting = []
        for url in pending { openFallback(url) }
        environment?.hidePicker()
    }

    private func advance() {
        guard let environment else { return }
        if waiting.isEmpty {
            current = nil
            environment.hidePicker()
        } else {
            let next = waiting.removeFirst()
            current = next
            environment.showPicker(for: next, waiting: waiting.count)
        }
    }

    // MARK: Fallback

    /// The previous default browser, else the first visible one, else Safari.
    /// Never Vorssaint, and always an installed app.
    func fallbackBundleID() -> String? {
        guard let environment else { return nil }
        let candidates = [environment.previousDefaultBundleID]
            + environment.visibleBrowsers.map { Optional($0.bundleID) }
            + [Self.lastResortBundleID]
        return candidates.compactMap { $0 }.first {
            !$0.isEmpty && $0 != selfBundleID && environment.isInstalled(bundleID: $0)
        }
    }

    private func openFallback(_ url: URL) {
        guard let environment else { return }
        if let bundleID = fallbackBundleID() {
            environment.open(url, inBundleID: bundleID)
        } else {
            environment.noBrowserAvailable(for: url)
        }
    }
}
