// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreServices

/// AppKit side of the link router: receives the URL Apple event, implements
/// the core's environment with NSWorkspace, and owns the default-browser
/// lifecycle. Everything runs on the main thread.
final class LinkRouterService: NSObject, ObservableObject, LinkRouterEnvironment {
    static let shared = LinkRouterService()

    @Published private(set) var status: DefaultBrowserManager.Status = .other(nil)

    private let defaults = UserDefaults.standard
    private let manager = DefaultBrowserManager()
    private let picker = LinkPickerController()
    private let toast = LinkRuleToastController()
    private lazy var core = LinkRouterCore(environment: self, evaluator: RegexEvaluator(),
                                           selfBundleID: BrowserCatalog.ownBundleID)
    private var wasOn = false
    private var isRestoring = false

    private override init() { super.init() }

    // MARK: Apple event

    /// Registered before `app.run()` (see main.swift): a click that launches
    /// the app delivers its event before applicationDidFinishLaunching, and
    /// installing our own handler is also what keeps AppKit's internal one
    /// from forwarding the same URL to the app delegate (no double open).
    func installEventHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let raw = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        // The sender is a hint only: helper processes can hide the real app,
        // and the process may already be gone. Unknown means nil.
        var sender: String?
        if let pid = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value, pid > 0 {
            sender = NSRunningApplication(processIdentifier: pid_t(pid))?.bundleIdentifier
        }
        route(LinkRequest(urls: [url], senderBundleID: sender))
    }

    /// Files handed to the app (html, xhtml). They open in an explicit
    /// browser, never through a bare open, which LaunchServices would hand
    /// straight back to Vorssaint.
    func openDocuments(_ urls: [URL]) {
        for url in urls {
            guard url.isFileURL else { LinkOpener.open(url); continue }
            guard let bundleID = core.fallbackBundleID(),
                  let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                NSSound.beep()
                continue
            }
            NSWorkspace.shared.open([url], withApplicationAt: appURL,
                                    configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
        }
    }

    func route(_ request: LinkRequest) {
        core.route(request)
    }

    // MARK: Lifecycle

    /// Called from FeatureRuntime at launch and whenever the feature or its
    /// toggle changes.
    func syncWithPreferences() {
        let on = isFeatureOn
        core.setReady()
        if !on {
            if wasOn { core.stopAll() }
            // One chain at a time: it can raise a system confirmation dialog,
            // and a second sync must not stack another or re-prompt.
            if !isRestoring {
                isRestoring = true
                restoreDefault { [weak self] result in
                    DispatchQueue.main.async {
                        self?.isRestoring = false
                        self?.finishRestore(result)
                    }
                }
            }
        }
        wasOn = on
        refreshStatus()
    }

    private func finishRestore(_ result: DefaultBrowserManager.RestoreResult) {
        if result == .failed || result == .previousMissing {
            QuickToolHUD.show(icon: "exclamationmark.triangle",
                              message: FeatureStrings.linkRouter(L10n.shared.language).restoreFailed)
        }
        refreshStatus()
    }

    func stop() {
        core.stopAll()
        wasOn = false
    }

    func refreshStatus() {
        status = manager.status
    }

    var canMakeDefault: Bool { manager.canMakeDefault }

    func makeDefault(completion: @escaping (DefaultBrowserManager.MakeDefaultResult) -> Void) {
        manager.makeDefault { [weak self] result in
            self?.refreshStatus()
            completion(result)
        }
    }

    /// Hands http and https back to the browser that was default before, if
    /// Vorssaint currently owns them. Used by turning the feature off, by the
    /// hub removing it, and by the complete uninstall.
    func restoreDefault(completion: @escaping (DefaultBrowserManager.RestoreResult) -> Void) {
        manager.restorePrevious { [weak self] result in
            self?.refreshStatus()
            completion(result)
        }
    }

    func removeRule(id: UUID) {
        RuleStore.save(RuleStore.load(defaults).filter { $0.id != id }, to: defaults)
    }

    // MARK: LinkRouterEnvironment

    var isFeatureOn: Bool {
        AppFeature.linkRouter.isAvailable && defaults.bool(forKey: DefaultsKey.linkRouterEnabled)
    }

    var rules: [RoutingRule] { RuleStore.load(defaults) }

    var visibleBrowsers: [BrowserInfo] { BrowserCatalog.current(defaults: defaults).visible }

    var previousDefaultBundleID: String? { manager.effectiveFallbackBundleID }

    var isScreenLocked: Bool {
        let locked = (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
        return locked || CGDisplayIsAsleep(CGMainDisplayID()) != 0
    }

    func isInstalled(bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    func open(_ url: URL, inBundleID bundleID: String) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            noBrowserAvailable(for: url)
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
    }

    func openNonWeb(_ url: URL) {
        LinkOpener.openNonWeb(url)
    }

    func noBrowserAvailable(for url: URL) {
        NSSound.beep()
    }

    func showPicker(for url: URL, waiting: Int) {
        let browsers = visibleBrowsers
        picker.present(
            url: url, browsers: browsers, waiting: waiting,
            showURLLine: defaults.bool(forKey: DefaultsKey.linkRouterShowURLLine),
            onChoose: { [weak self] browser, saveRule in
                self?.core.pickerDidChoose(url, bundleID: browser.bundleID, saveRule: saveRule)
            },
            onCancel: { [weak self] in self?.core.pickerDidCancel(url) })
    }

    func hidePicker() {
        picker.dismiss()
    }

    func addRule(_ rule: RoutingRule) {
        var all = RuleStore.load(defaults)
        all.insert(rule, at: 0)
        RuleStore.save(all, to: defaults)
        guard defaults.bool(forKey: DefaultsKey.linkRouterShowUndoToast) else { return }
        let text = FeatureStrings.linkRouter(L10n.shared.language)
        toast.show(message: String(format: text.ruleAddedFormat, rule.pattern), undoTitle: text.undo) { [weak self] in
            self?.removeRule(id: rule.id)
        }
    }

    func flagRule(id: UUID, flag: RoutingRule.Flag) {
        var all = RuleStore.load(defaults)
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        all[index].flag = flag
        all[index].isEnabled = false
        RuleStore.save(all, to: defaults)
    }
}
