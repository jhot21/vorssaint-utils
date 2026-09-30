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
    @State private var draggingBrowser: String?
    @State private var draggingRule: String?
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
                ForEach(browsers) { browser in
                    ReorderableRow(item: browser, id: { $0.bundleID }, items: $browsers, dragging: $draggingBrowser,
                                   onCommit: { BrowserCatalog.saveOrder($0) }) {
                        browserRow(browser)
                    }
                }
                if !browsers.isEmpty { reorderHint }
                Button(text.rescan) { loadBrowsers() }
            }
            Section(text.rulesHeader) {
                if rulesUnreadable {
                    Label(text.rulesUnreadable, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                } else if rules.isEmpty {
                    Text(text.rulesEmpty).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(rules) { rule in
                    ReorderableRow(item: rule, id: { $0.id.uuidString }, items: $rules, dragging: $draggingRule,
                                   onCommit: { ids in
                                       let order = ids.compactMap(UUID.init(uuidString:))
                                       mutateRules { RuleEditing.reorder(order, in: &$0) }
                                   }) {
                        ruleRow(rule)
                    }
                }
                if rules.count > 1 { reorderHint }
                Button(text.addRule) {
                    editing = RoutingRule(pattern: "", browserBundleID: browsers.first?.bundleID ?? "")
                }
                TextField("", text: $testInput, prompt: Text(text.testLabel))
                    .labelsHidden()
                    .accessibilityLabel(text.testLabel)
                    .onChange(of: testInput) { _, _ in runTest() }
                    .onChange(of: rules) { _, _ in runTest() }
                if let testResult { Text(testResult).font(.caption).foregroundStyle(.secondary) }
            }
            Section(text.pickerHeader) {
                Toggle(text.showURLLine, isOn: $showURLLine)
                Toggle(text.showUndoToast, isOn: $showUndoToast)
            }
        }
        .onDrop(of: [.text], delegate: ReorderDropZone(
            isDragging: { draggingBrowser != nil || draggingRule != nil },
            finish: { draggingBrowser = nil; draggingRule = nil }))
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
            // Safety net: a drag that ended somewhere unexpected must not leave a row dimmed.
            draggingBrowser = nil
            draggingRule = nil
            reloadRules()
            router.refreshStatus()
        }
        .onChange(of: router.status) { _, _ in restoreFailed = false }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            // The picker, the service and the undo toast write the rules while this page is open.
            // Reorders are saved as they happen, so a reload never undoes one.
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
                        restoreFailed = result == .failed || result == .previousMissing || result == .noPrevious
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
            .disabled(!router.canMakeDefault || !enabled)
            if !router.canMakeDefault { Text(text.makeDefaultDevNote).font(.caption).foregroundStyle(.secondary) }
        }
    }

    // MARK: Rules

    private var reorderHint: some View {
        Text(FeatureStrings.notchEditor(l10n.language).reorderHint).font(.caption).foregroundStyle(.secondary)
    }

    private func browserRow(_ browser: BrowserInfo) -> some View {
        HStack(spacing: 8) {
            PanelDragHandle()
            Toggle(isOn: Binding(
                get: { !hidden.contains(browser.bundleID) },
                set: { visible in
                    if visible { hidden.remove(browser.bundleID) } else { hidden.insert(browser.bundleID) }
                    BrowserCatalog.saveHidden(hidden)
                })) {
                Text(browser.name).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contextMenu {
            Button(FeatureStrings.clipboard(l10n.language).moveUp) { moveBrowser(browser.bundleID, by: -1) }
            Button(FeatureStrings.clipboard(l10n.language).moveDown) { moveBrowser(browser.bundleID, by: 1) }
        }
    }

    private func ruleRow(_ rule: RoutingRule) -> some View {
        HStack(spacing: 8) {
            PanelDragHandle()
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { value in mutateRules { RuleEditing.setEnabled(rule.id, value, in: &$0) } }))
                .labelsHidden()
                .fixedSize()
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.pattern).font(.body.monospaced()).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(browserName(rule.browserBundleID)).font(.caption).lineLimit(1)
                    if !installed(rule.browserBundleID) {
                        Text(text.browserMissing).font(.caption).foregroundStyle(.orange)
                    }
                    if let source = rule.sourceAppBundleID, !source.isEmpty {
                        Text(appName(source)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if rule.kind == .regex { Text(text.regexToggle).font(.caption).foregroundStyle(.secondary) }
                    switch rule.flag {
                    case .tooSlow?: Text(text.tooSlow).font(.caption).foregroundStyle(.red).lineLimit(1)
                    case .invalidRegex?: Text(text.invalidRegex).font(.caption).foregroundStyle(.red).lineLimit(1)
                    case nil: EmptyView()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { editing = rule } label: { Image(systemName: "pencil") }
                .buttonStyle(.borderless).fixedSize()
            Button(role: .destructive) { mutateRules { RuleEditing.remove(rule.id, from: &$0) } } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless).fixedSize()
        }
        .contextMenu {
            Button(FeatureStrings.clipboard(l10n.language).moveUp) { moveRule(rule.id, by: -1) }
            Button(FeatureStrings.clipboard(l10n.language).moveDown) { moveRule(rule.id, by: 1) }
        }
    }

    /// Every change reloads the stored list first, so rules added elsewhere while
    /// this page is open (picker, service, undo toast) are not overwritten.
    private func mutateRules(_ change: (inout [RoutingRule]) -> Void) {
        rules = RuleStore.mutate(.standard, change)
        rulesUnreadable = false
    }

    private func reloadRules() {
        draggingRule = nil
        rules = RuleStore.load()
        rulesUnreadable = RuleStore.isMalformed(UserDefaults.standard.string(forKey: DefaultsKey.linkRouterRules) ?? "")
    }

    private func moveRule(_ id: UUID, by offset: Int) {
        mutateRules { RuleEditing.move(id, by: offset, in: &$0) }
    }

    private func moveBrowser(_ bundleID: String, by offset: Int) {
        guard let index = browsers.firstIndex(where: { $0.bundleID == bundleID }),
              browsers.indices.contains(index + offset) else { return }
        browsers.swapAt(index, index + offset)
        BrowserCatalog.saveOrder(browsers.map(\.bundleID))
    }

    private func loadBrowsers() {
        draggingBrowser = nil
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
    @State private var advanced: Bool
    @State private var showInvalid = false
    @State private var sourceApps: [BrowserInfo] = []

    init(rule: RoutingRule, browsers: [BrowserInfo], text: LinkRouterFeatureStrings,
         onSave: @escaping (RoutingRule) -> Void, onCancel: @escaping () -> Void) {
        _rule = State(initialValue: rule)
        self.browsers = browsers
        self.text = text
        self.onSave = onSave
        self.onCancel = onCancel
        _advanced = State(initialValue: rule.kind == .regex || rule.sourceAppBundleID != nil)
    }

    private static let labelWidth: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            editorRow(text.patternLabel) {
                TextField("", text: $rule.pattern, prompt: Text(verbatim: "github.com, *.example.com, docs.google.com/*"))
                    .labelsHidden()
                    .font(.body.monospaced())
            }
            editorRow(text.browserLabel) {
                Picker("", selection: $rule.browserBundleID) {
                    ForEach(browsers) { Text($0.name).tag($0.bundleID) }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // The disclosure sits in the same spot collapsed or expanded; the
            // extra rows appear below it so nothing above moves.
            Button {
                advanced.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(advanced ? 90 : 0))
                        .frame(width: 12)
                    Text(text.advancedLabel)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if advanced {
                editorRow(text.regexToggle) {
                    Toggle("", isOn: Binding(get: { rule.kind == .regex },
                                             set: { rule.kind = $0 ? .regex : .glob; showInvalid = false }))
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                editorRow(text.sourceAppLabel) {
                    Picker("", selection: Binding(get: { rule.sourceAppBundleID ?? "" },
                                                  set: { rule.sourceAppBundleID = $0.isEmpty ? nil : $0 })) {
                        Text(text.anySourceApp).tag("")
                        ForEach(sourceApps) { Text($0.name).tag($0.bundleID) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
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
        .frame(width: 460)
        .onAppear {
            sourceApps = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .compactMap { app in app.bundleIdentifier.map { BrowserInfo(bundleID: $0, name: app.localizedName ?? $0) } }
                .sorted { $0.name < $1.name }
        }
    }

    private func editorRow<Control: View>(_ label: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .frame(width: Self.labelWidth, alignment: .leading)
            control()
                .accessibilityLabel(label)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
