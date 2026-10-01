// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CoreGraphics

enum LinkRouterPickerTests {
    static func run(_ suite: TestSuite) {
        runKeys(suite)
        runState(suite)
        runPreview(suite)

        suite.expect(LinkPickerSupport.moved(selected: 0, by: 1, count: 3) == 1
                        && LinkPickerSupport.moved(selected: 2, by: 1, count: 3) == 0
                        && LinkPickerSupport.moved(selected: 0, by: -1, count: 3) == 2,
                     "the highlight wraps around at both ends")
        suite.expect(LinkPickerSupport.moved(selected: 0, by: 1, count: 0) == 0,
                     "moving with no browsers stays at zero")
        suite.expect(LinkPickerSupport.clamped(selected: 5, count: 3) == 2
                        && LinkPickerSupport.clamped(selected: -1, count: 3) == 0
                        && LinkPickerSupport.clamped(selected: 1, count: 0) == 0,
                     "a stale highlight is clamped into the current list")
        suite.expect(LinkPickerSupport.visibleRows(count: 4) == 4
                        && LinkPickerSupport.visibleRows(count: 30) == LinkPickerSupport.maxVisibleRows,
                     "a long list is capped so the panel scrolls instead of growing off screen")

        // Placement
        let screen = (frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                      visible: CGRect(x: 0, y: 0, width: 1000, height: 775))
        let size = CGSize(width: 300, height: 100)
        let middle = LinkPickerPlacement.frame(size: size, cursor: CGPoint(x: 500, y: 400), screens: [screen])
        suite.expect(middle.midX == 500 && middle.maxY < 400,
                     "the picker centers on the cursor, below it when there is room")
        let bottom = LinkPickerPlacement.frame(size: size, cursor: CGPoint(x: 500, y: 20), screens: [screen])
        suite.expect(bottom.minY >= 20 && bottom.minY >= screen.visible.minY,
                     "with no room below the picker flips above the cursor")
        let corner = LinkPickerPlacement.frame(size: size, cursor: CGPoint(x: 995, y: 770), screens: [screen])
        suite.expect(screen.visible.contains(corner),
                     "the picker is clamped inside the visible frame at a corner")
        let second = (frame: CGRect(x: 1000, y: 0, width: 800, height: 600),
                      visible: CGRect(x: 1000, y: 0, width: 800, height: 600))
        let onSecond = LinkPickerPlacement.frame(size: size, cursor: CGPoint(x: 1400, y: 300), screens: [screen, second])
        suite.expect(second.visible.contains(onSecond), "the picker appears on the screen under the cursor")
        let menuBar = LinkPickerPlacement.frame(size: size, cursor: CGPoint(x: 500, y: 790), screens: [screen])
        suite.expect(screen.visible.contains(menuBar),
                     "a cursor over the menu bar still picks that screen and clamps below it")
        suite.expect(LinkPickerPlacement.frame(size: size, cursor: .zero, screens: []).size == size,
                     "with no screens the size is kept and nothing crashes")

        // Command Bar placement
        let wide = (frame: CGRect(x: 0, y: 0, width: 2000, height: 1000), visible: CGRect(x: 0, y: 0, width: 2000, height: 975))
        let other = (frame: CGRect(x: 2000, y: 0, width: 1000, height: 800), visible: CGRect(x: 2000, y: 0, width: 1000, height: 775))
        let bar = LinkPickerPlacement.barFrame(size: CGSize(width: 560, height: 200), pointer: CGPoint(x: 100, y: 100), screens: [wide, other])
        suite.expect(bar.midX == wide.visible.midX && abs(bar.maxY - (wide.visible.minY + wide.visible.height * 0.72)) < 0.5,
                     "the picker opens centered on the pointer's screen with its top at the Command Bar's height")
        let barOnOther = LinkPickerPlacement.barFrame(size: CGSize(width: 560, height: 200), pointer: CGPoint(x: 2500, y: 100), screens: [wide, other])
        suite.expect(other.visible.contains(barOnOther), "the picker follows the pointer to another display")
        let tall = LinkPickerPlacement.barFrame(size: CGSize(width: 560, height: 900), pointer: CGPoint(x: 100, y: 100), screens: [wide])
        suite.expect(wide.visible.contains(tall), "a tall picker is clamped into the visible frame")
        suite.expect(LinkPickerPlacement.barFrame(size: CGSize(width: 560, height: 200), pointer: .zero, screens: []).size
                        == CGSize(width: 560, height: 200),
                     "with no screens the size is kept and nothing crashes")

        // Resizing in place keeps the top edge and horizontal center
        let current = CGRect(x: 350, y: 300, width: 300, height: 100)
        let grown = LinkPickerPlacement.resized(current, to: CGSize(width: 400, height: 130), screens: [screen])
        suite.expect(grown.midX == current.midX && grown.maxY == current.maxY && grown.size == CGSize(width: 400, height: 130),
                     "an update resize keeps the top edge and center instead of following the cursor")
        let nearEdge = LinkPickerPlacement.resized(CGRect(x: 690, y: 10, width: 300, height: 100),
                                                   to: CGSize(width: 400, height: 130), screens: [screen])
        suite.expect(screen.visible.contains(nearEdge), "an update resize is re-clamped into the visible frame")
        let onOther = LinkPickerPlacement.resized(CGRect(x: 1500, y: 300, width: 300, height: 100),
                                                  to: CGSize(width: 400, height: 130), screens: [screen, second])
        suite.expect(second.visible.contains(onOther), "an update resize clamps on the screen the panel is on")
        suite.expect(LinkPickerPlacement.resized(current, to: size, screens: []).size == size,
                     "resizing with no screens keeps the size and nothing crashes")

        suite.expect(LinkPickerSupport.shouldActivateBrowser(waitingAfter: 0)
                        && !LinkPickerSupport.shouldActivateBrowser(waitingAfter: 1)
                        && !LinkPickerSupport.shouldActivateBrowser(waitingAfter: 3),
                     "the chosen browser only activates when no more links are waiting")
    }

