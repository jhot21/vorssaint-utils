// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The Link Router's link-editing settings: which edits start on, redirect
/// wrapper rules, and regex rewrites. Every change reloads the stored value
/// first, so a stale copy of this page cannot overwrite newer data.
struct LinkTransformSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.linkRouterDefaultChips) private var defaultChips = 0
    @AppStorage(DefaultsKey.linkRouterGenericExtract) private var genericExtract = false

    @State private var added: [WrapperEntry] = WrapperStore.loadAdded()
    @State private var disabled: Set<String> = WrapperStore.loadDisabled()
    @State private var rewrites: [RewriteRule] = RewriteStore.load()
    @State private var editing: RewriteRule?
    @State private var newSite = ""
    @State private var newParameter = ""

    private var text: LinkTransformFeatureStrings { FeatureStrings.linkTransform(l10n.language) }
    private var routerText: LinkRouterFeatureStrings { FeatureStrings.linkRouter(l10n.language) }

    var body: some View {
        Group {
            Section(text.defaultChipsHeader) {
                Toggle(text.extractToggle, isOn: chipBinding(.extract))
                Toggle(text.cleanToggle, isOn: chipBinding(.clean))
                Toggle(text.genericExtractToggle, isOn: $genericExtract)
                Text(text.genericExtractNote).font(.caption).foregroundStyle(.secondary)
            }
            Section(text.wrappersHeader) {
                ForEach(RedirectWrappers.builtIn, id: \.token) { entry in
                    HStack {
                        Toggle("", isOn: Binding(get: { !disabled.contains(entry.token) },
                                                 set: { setBuiltIn(entry, enabled: $0) }))
                            .labelsHidden().fixedSize()
                        Text(entry.site).font(.body.monospaced()).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text(entry.parameter).font(.caption.monospaced()).foregroundStyle(.secondary)
                        Text(text.builtInBadge).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                if added.isEmpty {
                    Text(text.wrappersEmpty).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(added, id: \.token) { entry in
                    HStack {
                        Text(entry.site).font(.body.monospaced()).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text(entry.parameter).font(.caption.monospaced()).foregroundStyle(.secondary)
                        Button(role: .destructive) { removeWrapper(entry) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField(text.wrapperSiteLabel, text: $newSite).font(.body.monospaced())
                    TextField(text.wrapperParameterLabel, text: $newParameter).font(.body.monospaced())
                    Button(text.addWrapper) { addWrapper() }.disabled(newWrapper == nil)
                }
            }
            Section(text.rewritesSettingsHeader) {
                if rewrites.isEmpty { Text(text.rewritesEmpty).font(.caption).foregroundStyle(.secondary) }
                ForEach(rewrites) { rule in rewriteRow(rule) }
                Button {
                    editing = RewriteRule(name: "", find: "", replacement: "",
                                          key: RewriteKeys.suggestion(for: "", among: rewrites) ?? "")
                } label: {
                    Label(text.addRewrite, systemImage: "plus")
                }
            }
        }
        .sheet(item: $editing) { rule in
            RewriteEditor(rule: rule, all: rewrites, text: text, routerText: routerText) { saved in
                mutateRewrites { rules in
                    if let index = rules.firstIndex(where: { $0.id == saved.id }) {
                        rules[index] = saved
                    } else {
                        rules.append(saved)
                    }
                }
                editing = nil
            } onCancel: { editing = nil }
        }
    }

    // MARK: Default edits

    private func chipBinding(_ chip: TransformChips) -> Binding<Bool> {
        Binding(get: { TransformChips(rawValue: defaultChips).contains(chip) },
                set: { on in
                    var chips = TransformChips(rawValue: defaultChips)
                    if on { chips.insert(chip) } else { chips.remove(chip) }
                    defaultChips = chips.rawValue
                })
    }

    // MARK: Wrappers

    private var newWrapper: WrapperEntry? {
        let site = newSite.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !site.isEmpty, !site.contains(where: \.isWhitespace),
              let name = URLCleaning.parameterName(from: newParameter) else { return nil }
        let entry = WrapperEntry(site: site, parameter: name)
        let known = Set(RedirectWrappers.builtIn.map(\.token)).union(added.map(\.token))
        return known.contains(entry.token) ? nil : entry
    }

    private func setBuiltIn(_ entry: WrapperEntry, enabled: Bool) {
        var tokens = WrapperStore.loadDisabled()
        if enabled { tokens.remove(entry.token) } else { tokens.insert(entry.token) }
        WrapperStore.saveDisabled(tokens)
        disabled = tokens
    }

    private func addWrapper() {
        guard let entry = newWrapper else { return }
        var all = WrapperStore.loadAdded()
        all.append(entry)
        WrapperStore.saveAdded(all)
        added = all
        newSite = ""
        newParameter = ""
    }

    private func removeWrapper(_ entry: WrapperEntry) {
        var all = WrapperStore.loadAdded()
        all.removeAll { $0.token == entry.token }
        WrapperStore.saveAdded(all)
        added = all
    }

    // MARK: Rewrites

    private func rewriteRow(_ rule: RewriteRule) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { rule.isEnabled }, set: { on in
                mutateRewrites { rules in
                    guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
                    rules[index].isEnabled = on
                    if on { rules[index].flag = nil }
                }
            }))
            .labelsHidden().fixedSize()
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name).lineLimit(1)
                HStack(spacing: 6) {
                    Text(rule.site ?? "*").font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                    switch rule.flag {
                    case .tooSlow?: Text(routerText.tooSlow).font(.caption).foregroundStyle(.red).lineLimit(1)
                    case .invalidRegex?: Text(routerText.invalidRegex).font(.caption).foregroundStyle(.red).lineLimit(1)
                    case nil: EmptyView()
                    }
                }
            }
            Spacer(minLength: 8)
            Text("\u{2318}\(rule.key.uppercased())")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 6).padding(.vertical, 2.5)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.06)))
            Button { editing = rule } label: { Image(systemName: "pencil") }.buttonStyle(.borderless)
            Button(role: .destructive) {
                mutateRewrites { $0.removeAll { $0.id == rule.id } }
            } label: { Image(systemName: "trash") }
            .buttonStyle(.borderless)
        }
    }

    private func mutateRewrites(_ change: (inout [RewriteRule]) -> Void) {
        var all = RewriteStore.load()
        change(&all)
        RewriteStore.save(all)
        rewrites = all
    }
}

