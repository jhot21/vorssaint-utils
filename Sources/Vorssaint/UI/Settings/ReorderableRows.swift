// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import UniformTypeIdentifiers

/// Drag-to-reorder for dynamic lists keyed by a string id, in the style of
/// `PanelReorderableItem`. The rows reorder live in the bound array while the
/// drag moves over them, but that is only a preview: nothing is saved until the
/// drag is dropped (`onCommit`, once, and only when the order changed). A drag
/// that is cancelled is reverted by the owner through `ReorderReleaseWatcher`.
struct ReorderableRow<Item, Content: View>: View {
    let item: Item
    let id: (Item) -> String
    @Binding var items: [Item]
    @Binding var dragging: String?
    @Binding var session: ReorderSession?
    let onDragStart: () -> Void
    let onCommit: ([String]) -> Void
    let onDragEnd: () -> Void
    let content: () -> Content

    var body: some View {
        content()
            .opacity(dragging == id(item) ? 0.4 : 1)
            .onDrag {
                dragging = id(item)
                if session == nil { session = ReorderSession(snapshot: items.map(id)) }
                onDragStart()
                return NSItemProvider(object: id(item) as NSString)
            }
            .onDrop(of: [UTType.text], delegate: ReorderDropDelegate(target: id(item), id: id,
                                                                      items: $items, dragging: $dragging,
                                                                      session: $session, onCommit: onCommit, onDragEnd: onDragEnd))
    }
}

private struct ReorderDropDelegate<Item>: DropDelegate {
    let target: String
    let id: (Item) -> String
    @Binding var items: [Item]
    @Binding var dragging: String?
    @Binding var session: ReorderSession?
    let onCommit: ([String]) -> Void
    let onDragEnd: () -> Void

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
        session?.preview(moved)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard operation == .move else { return false }
        let finished = session
        dragging = nil
        session = nil
        if let finished, finished.changed { onCommit(finished.committed()) }
        onDragEnd()
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: operation == .move ? .move : .forbidden)
    }
}

/// SwiftUI reports no callback for a cancelled drag (Esc, or released outside
/// every target), so while a drag is active this polls the left mouse button.
/// Once it has been up for `grace` (long enough for a real drop to run first)
/// and the drag is still active, `onCancel` runs. The timer invalidates itself
/// as soon as `isActive` turns false or it fires `onCancel`, is replaced by the
/// next `start`, and is invalidated on `deinit`, so it never outlives a drag.
final class ReorderReleaseWatcher {
    private var timer: Timer?
    private var releasedAt: Date?

    deinit { timer?.invalidate() }

    func start(grace: TimeInterval = 0.3, isActive: @escaping () -> Bool, onCancel: @escaping () -> Void) {
        stop()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard isActive() else { return self.stop() }
            if NSEvent.pressedMouseButtons & 1 != 0 {
                self.releasedAt = nil
                return
            }
            let since = self.releasedAt ?? Date()
            self.releasedAt = since
            if Date().timeIntervalSince(since) >= grace {
                self.stop()
                onCancel()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        releasedAt = nil
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