    private static let safari = BrowserInfo(bundleID: "com.apple.Safari", name: "Safari")
    private static let firefox = BrowserInfo(bundleID: "org.mozilla.firefox", name: "Firefox")
    private static let chrome = BrowserInfo(bundleID: "com.google.Chrome", name: "Chrome")
    private static let sealant = RewriteRule(name: "YouTube to Sealant", find: "a", replacement: "b", key: "y")
    private static let privacy = RewriteRule(name: "Privacy front-end", find: "a", replacement: "b", key: "p")

    private static func runKeys(_ suite: TestSuite) {
        let numberRow: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        let keypad: [UInt16] = [83, 84, 85, 86, 87, 88, 89, 91, 92]
        let map = LinkPickerKeyMap.make(rewrites: [sealant, privacy])
        func act(_ keyCode: UInt16, command: Bool = false, characters: String? = nil,
                 empty: Bool = true, rows: Int = 9, browsers: Int = 9) -> LinkPickerAction? {
            LinkPickerKeys.action(keyCode: keyCode, command: command, characters: characters,
                                  fieldIsEmpty: empty, keyMap: map, rowCount: rows, browserCount: browsers)
        }
        for (index, code) in numberRow.enumerated() {
            suite.expect(act(code) == .chooseDigit(index), "number row key \(index + 1) picks browser \(index + 1) while the field is empty")
        }
        for (index, code) in keypad.enumerated() {
            suite.expect(act(code) == .chooseDigit(index), "keypad key \(index + 1) picks browser \(index + 1) while the field is empty")
        }
        suite.expect(act(18, empty: false) == nil, "a digit goes into the field once there is text")
        suite.expect(act(20, browsers: 2) == nil, "a digit beyond the browser count goes into the field")
        suite.expect(act(20, command: true, empty: false) == .chooseDigit(2),
                     "command plus a digit picks a browser even while typing")
        suite.expect(act(36) == .activateSelected && act(76) == .activateSelected, "Return and Enter act on the highlighted row")
        suite.expect(act(36, rows: 0) == nil, "Return with no rows does nothing")
        suite.expect(act(125) == .move(1) && act(126) == .move(-1), "arrows move the highlight")
        suite.expect(act(125, rows: 0) == nil, "arrows with no rows do nothing")
        suite.expect(act(53) == .escape, "Escape is reported so the state can clear or cancel")
        suite.expect(act(14, command: true, characters: "e", empty: false) == .toggleChip(.extract)
                        && act(37, command: true, characters: "L") == .toggleChip(.clean),
                     "command plus a chip letter toggles the chip, also while typing")
        suite.expect(act(16, command: true, characters: "y") == .toggleRewrite(sealant.id)
                        && act(35, command: true, characters: "p") == .toggleRewrite(privacy.id),
                     "command plus a rewrite's letter toggles that rewrite")
        suite.expect(act(9, command: true, characters: "v") == nil && act(0, command: true, characters: "a") == nil
                        && act(8, command: true, characters: "c") == nil,
                     "reserved edit shortcuts are left to the field")
        suite.expect(act(14, command: false, characters: "e") == nil, "a bare letter is typing, not a shortcut")
        let clash = RewriteRule(name: "Clash", find: "a", replacement: "b", key: "y")
        let reservedKeys = [RewriteRule(name: "E", find: "a", replacement: "b", key: "e"),
                            RewriteRule(name: "V", find: "a", replacement: "b", key: "v")]
        let clashMap = LinkPickerKeyMap.make(rewrites: [sealant, clash] + reservedKeys)
        suite.expect(clashMap.rewrites == ["y": sealant.id] && clashMap.chips == ["e": .extract, "l": .clean],
                     "a duplicate, built-in or reserved rewrite key never maps; the first claim wins")
    }

