// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum LinkPickerAction: Equatable {
    case chooseDigit(Int)
    case activateSelected
    case move(Int)
    case escape
    case toggleChip(TransformChips)
    case toggleRewrite(UUID)
}

/// Hardware key codes for the non-letter keys, so the shortcuts work on any
/// keyboard layout and on the keypad. Letters come in as the character the
/// system resolved, because a chip's letter must follow the layout.
enum LinkPickerKeys {
    private static let numberRow: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
    private static let keypad: [UInt16] = [83, 84, 85, 86, 87, 88, 89, 91, 92]

    /// Nil means "not ours": the key is typing into the search field (or an
    /// edit shortcut the field should handle).
    static func action(keyCode: UInt16, command: Bool, characters: String?, fieldIsEmpty: Bool,
                       keyMap: LinkPickerKeyMap, rowCount: Int, browserCount: Int) -> LinkPickerAction? {
        if keyCode == 53 { return .escape }
        if keyCode == 36 || keyCode == 76 { return rowCount > 0 ? .activateSelected : nil }
        if keyCode == 125 || keyCode == 126 { return rowCount > 0 ? .move(keyCode == 125 ? 1 : -1) : nil }
        if let index = numberRow.firstIndex(of: keyCode) ?? keypad.firstIndex(of: keyCode) {
            // A bare digit is a shortcut only while nothing is typed, so
            // filtering for a name that contains a digit still works.
            guard command || fieldIsEmpty, index < browserCount else { return nil }
            return .chooseDigit(index)
        }
        guard command, let key = characters?.lowercased() else { return nil }
        if let chip = keyMap.chips[key] { return .toggleChip(chip) }
        if let id = keyMap.rewrites[key] { return .toggleRewrite(id) }
        return nil
    }
}

enum LinkPickerSupport {
    /// Rows shown before the list scrolls; keeps the panel on screen however
    /// many browsers are installed.
    static let maxVisibleRows = 9

    static func visibleRows(count: Int) -> Int { min(count, maxVisibleRows) }

    /// Matches the Command Bar's window so the two read as one family.
    static let barWidth: CGFloat = 560

    /// Arrow keys wrap, so a short list never needs a second press to loop.
    static func moved(selected: Int, by delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((selected + delta) % count + count) % count
    }

    /// The browser list can change under a held highlight (a queued link
    /// brings its own matches), so it is re-fitted instead of trusted.
    static func clamped(selected: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(selected, 0), count - 1)
    }

    /// A chosen browser takes keyboard focus when it activates. While more
    /// links are queued the next picker must keep focus, so the open is
    /// background-only then.
    static func shouldActivateBrowser(waitingAfter waiting: Int) -> Bool {
        waiting <= 0
    }
}

enum LinkPickerPlacement {
    private static let gap: CGFloat = 12
    private static let margin: CGFloat = 8

    /// Where the Command Bar opens: centered, its top edge at 72% of the
    /// visible height of the screen under the pointer. The same formula, not a
    /// copy, so the two windows cannot drift apart.
    static func barFrame(size: CGSize, pointer: CGPoint,
                         screens: [(frame: CGRect, visible: CGRect)]) -> CGRect {
        guard let screen = screens.first(where: { $0.frame.contains(pointer) }) ?? screens.first else {
            return CGRect(origin: .zero, size: size)
        }
        let origin = CommandBarPreferences.clampedPanelOrigin(size: size, in: screen.visible, offset: .zero)
        return CGRect(origin: origin, size: size)
    }

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