private struct RewriteEditor: View {
    @State var rule: RewriteRule
    let all: [RewriteRule]
    let text: LinkTransformFeatureStrings
    let routerText: LinkRouterFeatureStrings
    let onSave: (RewriteRule) -> Void
    let onCancel: () -> Void
    @State private var testInput = ""
    @State private var testResult: String?
    @State private var testToken = 0
    private let evaluator = RegexEvaluator()

    private static let labelWidth: CGFloat = 150

    private var keyIsValid: Bool { RewriteKeys.isValid(rule.key, among: all, editing: rule.id) }
    private var regexCompiles: Bool { (try? NSRegularExpression(pattern: rule.find)) != nil }
    private var canSave: Bool {
        !rule.name.trimmingCharacters(in: .whitespaces).isEmpty && !rule.find.isEmpty && regexCompiles && keyIsValid
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            row(text.rewriteNameLabel) {
                TextField("", text: $rule.name).labelsHidden()
            }
            row(text.rewriteSiteLabel) {
                TextField("", text: Binding(get: { rule.site ?? "" },
                                            set: { rule.site = $0.isEmpty ? nil : $0 }),
                          prompt: Text(verbatim: "*.youtube.com"))
                    .labelsHidden().font(.body.monospaced())
            }
            row(text.rewriteFindLabel) {
                TextField("", text: $rule.find).labelsHidden().font(.body.monospaced())
            }
            row(text.rewriteReplaceLabel) {
                TextField("", text: $rule.replacement).labelsHidden().font(.body.monospaced())
            }
            row(text.rewriteKeyLabel) {
                TextField("", text: $rule.key).labelsHidden().frame(width: 40)
                Text("\u{2318}\(rule.key.uppercased())").font(.caption).foregroundStyle(.secondary)
            }
            if !keyIsValid { Text(text.rewriteKeyInvalid).font(.caption).foregroundStyle(.red) }
            if !rule.find.isEmpty, !regexCompiles {
                Text(routerText.invalidRegex).font(.caption).foregroundStyle(.red)
            }
            row(text.rewriteTestLabel) {
                TextField("", text: $testInput, prompt: Text(verbatim: "https://www.youtube.com/watch?v=..."))
                    .labelsHidden().font(.body.monospaced())
            }
            if let testResult { Text(testResult).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            HStack {
                Spacer()
                Button(routerText.cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button(routerText.save) {
                    var saved = rule
                    saved.name = saved.name.trimmingCharacters(in: .whitespaces)
                    saved.site = saved.site?.trimmingCharacters(in: .whitespaces)
                    // Saving a rule is the way to fix a flagged one.
                    saved.flag = nil
                    onSave(saved)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onChange(of: testInput) { _, _ in runTest() }
        .onChange(of: rule.find) { _, _ in runTest() }
        .onChange(of: rule.replacement) { _, _ in runTest() }
        .onChange(of: rule.site) { _, _ in runTest() }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label).frame(width: Self.labelWidth, alignment: .trailing)
            content()
        }
    }

    /// Stale answers are dropped: the evaluator may take its whole deadline,
    /// and the field keeps changing meanwhile.
    private func runTest() {
        testToken += 1
        let token = testToken
        let input = testInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, regexCompiles, let url = URL(string: input), LinkCanonical.isWeb(url) else {
            testResult = nil
            return
        }
        var probe = rule
        probe.isEnabled = true
        probe.flag = nil
        guard !LinkRewrite.applicable([probe], to: url).isEmpty else {
            testResult = text.rewriteTestNoChange
            return
        }
        LinkRewrite.apply(probe, to: url, replacer: evaluator) { outcome in
            guard token == testToken else { return }
            switch outcome {
            case .rewritten(let link): testResult = String(format: text.rewriteTestResultFormat, link.absoluteString)
            case .unchanged: testResult = text.rewriteTestNoChange
            case .failed: testResult = text.rewriteTestFailed
            }
        }
    }
}
