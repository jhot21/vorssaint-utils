// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

final class LinkPickerModel: ObservableObject {
    enum RewriteStatus: Equatable { case idle, pending, applied, failed }

    /// The clicked link. A queued link gets a new model, so this never changes.
    let url: URL
    let prefs: LinkTransformPrefs
    let mode: LinkURLLineMode
    /// New for every model, so the view can tell "another link" from "an
    /// update" and refocus its field.
    let instanceID = UUID()
    @Published var state: LinkPickerState
    @Published var waiting: Int
    @Published private(set) var result: TransformResult
    @Published private(set) var rewritten: URL?
    @Published private(set) var rewriteStatus: RewriteStatus = .idle
    @Published private(set) var availableChips: TransformChips = []
    /// Set once a browser is chosen; later keys and clicks are ignored so one
    /// link can never open twice.
    private(set) var isCommitting = false
    var choose: (BrowserInfo, Bool, URL, TransformChips, UUID?) -> Void = { _, _, _, _, _ in }

    private let replacer: RegexReplacing
    private let flagRewrite: (UUID, RoutingRule.Flag) -> Void
    private var rewriteToken = 0
    private var pendingCommit: (browser: BrowserInfo, remember: Bool)?

    init(url: URL, browsers: [BrowserInfo], prefs: LinkTransformPrefs, mode: LinkURLLineMode,
         waiting: Int, replacer: RegexReplacing, flagRewrite: @escaping (UUID, RoutingRule.Flag) -> Void) {
        self.url = url
        self.prefs = prefs
        self.mode = mode
        self.waiting = waiting
        self.replacer = replacer
        self.flagRewrite = flagRewrite
        // The rewrites offered depend on the link after the default chips ran,
        // so they are filled in by the first recompute.
        self.state = LinkPickerState(browsers: browsers, rewrites: [], chips: prefs.defaultChips)
        self.result = TransformResult(url: url, beforeClean: url)
        recompute()
    }

    /// A queued link makes the router present the current one again; that is
    /// an update to the waiting count, not a new decision.
    func matches(_ other: URL) -> Bool { url == other }

    var finalURL: URL { rewritten ?? result.url }
    var keyMap: LinkPickerKeyMap { LinkPickerKeyMap.make(rewrites: state.rewrites) }

    // Every way of changing the picker is ignored once a browser is chosen.
    // A click on a chip while the open waits for a rewrite would otherwise
    // supersede that rewrite, and the open waiting on it would never happen.
    func setQuery(_ text: String) { guard !isCommitting else { return }; state.setQuery(text) }
    func move(_ delta: Int) { guard !isCommitting else { return }; state.move(delta) }
    func select(row: Int) { guard !isCommitting else { return }; state.select(row: row) }

    func toggleChip(_ chip: TransformChips) {
        guard !isCommitting else { return }
        state.toggleChip(chip)
        recompute()
    }

    func toggleRewrite(_ id: UUID) {
        guard !isCommitting else { return }
        state.toggleRewrite(id)
        recompute()
    }

    func activate() -> LinkPickerState.Activation {
        guard !isCommitting else { return .nothing }
        let activation = state.activate()
        if activation == .toggledRewrite { recompute() }
        return activation
    }

    func escape() -> LinkPickerState.EscapeResult {
        guard !isCommitting else { return .clearedQuery }
        return state.escape()
    }

    /// A rewrite still running when a browser is chosen is waited for; the
    /// evaluator's own deadline bounds the wait, after which the link opens
    /// without the rewrite.
    func commit(_ browser: BrowserInfo, remember: Bool) {
        guard !isCommitting else { return }
        isCommitting = true
        if rewriteStatus == .pending {
            pendingCommit = (browser, remember)
        } else {
            choose(browser, remember, finalURL, state.chips, state.activeRewrite)
        }
    }

    private func recompute() {
        result = LinkTransform.apply(url, chips: state.chips, settings: prefs.settings)
        availableChips = LinkTransform.available(for: url, selected: state.chips, settings: prefs.settings)
        // A rewrite runs on the link as edited, so its site scope is judged
        // against that link, the same way an auto-open rule judges it.
        state.rewrites = LinkRewrite.applicable(prefs.rewrites, to: result.url)
        if let id = state.activeRewrite, !state.rewrites.contains(where: { $0.id == id }) {
            state.activeRewrite = nil
        }
        rewriteToken += 1
        let token = rewriteToken
        rewritten = nil
        guard let id = state.activeRewrite, let rule = state.rewrites.first(where: { $0.id == id }) else {
            rewriteStatus = .idle
            return
        }
        rewriteStatus = .pending
        LinkRewrite.apply(rule, to: result.url, replacer: replacer) { [weak self] outcome in
            guard let self, self.rewriteToken == token else { return }
            switch outcome {
            case .rewritten(let link):
                self.rewritten = link
                self.rewriteStatus = .applied
            case .unchanged:
                self.rewriteStatus = .idle
            case .failed(let failure):
                self.rewriteStatus = .failed
                if let flag = LinkRouterCore.flag(for: failure) { self.flagRewrite(rule.id, flag) }
            }
            if let pending = self.pendingCommit {
                self.pendingCommit = nil
                self.choose(pending.browser, pending.remember, self.finalURL, self.state.chips, self.state.activeRewrite)
            }
        }
    }
}
