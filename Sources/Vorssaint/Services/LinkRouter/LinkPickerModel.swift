// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

final class LinkPickerModel: ObservableObject {
    enum RewriteStatus: Equatable { case idle, pending, applied, failed }
    enum UnshortenStatus: Equatable { case idle, pending, resolved, noRedirect, failed }

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
    @Published private(set) var unshortenStatus: UnshortenStatus = .idle
    @Published private(set) var availableChips: TransformChips = []
    /// Set once a browser is chosen; later keys and clicks are ignored so one
    /// link can never open twice.
    private(set) var isCommitting = false
    var choose: (BrowserInfo, Bool, URL, TransformChips, UUID?) -> Void = { _, _, _, _, _ in }

    private let replacer: RegexReplacing
    private let flagRewrite: (UUID, RoutingRule.Flag) -> Void
    private let unshortener: LinkUnshortening?
    private var transformToken = 0
    private var rewriteToken = 0
    private var pendingCommit: (browser: BrowserInfo, remember: Bool)?

    init(url: URL, browsers: [BrowserInfo], prefs: LinkTransformPrefs, mode: LinkURLLineMode,
         waiting: Int, replacer: RegexReplacing, flagRewrite: @escaping (UUID, RoutingRule.Flag) -> Void,
         unshortener: LinkUnshortening? = nil) {
        self.url = url
        self.prefs = prefs
        self.mode = mode
        self.waiting = waiting
        self.replacer = replacer
        self.flagRewrite = flagRewrite
        self.unshortener = unshortener
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

    /// A step still running when a browser is chosen is waited for. The
    /// evaluator's own deadline and the unshortener's total budget bound the
    /// wait, after which the link opens without that step.
    func commit(_ browser: BrowserInfo, remember: Bool) {
        guard !isCommitting else { return }
        isCommitting = true
        if isWorking {
            pendingCommit = (browser, remember)
        } else {
            choose(browser, remember, finalURL, state.chips, state.activeRewrite)
        }
    }

    private var isWorking: Bool { unshortenStatus == .pending || rewriteStatus == .pending }

    private func flushPendingCommit() {
        guard let pending = pendingCommit, !isWorking else { return }
        pendingCommit = nil
        choose(pending.browser, pending.remember, finalURL, state.chips, state.activeRewrite)
    }

    private func recompute() {
        transformToken += 1
        let token = transformToken
        rewriteToken += 1
        rewritten = nil
        rewriteStatus = .idle
        let settings = prefs.settings
        let extractedURL = LinkTransform.extract(url, chips: state.chips, settings: settings).url
        guard unshortener != nil,
              LinkPipeline.needsLookup(extractedURL, chips: state.chips, settings: settings) else {
            unshortenStatus = .idle
            show(LinkTransform.apply(url, chips: state.chips, settings: settings), resolved: nil)
            startRewrite()
            return
        }
        // Until the lookup answers, the link is shown as far as Extract took it,
        // and no rewrite runs on the short link.
        unshortenStatus = .pending
        show(LinkTransform.extract(url, chips: state.chips, settings: settings), resolved: nil)
        LinkPipeline.run(url, chips: state.chips, settings: settings, unshortener: unshortener) { [weak self] outcome in
            guard let self, self.transformToken == token else { return }
            switch outcome.unshorten {
            case .resolved: self.unshortenStatus = .resolved
            case .noRedirect: self.unshortenStatus = .noRedirect
            case .failed: self.unshortenStatus = .failed
            // Unreachable while the guard above and the pipeline share
            // `needsLookup`; if they ever drift, show nothing rather than a
            // failure for a lookup that never ran.
            case .notRun: self.unshortenStatus = .idle
            }
            let destination = outcome.result.unshortenedFrom == nil ? nil : outcome.result.beforeClean
            self.show(outcome.result, resolved: destination)
            self.startRewrite()
        }
    }

    private func show(_ new: TransformResult, resolved: URL?) {
        result = new
        var offered = LinkTransform.available(for: url, selected: state.chips, settings: prefs.settings,
                                              resolved: resolved, unshortenPending: unshortenStatus == .pending)
        if unshortener == nil { offered.remove(.unshorten) }
        availableChips = offered
        // A rewrite runs on the link as edited, so its site scope is judged
        // against that link, the same way an auto-open rule judges it. While a
        // lookup is pending none is offered: the destination is not known.
        state.rewrites = unshortenStatus == .pending ? [] : LinkRewrite.applicable(prefs.rewrites, to: new.url)
        if let id = state.activeRewrite, !state.rewrites.contains(where: { $0.id == id }) {
            state.activeRewrite = nil
        }
    }

    private func startRewrite() {
        rewriteToken += 1
        let token = rewriteToken
        rewritten = nil
        guard let id = state.activeRewrite, let rule = state.rewrites.first(where: { $0.id == id }) else {
            rewriteStatus = .idle
            flushPendingCommit()
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
            self.flushPendingCommit()
        }
    }
}
