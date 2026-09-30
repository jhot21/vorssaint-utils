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
    @State private var declined = false
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
                if let testResult { Text(testResult).font(.caption).foregroundStyle(.secondary) }
            }
            Section(text.pickerHeader) {
                Toggle(text.showURLLine, isOn: $showURLLine)
                Toggle(text.showUndoToast, isOn: $showUndoToast)
            }
        }
        .sheet(item: $editing) { rule in
            RuleEditor(rule: rule, browsers: browsers, text: text) { saved in
                if let index = rules.firstIndex(where: { $0.id == saved.id }) { rules[index] = saved } else { rules.append(saved) }
                RuleStore.save(rules)
                rulesUnreadable = false
                editing = nil
            } onCancel: { editing = nil }
        }
        .onAppear {
            loadBrowsers()
            rules = RuleStore.load()
            rulesUnreadable = RuleStore.isMalformed(UserDefaults.standard.string(forKey: DefaultsKey.linkRouterRules) ?? "")
            router.refreshStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            rules = RuleStore.load()
            router.refreshStatus()
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
            Button(text.restoreDefault) {
                LinkRouterService.shared.restoreDefault { _ in }
            }
        }
    }

    private var makeDefaultButton: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(text.makeDefault) {
                LinkRouterService.shared.makeDefault { result in declined = result == .failed }
            }
            .disabled(!router.canMakeDefault)
            if !router.canMakeDefault { Text(text.makeDefaultDevNote).font(.caption).foregroundStyle(.secondary) }
            if declined { Text(text.restoreFailed).font(.caption).foregroundStyle(.secondary) }
        }
    }

    // MARK: Rules

    private func ruleRow(_ rule: RoutingRule, index: Int) -> some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { rules[index].isEnabled = $0; rules[index].flag = $0 ? nil : rules[index].flag; RuleStore.save(rules) }))
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
            Button { moveRule(index, by: -1) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless).disabled(index == 0)
            Button { moveRule(index, by: 1) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless).disabled(index == rules.count - 1)
            Button { editing = rule } label: { Image(systemName: "pencil") }.buttonStyle(.borderless)
            Button(role: .destructive) { rules.remove(at: index); RuleStore.save(rules) } label: {
                Image(systemName: "trash")
            }.buttonStyle(.borderless)
        }
    }

    private func moveRule(_ index: Int, by offset: Int) {
        let target = index + offset
        guard rules.indices.contains(target) else { return }
        rules.swapAt(index, target)
        RuleStore.save(rules)
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
    private func runTest() {
        guard let url = URL(string: testInput.trimmingCharacters(in: .whitespaces)), LinkCanonical.isWeb(url) else {
            testResult = nil
            return
        }
        RuleMatcher.firstMatch(url: url, sourceApp: nil, rules: rules, evaluator: evaluator) { result in
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
                                                       set: { rule.kind = $0 ? .regex : .glob; rule.flag = nil }))
                Picker(text.sourceAppLabel, selection: Binding(get: { rule.sourceAppBundleID ?? "" },
                                                               set: { rule.sourceAppBundleID = $0.isEmpty ? nil : $0 })) {
                    Text(text.anySourceApp).tag("")
                    ForEach(sourceApps) { Text($0.name).tag($0.bundleID) }
                }
            }
            HStack {
                Spacer()
                Button(text.cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button(text.save) {
                    var saved = rule
                    saved.pattern = saved.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
                    saved.isEnabled = true
                    onSave(saved)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(rule.pattern.trimmingCharacters(in: .whitespaces).isEmpty || rule.browserBundleID.isEmpty)
            }
        }
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