    private static func runState(_ suite: TestSuite) {
        var state = LinkPickerState(browsers: [safari, firefox, chrome], rewrites: [sealant, privacy], chips: [])
        suite.expect(state.rowCount == 5 && state.selected == 0 && state.visibleBrowsers == [safari, firefox, chrome],
                     "an empty query shows every row with the first browser highlighted")
        state.move(-1)
        suite.expect(state.selected == 4, "moving up from the top wraps to the last rewrite")
        state.move(1)
        suite.expect(state.selected == 0, "moving down from the last row wraps to the top")

        state.setQuery("fi")
        suite.expect(state.visibleBrowsers == [firefox] && state.visibleRewrites.isEmpty && state.selected == 0,
                     "typing filters browsers and hides rewrites that do not match")
        state.setQuery("ROME")
        suite.expect(state.visibleBrowsers == [chrome], "matching ignores case and finds substrings")
        state.setQuery("yout")
        suite.expect(state.visibleBrowsers == [safari, firefox, chrome] && state.visibleRewrites == [sealant]
                        && state.selected == 3,
                     "a query only a rewrite matches keeps every browser and highlights the rewrite")
        state.setQuery("s")
        suite.expect(state.visibleBrowsers == [safari] && state.selected == 0,
                     "prefix matches rank before substring matches, and a browser match wins the highlight")
        var ranked = LinkPickerState(browsers: [BrowserInfo(bundleID: "a", name: "Brave Safari"), safari], rewrites: [], chips: [])
        ranked.setQuery("saf")
        suite.expect(ranked.visibleBrowsers == [safari, BrowserInfo(bundleID: "a", name: "Brave Safari")],
                     "a name that starts with the query ranks above one that merely contains it")

        state.setQuery("yout")
        suite.expect(state.activate() == .toggledRewrite && state.activeRewrite == sealant.id
                        && state.query.isEmpty && state.selected == 0,
                     "Return on a rewrite turns it on, clears the filter and returns to the first browser")
        suite.expect(state.activate() == .open(safari), "the next Return opens the first browser")
        state.toggleRewrite(privacy.id)
        suite.expect(state.activeRewrite == privacy.id, "rewrites are exclusive: turning one on turns the other off")
        state.toggleRewrite(privacy.id)
        suite.expect(state.activeRewrite == nil, "toggling the active rewrite turns it off")

        state.toggleChip(.clean)
        suite.expect(state.chips == [.clean], "a chip toggles on")
        state.toggleChip(.extract)
        state.toggleChip(.clean)
        suite.expect(state.chips == [.extract], "chips toggle independently")

        state.setQuery("fi")
        suite.expect(state.escape() == .clearedQuery && state.query.isEmpty, "Escape first clears the filter")
        suite.expect(state.escape() == .cancel, "Escape with an empty filter cancels")

        state.setQuery("zzz")
        suite.expect(state.visibleBrowsers.count == 3 && state.visibleRewrites.isEmpty,
                     "a query nothing matches leaves the browsers in place")
        state.setQuery("")
        suite.expect(state.browser(atDigit: 1) == firefox && state.browser(atDigit: 3) == nil && state.browser(atDigit: -1) == nil,
                     "digits index the visible browsers and out of range is nil")
        state.select(row: 99)
        suite.expect(state.selected == 4, "selecting a row past the end clamps to the last row")

        var empty = LinkPickerState(browsers: [], rewrites: [], chips: [])
        suite.expect(empty.activate() == .nothing && empty.rowCount == 0, "with no rows there is nothing to activate")
        empty.move(1)
        suite.expect(empty.selected == 0, "moving with no rows stays at zero")
    }

