// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import SwiftUI

/// Borderless panels refuse key status by default; the picker needs it for
/// its search field. Non-activating, so the app the link came from keeps
/// focus and nothing has to be restored afterwards.
private final class KeyablePickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

struct LinkPickerView: View {
    @ObservedObject var model: LinkPickerModel
    @ObservedObject private var l10n = L10n.shared
    @FocusState private var searchFocused: Bool

    private static let rowHeight: CGFloat = 36
    private static let rowSpacing: CGFloat = 2
    private static let headerHeight: CGFloat = 24

    private var text: LinkTransformFeatureStrings { FeatureStrings.linkTransform(l10n.language) }

    var body: some View {
        let browsers = model.state.visibleBrowsers
        let rewrites = model.state.visibleRewrites
        VStack(spacing: 0) {
            searchBar
            if model.mode != .off {
                Divider()
                urlLine
            }
            if !model.availableChips.isEmpty {
                Divider()
                chipRow
            }
            if !browsers.isEmpty || !rewrites.isEmpty {
                Divider()
                list(browsers: browsers, rewrites: rewrites)
            }
            if model.waiting > 0 {
                Text(String(format: FeatureStrings.linkRouter(l10n.language).waitingFormat, model.waiting))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(.thinMaterial, in: Capsule())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.bottom, 8)
            }
        }
        .frame(width: LinkPickerSupport.barWidth)
        .background(HUDBackdrop(cornerRadius: 22, contrast: .high))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .fixedSize()
        .id(model.instanceID)
        .onAppear { DispatchQueue.main.async { searchFocused = true } }
    }

    // MARK: Field and link

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "link")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            TextField(text.searchPlaceholder,
                      text: Binding(get: { model.state.query }, set: { model.setQuery($0) }))
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($searchFocused)
                .disableAutocorrection(true)
            if !model.state.query.isEmpty {
                Button { model.setQuery("") } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var urlLine: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(Self.attributed(LinkURLPreview.segments(mode: model.mode, result: model.result,
                                                          rewritten: model.rewritten)))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            switch model.rewriteStatus {
            case .pending:
                Text(text.rewritePending).font(.caption2).foregroundStyle(.secondary)
            case .failed:
                Label(text.rewriteFailed, systemImage: "exclamationmark.triangle")
                    .font(.caption2).foregroundStyle(.orange)
            case .idle, .applied:
                EmptyView()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private static func attributed(_ segments: [URLSegment]) -> AttributedString {
        var output = AttributedString()
        for segment in segments {
            var part = AttributedString(segment.text)
            switch segment.style {
            case .plain:
                break
            case .removed:
                part.strikethroughStyle = .single
                part.foregroundColor = Color.secondary.opacity(0.7)
            case .changed:
                part.foregroundColor = Color.accentColor
            }
            output.append(part)
        }
        return output
    }

    // MARK: Chips

    private var chipRow: some View {
        HStack(spacing: 5) {
            if model.availableChips.contains(.extract) {
                chip(.extract, label: text.extractChip, key: RewriteKeys.extractKey)
            }
            if model.availableChips.contains(.clean) {
                chip(.clean, label: text.cleanChip, key: RewriteKeys.cleanKey)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private func chip(_ chip: TransformChips, label: String, key: String) -> some View {
        let isOn = model.state.chips.contains(chip)
        return Button { model.toggleChip(chip) } label: {
            HStack(spacing: 5) {
                Text(label).font(.system(size: 10, weight: isOn ? .semibold : .regular))
                Text("\u{2318}\(key.uppercased())")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .opacity(0.7)
            }
            // Tinted, never filled, like the Command Bar's category chips.
            .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(isOn ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06)))
            .overlay(Capsule().strokeBorder(Color.accentColor.opacity(isOn ? 0.45 : 0), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Rows

    private func list(browsers: [BrowserInfo], rewrites: [RewriteRule]) -> some View {
        let rows = LinkPickerSupport.visibleRows(count: browsers.count + rewrites.count)
        let header = rewrites.isEmpty ? 0 : Self.headerHeight
        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Self.rowSpacing) {
                    ForEach(Array(browsers.enumerated()), id: \.element.id) { index, browser in
                        browserRow(browser, index: index).id("b-\(browser.id)")
                    }
                    if !rewrites.isEmpty {
                        Text(text.rewritesHeader.uppercased())
                            .font(.system(size: 9, weight: .bold)).tracking(0.5)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: Self.headerHeight - Self.rowSpacing, alignment: .bottom)
                            .padding(.horizontal, 8)
                        ForEach(Array(rewrites.enumerated()), id: \.element.id) { index, rule in
                            rewriteRow(rule, row: browsers.count + index).id("r-\(rule.id)")
                        }
                    }
                }
                .padding(8)
            }
            .frame(height: CGFloat(rows) * Self.rowHeight + CGFloat(max(rows - 1, 0)) * Self.rowSpacing + header + 16)
            .onChange(of: model.state.selected) { _, row in
                if row < browsers.count {
                    proxy.scrollTo("b-\(browsers[row].id)")
                } else if rewrites.indices.contains(row - browsers.count) {
                    proxy.scrollTo("r-\(rewrites[row - browsers.count].id)")
                }
            }
        }
    }

    private func browserRow(_ browser: BrowserInfo, index: Int) -> some View {
        let isSelected = index == model.state.selected
        return Button {
            model.commit(browser, remember: NSEvent.modifierFlags.contains(.option))
        } label: {
            HStack(spacing: 10) {
                Image(nsImage: Self.icon(for: browser)).resizable().frame(width: 24, height: 24)
                Text(browser.name).font(.system(size: 13)).lineLimit(1)
                Spacer(minLength: 8)
                if index < 9, model.state.query.isEmpty { badge("\(index + 1)") }
                returnGlyph(visible: isSelected)
            }
            .rowChrome(isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .onHover { if $0 { model.select(row: index) } }
        .accessibilityLabel(browser.name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func rewriteRow(_ rule: RewriteRule, row: Int) -> some View {
        let isSelected = row == model.state.selected
        let isActive = model.state.activeRewrite == rule.id
        return Button { model.toggleRewrite(rule.id) } label: {
            HStack(spacing: 10) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "arrow.triangle.branch")
                    .font(.system(size: 15))
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                    .frame(width: 24)
                Text(rule.name).font(.system(size: 13)).lineLimit(1)
                Spacer(minLength: 8)
                badge("\u{2318}\(rule.key.uppercased())")
                returnGlyph(visible: isSelected)
            }
            .rowChrome(isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .onHover { if $0 { model.select(row: row) } }
        .accessibilityLabel(rule.name)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }

    private func badge(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6).padding(.vertical, 2.5)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    private func returnGlyph(visible: Bool) -> some View {
        Image(systemName: "return")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            // Always laid out, only drawn on the selected row, so the rows do
            // not shift as the highlight moves.
            .opacity(visible ? 1 : 0)
    }

    private static func icon(for browser: BrowserInfo) -> NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleID) else {
            return NSImage(systemSymbolName: "globe", accessibilityDescription: nil) ?? NSImage()
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

private extension View {
    func rowChrome(isSelected: Bool) -> some View {
        self
            .padding(.horizontal, 9)
            .frame(height: 36)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : .clear))
    }
}

final class LinkPickerController {
    private var panel: KeyablePickerPanel?
    private var model: LinkPickerModel?
    private var hosting: NSHostingView<LinkPickerView>?
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private var changes: AnyCancellable?
    private var onCancel: () -> Void = {}

    func present(url: URL, browsers: [BrowserInfo], prefs: LinkTransformPrefs, urlLineMode: LinkURLLineMode,
                 replacer: RegexReplacing, waiting: Int, flagRewrite: @escaping (UUID, RoutingRule.Flag) -> Void,
                 onChoose: @escaping (BrowserInfo, Bool, URL, TransformChips, UUID?) -> Void,
                 onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
        // The router presents the current link again whenever another one is
        // queued behind it. That only changes the waiting count; a fresh model
        // would throw away what the person has typed or toggled, and drop an
        // open that is waiting on a rewrite.
        if let model, panel != nil, model.matches(url) {
            model.waiting = waiting
            model.choose = onChoose
            return
        }
        let model = LinkPickerModel(url: url, browsers: browsers, prefs: prefs, mode: urlLineMode,
                                    waiting: waiting, replacer: replacer, flagRewrite: flagRewrite)
        model.choose = onChoose
        self.model = model
        observe(model)
        if let panel, let hosting {
            // A queued link is a new decision: a fresh model, field and highlight.
            hosting.rootView = LinkPickerView(model: model)
            panel.makeKeyAndOrderFront(nil)
            // The hosting view has not re-evaluated the body yet, so its
            // fitting size is stale; measure on the next turn instead.
            DispatchQueue.main.async { [weak self] in self?.resizeInPlace() }
            return
        }
        let panel = KeyablePickerPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                       backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        let hosting = NSHostingView(rootView: LinkPickerView(model: model))
        panel.contentView = hosting
        self.hosting = hosting
        self.panel = panel
        placeBar()
        panel.makeKeyAndOrderFront(nil)
        installMonitors(for: panel)
    }

    func dismiss() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        clickMonitor = nil
        keyMonitor = nil
        changes = nil
        panel?.orderOut(nil)
        panel = nil
        hosting = nil
        model = nil
        onCancel = {}
    }

    private var screens: [(frame: CGRect, visible: CGRect)] {
        NSScreen.screens.map { (frame: $0.frame, visible: $0.visibleFrame) }
    }

    /// The panel's height follows what is shown (filtering, chips, a rewrite
    /// note), so every model change re-fits it.
    private func observe(_ model: LinkPickerModel) {
        changes = model.objectWillChange.sink { [weak self] _ in
            // Two turns: the first lets the published value land, the second
            // lets SwiftUI lay the new body out before it is measured.
            DispatchQueue.main.async { DispatchQueue.main.async { self?.resizeInPlace() } }
        }
    }

    private func placeBar() {
        guard let panel, let content = panel.contentView else { return }
        content.layoutSubtreeIfNeeded()
        panel.setFrame(LinkPickerPlacement.barFrame(size: content.fittingSize, pointer: NSEvent.mouseLocation,
                                                    screens: screens), display: true)
    }

    /// Keeps the panel where it is and only re-fits it.
    private func resizeInPlace() {
        guard let panel, let content = panel.contentView else { return }
        content.layoutSubtreeIfNeeded()
        panel.setFrame(LinkPickerPlacement.resized(panel.frame, to: content.fittingSize, screens: screens),
                       display: true)
    }

    private func installMonitors(for panel: KeyablePickerPanel) {
        // Clicking anywhere outside (another app's window) cancels. The
        // global monitor never sees clicks inside this panel.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.onCancel()
        }
        // The search field takes key events before the panel does, so the
        // shortcuts are intercepted here, ahead of it.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let self, let panel, event.window === panel, let model = self.model else { return event }
            // While a language composes a character, Return confirms the
            // candidate and the arrows walk it; composition always wins.
            if (panel.firstResponder as? NSTextView)?.hasMarkedText() == true { return event }
            if model.isCommitting { return nil }
            let command = event.modifierFlags.contains(.command)
            let characters = event.modifierFlags.contains(.option)
                ? event.charactersIgnoringModifiers : event.characters
            guard let action = LinkPickerKeys.action(
                keyCode: event.keyCode, command: command, characters: characters,
                fieldIsEmpty: model.state.query.isEmpty, keyMap: model.keyMap,
                rowCount: model.state.rowCount, browserCount: model.state.visibleBrowsers.count)
            else { return event }
            // A held key must not choose the next queued link the moment the
            // first repeat arrives; swallow repeats so they do not beep either.
            if event.isARepeat { return nil }
            self.perform(action, option: event.modifierFlags.contains(.option), model: model)
            return nil
        }
    }

    private func perform(_ action: LinkPickerAction, option: Bool, model: LinkPickerModel) {
        switch action {
        case .chooseDigit(let index):
            if let browser = model.state.browser(atDigit: index) { model.commit(browser, remember: option) }
        case .activateSelected:
            if case .open(let browser) = model.activate() { model.commit(browser, remember: option) }
        case .move(let delta):
            model.move(delta)
        case .escape:
            if model.escape() == .cancel { onCancel() }
        case .toggleChip(let chip):
            model.toggleChip(chip)
        case .toggleRewrite(let id):
            model.toggleRewrite(id)
        }
    }
}

/// "Rule added for github.com  Undo", dismissed on its own after a few seconds.
final class LinkRuleToastController {
    private var panel: NSPanel?
    private var dismissal: DispatchWorkItem?

    func show(message: String, undoTitle: String, onUndo: @escaping () -> Void) {
        dismiss()
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        let view = HStack(spacing: 12) {
            Text(message).font(.callout)
            Button(undoTitle) { [weak self] in onUndo(); self?.dismiss() }.buttonStyle(.link)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .fixedSize()
        panel.contentView = NSHostingView(rootView: view)
        let size = panel.contentView?.fittingSize ?? .zero
        let screens = NSScreen.screens.map { (frame: $0.frame, visible: $0.visibleFrame) }
        panel.setFrame(LinkPickerPlacement.frame(size: size, cursor: NSEvent.mouseLocation, screens: screens),
                       display: true)
        panel.orderFrontRegardless()
        self.panel = panel
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    func dismiss() {
        dismissal?.cancel()
        dismissal = nil
        panel?.orderOut(nil)
        panel = nil
    }
}
