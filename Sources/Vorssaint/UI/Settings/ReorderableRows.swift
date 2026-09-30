// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import UniformTypeIdentifiers

/// Drag-to-reorder for dynamic lists keyed by a string id, in the style of
/// `PanelReorderableItem`. The rows reorder live in the bound array while the
/// drag moves over them; `onCommit` runs once when the drop completes, so the
/// caller saves once instead of on every step.
struct ReorderableRow<Item, Content: View>: View {
    let item: Item
    let id: (Item) -> String
    @Binding var items: [Item]
    @Binding var dragging: String?
    let onCommit: () -> Void
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
    let onCommit: () -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        let ids = items.map(id)
        let moved = ReorderSupport.move(ids: ids, moving: dragging, onto: target)
        guard moved != ids else { return }
        items = ReorderSupport.apply(order: moved, to: items, id: id)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        onCommit()
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
