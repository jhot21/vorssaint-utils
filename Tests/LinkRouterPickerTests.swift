// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CoreGraphics

enum LinkRouterPickerTests {
    static func run(_ suite: TestSuite) {
        // Number row key codes 1...9 are 18,19,20,21,23,22,26,28,25.
        let numberRow: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        for (index, code) in numberRow.enumerated() {
            suite.expect(LinkPickerKeys.action(keyCode: code, browserCount: 9) == .choose(index: index),
                         "number row key \(index + 1) chooses browser \(index + 1)")
        }
        let keypad: [UInt16] = [83, 84, 85, 86, 87, 88, 89, 91, 92]
        for (index, code) in keypad.enumerated() {
            suite.expect(LinkPickerKeys.action(keyCode: code, browserCount: 9) == .choose(index: index),
                         "keypad key \(index + 1) chooses browser \(index + 1)")
        }
        suite.expect(LinkPickerKeys.action(keyCode: 20, browserCount: 2) == nil,
                     "a number beyond the browser count does nothing")
        suite.expect(LinkPickerKeys.action(keyCode: 36, browserCount: 3) == .chooseFirst
                        && LinkPickerKeys.action(keyCode: 76, browserCount: 3) == .chooseFirst,
                     "Return and keypad Enter choose the first browser")
        suite.expect(LinkPickerKeys.action(keyCode: 36, browserCount: 0) == nil,
                     "Return with no browsers does nothing")
        suite.expect(LinkPickerKeys.action(keyCode: 53, browserCount: 3) == .cancel, "Escape cancels")
        suite.expect(LinkPickerKeys.action(keyCode: 0, browserCount: 3) == nil, "other keys are ignored")

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
}