    private static func runPreview(_ suite: TestSuite) {
        let settings = TransformSettings()
        let plain = LinkTransform.apply(URL(string: "https://example.com/a/b?x=1")!, chips: [], settings: settings)
        suite.expect(LinkURLPreview.segments(mode: .off, result: plain, rewritten: nil).isEmpty,
                     "the off mode shows no line")
        suite.expect(LinkURLPreview.segments(mode: .hostPath, result: plain, rewritten: nil)
                        == [URLSegment(text: "example.com/a/b", style: .plain)],
                     "host and path mode drops the query")
        let root = LinkTransform.apply(URL(string: "https://example.com/?x=1")!, chips: [], settings: settings)
        suite.expect(LinkURLPreview.segments(mode: .hostPath, result: root, rewritten: nil)
                        == [URLSegment(text: "example.com", style: .plain)],
                     "host and path mode leaves off a bare slash")
        suite.expect(LinkURLPreview.segments(mode: .full, result: plain, rewritten: nil)
                        == [URLSegment(text: "https://example.com/a/b?x=1", style: .plain)],
                     "full mode shows the whole link")

        let tracked = LinkTransform.apply(URL(string: "https://example.com/p?id=7&utm_source=x&fbclid=y")!,
                                          chips: [.clean], settings: settings)
        suite.expect(LinkURLPreview.segments(mode: .full, result: tracked, rewritten: nil) == [
            URLSegment(text: "https://example.com/p?id=7&", style: .plain),
            URLSegment(text: "utm_source=x", style: .removed),
            URLSegment(text: "&", style: .plain),
            URLSegment(text: "fbclid=y", style: .removed),
        ], "removed parameters are shown struck through in place")

        let rewritten = URL(string: "https://yt.example.test/watch?v=abc")!
        suite.expect(LinkURLPreview.segments(mode: .full, result: plain, rewritten: rewritten) == [
            URLSegment(text: "https://", style: .plain),
            URLSegment(text: "yt.example.test", style: .changed),
            URLSegment(text: "/watch?v=abc", style: .plain),
        ], "a rewrite highlights the new host")
        suite.expect(LinkURLPreview.segments(mode: .hostPath, result: plain, rewritten: rewritten)
                        == [URLSegment(text: "yt.example.test/watch", style: .plain)],
                     "host and path mode follows the rewritten link")

        let wrapper = LinkTransform.apply(URL(string: "https://l.facebook.com/l.php?u=https%3A%2F%2Fexample.org%2Fa")!,
                                          chips: [.extract], settings: settings)
        suite.expect(LinkURLPreview.segments(mode: .full, result: wrapper, rewritten: nil)
                        == [URLSegment(text: "https://example.org/a", style: .plain)],
                     "an extracted destination is shown as plain text")
    }
}
