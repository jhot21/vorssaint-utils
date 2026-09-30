// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct LinkRouterSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var router = LinkRouterService.shared
    @AppStorage(DefaultsKey.linkRouterEnabled) private var enabled = false
    @AppStorage(DefaultsKey.linkRouterShowURLLine) private var showURLLine = true
    @AppStorage(DefaultsKey.linkRouterShowUndoToast) private var showUndoToast = true

    @State private var rules: [RoutingRule] = RuleStore.load()
    @State private var rulesUnreadable = RuleStore.isMalformed(UserDefaults.standard.string(forKey: DefaultsKey.linkRouterRules) ?? "")
    @State private var browsers: [BrowserInfo] = []
    @State private var hidden: Set<String> = Set(UserDefaults.standard.stringArray(forKey: DefaultsKey.linkRouterBrowserHidden) ?? [])
    @State private var editing: RoutingRule?
    @State private var testInput = ""
    @State private var testResult: String?
    @State private var restoreFailed = false
    @State private var testToken = 0
    private let evaluator = RegexEvaluator()

    private var text: LinkRouterFeatureStrings { FeatureStrings.linkRouter(l10n.language) }

    var body: some View {
        Form {
            Section {
                Toggle(text.enabledToggle, isOn: $enabled)
                    .onChange(of: enabled) { _, _ in LinkRouterService.shared.syncWithPreferences() }
                statusRow
            }
            Section(text.browsersHeader) {
                if browsers.isEmpty { Text(text.noBrowsers).foregroundStyle(.secondary) }
                ForEach(Array(browsers.enumerated()), id: \.element.id) { index, browser in
                    HStack {
                        Toggle(browser.name, isOn: Binding(
                            get: { !hidden.contains(browser.bundleID) },
                            set: { visible in
                                if visible { hidden.remove(browser.bundleID) } else { hidden.insert(browser.bundleID) }
                                BrowserCatalog.saveHidden(hidden)
                            }))
                        Spacer()
                        Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.borderless).disabled(index == 0)
                        Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.borderless).disabled(index == browsers.count - 1)
                    }
                }
                Button(text.rescan) { loadBrowsers() }
            }
            Section(text.rulesHeader) {
                if rulesUnreadable {
                    Label(text.rulesUnreadable, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                } else if rules.isEmpty {
                    Text(text.rulesEmpty).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                    ruleRow(rule, index: index)
                }
                Button(text.addRule) {
                    editing = RoutingRule(pattern: "", browserBundleID: browsers.first?.bundleID ?? "")
                }
                TextField(text.testLabel, text: $testInput)
                    .onChange(of: testInput) { _, _ in runTest() }
                    .onChange(of: rules) { _, _ in runTest() }
                if let testResult { Text(testResult).font(.caption).foregroundStyle(.secondary) }
            }
            Section(text.pickerHeader) {
                Toggle(text.showURLLine, isOn: $showURLLine)
                Toggle(text.showUndoToast, isOn: $showUndoToast)
            }
        }
        .sheet(item: $editing) { rule in
            RuleEditor(rule: rule, browsers: browsers, text: text) { saved in
                mutateRules { RuleEditing.save(saved, in: &$0) }
                editing = nil
            } onCancel: { editing = nil }
        }
        .onAppear {
            loadBrowsers()
            reloadRules()
            router.refreshStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            reloadRules()
            router.refreshStatus()
        }
        .onChange(of: router.status) { _, _ in restoreFailed = false }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            // The picker, the service and the undo toast write the rules while this page is open.
            let stored = RuleStore.load()
            if stored != rules { reloadRules() }
        }
    }

    // MARK: Status

    @ViewBuilder private var statusRow: some View {
        switch router.status {
        case .isDefault:
            Label(text.statusIsDefault, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .other(let bundleID):
            VStack(alignment: .leading, spacing: 6) {
                Label(bundleID.map { String(format: text.statusOtherFormat, appName($0)) } ?? text.statusNotDefault,
                      systemImage: "exclamationmark.triangle")
                if enabled { Text(text.statusNotDefault).font(.caption).foregroundStyle(.secondary) }
                makeDefaultButton
            }
        case .partial:
            VStack(alignment: .leading, spacing: 6) {
                Label(text.statusNotDefault, systemImage: "exclamationmark.triangle")
                makeDefaultButton
            }
        }
        if router.status == .isDefault {
            VStack(alignment: .leading, spacing: 2) {
                Button(text.restoreDefault) {
                    restoreFailed = false
                    LinkRouterService.shared.restoreDefault { result in
                        restoreFailed = result == .failed || result == .previousMissing
                    }
                }
                if restoreFailed { Text(text.restoreFailed).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    private var makeDefaultButton: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(text.makeDefault) {
                // The status row already says Vorssaint is not the default when this did not take.
                LinkRouterService.shared.makeDefault { _ in router.refreshStatus() }
            }
            .disabled(!router.canMakeDefault)
            if !router.canMakeDefault { Text(text.makeDefaultDevNote).font(.caption).foregroundStyle(.secondary) }
        }
    }

    // MARK: Rules

    private func ruleRow(_ rule: RoutingRule, index: Int) -> some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { value in mutateRules { RuleEditing.setEnabled(rule.id, value, in: &$0) } }))
                .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.pattern).font(.body.monospaced())
                HStack(spacing: 6) {
                    Text(browserName(rule.browserBundleID)).font(.caption)
                    if !installed(rule.browserBundleID) {
                        Text(text.browserMissing).font(.caption).foregroundStyle(.orange)
                    }
                    if let source = rule.sourceAppBundleID, !source.isEmpty {
                        Text(appName(source)).font(.caption).foregroundStyle(.secondary)
                    }
                    if rule.kind == .regex { Text(text.regexToggle).font(.caption).foregroundStyle(.secondary) }
                    switch rule.flag {
                    case .tooSlow?: Text(text.tooSlow).font(.caption).foregroundStyle(.red)
                    case .invalidRegex?: Text(text.invalidRegex).font(.caption).foregroundStyle(.red)
                    case nil: EmptyView()
                    }
                }
            }
            Spacer()
            Button { moveRule(rule.id, by: -1) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless).disabled(index == 0)
            Button { moveRule(rule.id, by: 1) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless).disabled(index == rules.count - 1)
            Button { editing = rule } label: { Image(systemName: "pencil") }.buttonStyle(.borderless)
            Button(role: .destructive) { mutateRules { RuleEditing.remove(rule.id, from: &$0) } } label: {
                Image(systemName: "trash")
            }.buttonStyle(.borderless)
        }
    }

    /// Every change reloads the stored list first, so rules added elsewhere while
    /// this page is open (picker, service, undo toast) are not overwritten.
    private func mutateRules(_ change: (inout [RoutingRule]) -> Void) {
        rules = RuleStore.mutate(.standard, change)
        rulesUnreadable = false
    }

    private func reloadRules() {
        rules = RuleStore.load()
        rulesUnreadable = RuleStore.isMalformed(UserDefaults.standard.string(forKey: DefaultsKey.linkRouterRules) ?? "")
    }

    private func moveRule(_ id: UUID, by offset: Int) {
        mutateRules { RuleEditing.move(id, by: offset, in: &$0) }
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard browsers.indices.contains(target) else { return }
        browsers.swapAt(index, target)
        BrowserCatalog.saveOrder(browsers.map(\.bundleID))
    }

    private func loadBrowsers() {
        browsers = BrowserCatalog.current().all
        hidden = Set(UserDefaults.standard.stringArray(forKey: DefaultsKey.linkRouterBrowserHidden) ?? [])
    }

    /// Uses the same matcher the router uses; the typed URL is never stored.
    /// Source-app-restricted rules cannot match here because the test has no source app.
    private func runTest() {
        testToken += 1
        let token = testToken
        var typed = testInput.trimmingCharacters(in: .whitespaces)
        if !typed.isEmpty, !typed.contains("://") { typed = "https://" + typed }
        guard let url = URL(string: typed), LinkCanonical.isWeb(url) else {
            testResult = nil
            return
        }
        RuleMatcher.firstMatch(url: url, sourceApp: nil, rules: rules, evaluator: evaluator) { result in
            guard token == testToken else { return }
            testResult = result.rule.map { String(format: text.testMatchFormat, browserName($0.browserBundleID)) }
                ?? text.testNoMatch
        }
    }

    private func installed(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    private func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path)
    }

    private func browserName(_ bundleID: String) -> String {
        browsers.first { $0.bundleID == bundleID }?.name ?? appName(bundleID)
    }
}

