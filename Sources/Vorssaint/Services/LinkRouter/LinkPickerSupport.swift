// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics

enum LinkPickerKey: Equatable {
    case choose(index: Int)
    case chooseFirst
    case cancel
}

/// Hardware key codes, not characters, so the shortcuts work on any keyboard
/// layout and on the keypad.
enum LinkPickerKeys {
    private static let numberRow: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
    private static let keypad: [UInt16] = [83, 84, 85, 86, 87, 88, 89, 91, 92]

    static func action(keyCode: UInt16, browserCount: Int) -> LinkPickerKey? {
        if keyCode == 53 { return .cancel }
        if keyCode == 36 || keyCode == 76 { return browserCount > 0 ? .chooseFirst : nil }
        let index = numberRow.firstIndex(of: keyCode) ?? keypad.firstIndex(of: keyCode)
        guard let index, index < browserCount else { return nil }
        return .choose(index: index)
    }
}

enum LinkPickerPlacement {
    private static let gap: CGFloat = 12
    private static let margin: CGFloat = 8

    /// Below the cursor, centered on it; above when there is no room below;
    /// always clamped inside the visible frame of the screen under the cursor
    /// (the full frame decides the screen, so the menu bar strip still counts).
    static func frame(size: CGSize, cursor: CGPoint, screens: [(frame: CGRect, visible: CGRect)]) -> CGRect {
        guard let screen = screens.first(where: { $0.frame.contains(cursor) }) ?? screens.first else {
            return CGRect(origin: .zero, size: size)
        }
        let area = screen.visible
        var x = cursor.x - size.width / 2
        var y = cursor.y - size.height - gap
        if y < area.minY { y = cursor.y + gap }
        x = min(max(x, area.minX + margin), area.maxX - size.width - margin)
        y = min(max(y, area.minY + margin), area.maxY - size.height - margin)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// Resizes an already-placed panel without moving it to the cursor: the top
    /// edge and horizontal center stay put, then the result is clamped into the
    /// visible frame of the screen the panel is on.
    static func resized(_ current: CGRect, to size: CGSize, screens: [(frame: CGRect, visible: CGRect)]) -> CGRect {
        let center = CGPoint(x: current.midX, y: current.midY)
        guard let screen = screens.first(where: { $0.frame.contains(center) }) ?? screens.first else {
            return CGRect(origin: current.origin, size: size)
        }
        let area = screen.visible
        var x = current.midX - size.width / 2
        var y = current.maxY - size.height
        x = min(max(x, area.minX + margin), area.maxX - size.width - margin)
        y = min(max(y, area.minY + margin), area.maxY - size.height - margin)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}
