// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Everything the picker decides, without a view: what is shown for the text
/// typed so far, which row is highlighted, and which edits are on. The panel
/// only renders it and forwards keys, so the behavior is testable.
struct LinkPickerState: Equatable {
    var browsers: [BrowserInfo]
    /// Already limited to the rewrites that match the link.
    var rewrites: [RewriteRule]
    var chips: TransformChips
    var activeRewrite: UUID?
    private(set) var query = ""
    /// Index into the rows: the visible browsers first, then the rewrites.
    private(set) var selected = 0

    init(browsers: [BrowserInfo], rewrites: [RewriteRule], chips: TransformChips) {
        self.browsers = browsers
        self.rewrites = rewrites
        self.chips = chips
    }

    /// When nothing matches the text the list is left whole: the person is
    /// typing a rewrite's name and still needs a browser to send it to.
    var visibleBrowsers: [BrowserInfo] {
        let text = normalizedQuery
        guard !text.isEmpty else { return browsers }
        let matches = Self.ranked(browsers, text) { $0.name }
        return matches.isEmpty ? browsers : matches
    }

    var visibleRewrites: [RewriteRule] {
        let text = normalizedQuery
        guard !text.isEmpty else { return rewrites }
        return Self.ranked(rewrites, text) { $0.name }
    }

    var rowCount: Int { visibleBrowsers.count + visibleRewrites.count }

    mutating func setQuery(_ text: String) {
        query = text
        let browsersMatch = !normalizedQuery.isEmpty && !Self.ranked(browsers, normalizedQuery) { $0.name }.isEmpty
        // Highlight a matching rewrite only when no browser matches, so
        // typing a browser's name never makes Return toggle something else.
        selected = (!normalizedQuery.isEmpty && !browsersMatch && !visibleRewrites.isEmpty)
            ? visibleBrowsers.count : 0
    }

    mutating func move(_ delta: Int) {
        selected = LinkPickerSupport.moved(selected: selected, by: delta, count: rowCount)
    }

    mutating func select(row: Int) {
        selected = LinkPickerSupport.clamped(selected: row, count: rowCount)
    }

    mutating func toggleChip(_ chip: TransformChips) {
        chips.formSymmetricDifference(chip)
    }

    /// Rewrites are alternatives: one at a time.
    mutating func toggleRewrite(_ id: UUID) {
        activeRewrite = activeRewrite == id ? nil : id
    }

    enum Activation: Equatable { case open(BrowserInfo), toggledRewrite, nothing }

    mutating func activate() -> Activation {
        guard rowCount > 0 else { return .nothing }
        let index = LinkPickerSupport.clamped(selected: selected, count: rowCount)
        let browsers = visibleBrowsers
        if index < browsers.count { return .open(browsers[index]) }
        toggleRewrite(visibleRewrites[index - browsers.count].id)
        setQuery("")
        return .toggledRewrite
    }

    enum EscapeResult: Equatable { case clearedQuery, cancel }

    mutating func escape() -> EscapeResult {
        guard !query.isEmpty else { return .cancel }
        setQuery("")
        return .clearedQuery
    }

    func browser(atDigit index: Int) -> BrowserInfo? {
        let list = visibleBrowsers
        return list.indices.contains(index) ? list[index] : nil
    }

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Names starting with the text first, then names merely containing it;
    /// each group keeps its original order.
    private static func ranked<T>(_ items: [T], _ text: String, name: (T) -> String) -> [T] {
        let names = items.map { name($0).lowercased() }
        let prefix = items.indices.filter { names[$0].hasPrefix(text) }
        let contains = items.indices.filter { !names[$0].hasPrefix(text) && names[$0].contains(text) }
        return (prefix + contains).map { items[$0] }
    }
}

/// `⌘`-letter bindings for one link: the two built-in chips and the rewrites
/// that apply to it.
struct LinkPickerKeyMap: Equatable {
    var chips: [String: TransformChips]
    var rewrites: [String: UUID]

    /// A rewrite whose key is a built-in chip's, reserved, malformed or already
    /// taken by an earlier rewrite gets no binding rather than shadowing one.
    static func make(rewrites: [RewriteRule]) -> LinkPickerKeyMap {
        var map = LinkPickerKeyMap(chips: [RewriteKeys.extractKey: .extract, RewriteKeys.cleanKey: .clean],
                                   rewrites: [:])
        for rule in rewrites where RewriteKeys.isValid(rule.key, among: [], editing: nil)
            && map.rewrites[rule.key] == nil {
            map.rewrites[rule.key] = rule.id
        }
        return map
    }
}

enum URLSegmentStyle: Equatable { case plain, removed, changed }

struct URLSegment: Equatable {
    var text: String
    var style: URLSegmentStyle
}

/// The link line under the search field, as styled pieces so the view can
/// strike out what Clean removed and highlight a rewritten host.
enum LinkURLPreview {
    static func segments(mode: LinkURLLineMode, result: TransformResult, rewritten: URL?) -> [URLSegment] {
        let final = rewritten ?? result.url
        switch mode {
        case .off:
            return []
        case .hostPath:
            let path = final.path == "/" ? "" : final.path
            return [URLSegment(text: (final.host ?? "") + path, style: .plain)]
        case .full:
            if rewritten != nil { return hostHighlighted(final) }
            if !result.removedParameters.isEmpty { return strikingRemoved(result.beforeClean, names: result.removedParameters) }
            return [URLSegment(text: final.absoluteString, style: .plain)]
        }
    }

    private static func hostHighlighted(_ url: URL) -> [URLSegment] {
        let text = url.absoluteString
        guard let host = url.host, let range = text.range(of: host) else {
            return [URLSegment(text: text, style: .plain)]
        }
        return [URLSegment(text: String(text[..<range.lowerBound]), style: .plain),
                URLSegment(text: host, style: .changed),
                URLSegment(text: String(text[range.upperBound...]), style: .plain)]
            .filter { !$0.text.isEmpty }
    }

    private static func strikingRemoved(_ url: URL, names: [String]) -> [URLSegment] {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.percentEncodedQueryItems, !items.isEmpty else {
            return [URLSegment(text: url.absoluteString, style: .plain)]
        }
        let fragment = components.percentEncodedFragment
        components.percentEncodedQueryItems = nil
        components.fragment = nil
        var segments: [URLSegment] = []
        func append(_ text: String, _ style: URLSegmentStyle) {
            if let last = segments.last, last.style == style {
                segments[segments.count - 1].text += text
            } else {
                segments.append(URLSegment(text: text, style: style))
            }
        }
        append((components.string ?? url.absoluteString) + "?", .plain)
        for (index, item) in items.enumerated() {
            if index > 0 { append("&", .plain) }
            let name = item.name.removingPercentEncoding ?? item.name
            let text = item.value.map { "\(item.name)=\($0)" } ?? item.name
            append(text, names.contains(name) ? .removed : .plain)
        }
        if let fragment { append("#" + fragment, .plain) }
        return segments
    }
}
