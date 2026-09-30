// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import UniformTypeIdentifiers

/// Drag-to-reorder for dynamic lists keyed by a string id, in the style of
/// `PanelReorderableItem`. The rows reorder live in the bound array while the
/// drag moves over them, and `onCommit` runs with the new order each time it
/// actually changes, so screen and storage never diverge even when the drag
/// ends off a row (a gap, another window, Esc).
struct ReorderableRow<Item, Content: View>: View {
    let item: Item
    let id: (Item) -> String
    @Binding var items: [Item]
    @Binding var dragging: String?
    let onCommit: ([String]) -> Void
    let content: () -> Content

    var body: some View {
        content()
            .opacity(dragging == id(item) ? 0.4 : 1)
            .onDrag {
                dragging = id(item)
                return NSItemProvider(object: id(item) as NSString)
            }
            .onDrop(of: [UTType.text], delegate: ReorderDropDelegate(target: id(item), id: id,
                                                                      items: $items, dragging: $dragging,
                                                                      onCommit: onCommit))
    }
}

private struct ReorderDropDelegate<Item>: DropDelegate {
    let target: String
    let id: (Item) -> String
    @Binding var items: [Item]
    @Binding var dragging: String?
    let onCommit: ([String]) -> Void

    private var operation: ReorderSupport.DropOperation {
        ReorderSupport.dropOperation(dragging: dragging, ids: items.map(id))
    }

    func validateDrop(info: DropInfo) -> Bool { operation == .move }

    func dropEntered(info: DropInfo) {
        guard operation == .move, let dragging, dragging != target else { return }
        let ids = items.map(id)
        let moved = ReorderSupport.move(ids: ids, moving: dragging, onto: target)
        guard moved != ids else { return }
        items = ReorderSupport.apply(order: moved, to: items, id: id)
        onCommit(moved)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard operation == .move else { return false }
        dragging = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: operation == .move ? .move : .forbidden)
    }
}

/// Catches drops that land between rows or on headers, so a drag that ends
/// there still clears the dragging state. Refuses everything when no row of
/// this page is being dragged.
struct ReorderDropZone: DropDelegate {
    let isDragging: () -> Bool
    let finish: () -> Void

    func validateDrop(info: DropInfo) -> Bool { isDragging() }

    func performDrop(info: DropInfo) -> Bool {
        guard isDragging() else { return false }
        finish()
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: isDragging() ? .move : .forbidden)
    }
}
