// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Borderless panels refuse key status by default; the picker needs it for
/// the number keys, Return and Escape. Non-activating, so the app the link
/// came from keeps focus and nothing has to be restored afterwards.
private final class KeyablePickerPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) != true { super.keyDown(with: event) }
    }
}

final class LinkPickerModel: ObservableObject {
    @Published var url: URL
    @Published var browsers: [BrowserInfo]
    @Published var waiting: Int
    @Published var showURLLine: Bool
    /// The row Return chooses. Arrow keys and hover move it.
    @Published var selectedIndex = 0
    var choose: (BrowserInfo, Bool) -> Void = { _, _ in }
    init(url: URL, browsers: [BrowserInfo], waiting: Int, showURLLine: Bool) {
        self.url = url; self.browsers = browsers; self.waiting = waiting; self.showURLLine = showURLLine
    }
}

struct LinkPickerView: View {
    @ObservedObject var model: LinkPickerModel
    @ObservedObject private var l10n = L10n.shared

    private static let rowHeight: CGFloat = 36
    private static let rowSpacing: CGFloat = 2

    var body: some View {
        let rows = LinkPickerSupport.visibleRows(count: model.browsers.count)
        VStack(alignment: .leading, spacing: 8) {
            if model.showURLLine {
                Text(Self.summary(of: model.url))
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail)
                    .padding(.horizontal, 9)
            }
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: Self.rowSpacing) {
                        ForEach(Array(model.browsers.enumerated()), id: \.element.id) { index, browser in
                            row(browser, index: index)
                                .id(browser.id)
                        }
                    }
                }
                .frame(height: CGFloat(rows) * Self.rowHeight + CGFloat(max(rows - 1, 0)) * Self.rowSpacing)
                .onChange(of: model.selectedIndex) { _, index in
                    guard model.browsers.indices.contains(index) else { return }
                    proxy.scrollTo(model.browsers[index].id)
                }
            }
            if model.waiting > 0 {
                Text(String(format: FeatureStrings.linkRouter(l10n.language).waitingFormat, model.waiting))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.horizontal, 9)
            }
        }
        .padding(8)
        .frame(width: 260)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .fixedSize()
    }

    private func row(_ browser: BrowserInfo, index: Int) -> some View {
        let isSelected = index == model.selectedIndex
        return Button {
            model.choose(browser, NSEvent.modifierFlags.contains(.option))
        } label: {
            HStack(spacing: 10) {
                Image(nsImage: Self.icon(for: browser))
                    .resizable().frame(width: 24, height: 24)
                Text(browser.name).font(.system(size: 13)).lineLimit(1)
                Spacer(minLength: 8)
                if index < 9 {
                    Text("\(index + 1)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2.5)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.primary.opacity(0.06)))
                }
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    // Always laid out, only drawn on the selected row, so the
                    // rows do not shift as the highlight moves.
                    .opacity(isSelected ? 1 : 0)
            }
            .padding(.horizontal, 9)
            .frame(height: Self.rowHeight)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { model.selectedIndex = index }
        }
        .accessibilityLabel(browser.name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private static func icon(for browser: BrowserInfo) -> NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleID) else {
            return NSImage(systemSymbolName: "globe", accessibilityDescription: nil) ?? NSImage()
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// Host plus the start of the path; never the query string, which can
    /// carry tokens that do not belong on screen.
    private static func summary(of url: URL) -> String {
        (url.host ?? "") + (url.path == "/" ? "" : url.path)
    }
}

final class LinkPickerController {
    private var panel: KeyablePickerPanel?
    private var model: LinkPickerModel?
    private var clickMonitor: Any?
    private var onCancel: () -> Void = {}

    func present(url: URL, browsers: [BrowserInfo], waiting: Int, showURLLine: Bool,
                 onChoose: @escaping (BrowserInfo, Bool) -> Void, onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
        if let model {
            model.url = url; model.browsers = browsers; model.waiting = waiting; model.showURLLine = showURLLine
            // A queued link is a new decision: start from the top again.
            model.selectedIndex = 0
            model.choose = onChoose
            panel?.makeKeyAndOrderFront(nil)
            // The hosting view has not re-evaluated the body yet, so its
            // fitting size is stale; measure on the next turn instead.
            DispatchQueue.main.async { [weak self] in self?.resizeInPlace() }
            return
        }
        let model = LinkPickerModel(url: url, browsers: browsers, waiting: waiting, showURLLine: showURLLine)
        model.choose = onChoose
        self.model = model
        let panel = KeyablePickerPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                       backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: LinkPickerView(model: model))
        panel.keyHandler = { [weak self] event in self?.handle(event) ?? false }
        self.panel = panel
        placeAtCursor()
        panel.makeKeyAndOrderFront(nil)
        // Clicking anywhere outside (another app's window) cancels. The
        // global monitor never sees clicks inside this panel.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.onCancel()
        }
    }

    func dismiss() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        panel?.orderOut(nil)
        panel = nil
        model = nil
        onCancel = {}
    }

    private var screens: [(frame: CGRect, visible: CGRect)] {
        NSScreen.screens.map { (frame: $0.frame, visible: $0.visibleFrame) }
    }

    /// First present: the body is evaluated on creation, so the size is right.
    private func placeAtCursor() {
        guard let panel, let content = panel.contentView else { return }
        content.layoutSubtreeIfNeeded()
        panel.setFrame(LinkPickerPlacement.frame(size: content.fittingSize, cursor: NSEvent.mouseLocation,
                                                 screens: screens), display: true)
    }

    /// Update: keep the panel where the user is aiming and only re-fit it.
    private func resizeInPlace() {
        guard let panel, let content = panel.contentView else { return }
        content.layoutSubtreeIfNeeded()
        panel.setFrame(LinkPickerPlacement.resized(panel.frame, to: content.fittingSize, screens: screens),
                       display: true)
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let model else { return false }
        // A held key must not choose the next queued link the moment the
        // first repeat arrives; swallow repeats so they do not beep either.
        if event.isARepeat { return true }
        switch LinkPickerKeys.action(keyCode: event.keyCode, browserCount: model.browsers.count) {
        case .choose(let index)?:
            model.choose(model.browsers[index], event.modifierFlags.contains(.option))
        case .chooseSelected?:
            let index = LinkPickerSupport.clamped(selected: model.selectedIndex, count: model.browsers.count)
            model.choose(model.browsers[index], event.modifierFlags.contains(.option))
        case .move(let delta)?:
            model.selectedIndex = LinkPickerSupport.moved(selected: model.selectedIndex, by: delta,
                                                          count: model.browsers.count)
        case .cancel?:
            onCancel()
        case nil:
            return false
        }
        return true
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