private struct RuleEditor: View {
    @State var rule: RoutingRule
    let browsers: [BrowserInfo]
    let text: LinkRouterFeatureStrings
    let onSave: (RoutingRule) -> Void
    let onCancel: () -> Void
    @State private var advanced = false
    @State private var showInvalid = false
    @State private var sourceApps: [BrowserInfo] = []

    var body: some View {
        Form {
            TextField(text.patternLabel, text: $rule.pattern, prompt: Text("github.com, *.example.com, docs.google.com/*"))
                .font(.body.monospaced())
            Picker(text.browserLabel, selection: $rule.browserBundleID) {
                ForEach(browsers) { Text($0.name).tag($0.bundleID) }
            }
            DisclosureGroup(text.advancedLabel, isExpanded: $advanced) {
                Toggle(text.regexToggle, isOn: Binding(get: { rule.kind == .regex },
                                                       set: { rule.kind = $0 ? .regex : .glob; showInvalid = false }))
                Picker(text.sourceAppLabel, selection: Binding(get: { rule.sourceAppBundleID ?? "" },
                                                               set: { rule.sourceAppBundleID = $0.isEmpty ? nil : $0 })) {
                    Text(text.anySourceApp).tag("")
                    ForEach(sourceApps) { Text($0.name).tag($0.bundleID) }
                }
            }
            if showInvalid { Text(text.invalidRegex).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button(text.cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button(text.save) {
                    var saved = rule
                    saved.pattern = saved.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard RuleEditing.canSave(saved) else { showInvalid = true; return }
                    onSave(saved)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(rule.pattern.trimmingCharacters(in: .whitespaces).isEmpty || rule.browserBundleID.isEmpty)
            }
        }
        .onChange(of: rule.pattern) { _, _ in showInvalid = false }
        .padding(20)
        .frame(minWidth: 420)
        .onAppear {
            advanced = rule.kind == .regex || rule.sourceAppBundleID != nil
            sourceApps = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .compactMap { app in app.bundleIdentifier.map { BrowserInfo(bundleID: $0, name: app.localizedName ?? $0) } }
                .sorted { $0.name < $1.name }
        }
    }
}
