// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure id-list reordering for drag-to-reorder rows.
enum ReorderSupport {
    enum DropOperation { case move, forbidden }

    /// A list accepts a drop only when the drag in progress is one of its own
    /// rows; a foreign drag (text from another app, a row of the other list)
    /// is refused so it can never be treated as a move.
    static func dropOperation(dragging: String?, ids: [String]) -> DropOperation {
        guard let dragging, ids.contains(dragging) else { return .forbidden }
        return .move
    }

    /// Moves `moving` to the position `target` currently holds, the same live
    /// behaviour as the panel layout editor: dragging forward lands after the
    /// hovered row, dragging backward lands before it. An unknown id or the
    /// same id returns the list unchanged.
    static func move(ids: [String], moving: String, onto target: String) -> [String] {
        guard moving != target,
              let from = ids.firstIndex(of: moving),
              let to = ids.firstIndex(of: target) else { return ids }
        var result = ids
        result.remove(at: from)
        result.insert(moving, at: to)
        return result
    }

    /// Re-sorts `items` into the order given by `ids`. Items whose id is not in
    /// `ids` (added by someone else since the ids were captured) keep their
    /// absolute positions; ids with no matching item are ignored.
    static func apply<Item>(order ids: [String], to items: [Item], id: (Item) -> String) -> [Item] {
        let present = Set(items.map(id))
        var ordered = ids.filter { present.contains($0) }
        var seen = Set<String>()
        ordered = ordered.filter { seen.insert($0).inserted }
        let known = Set(ordered)
        var byID: [String: Item] = [:]
        for item in items where byID[id(item)] == nil { byID[id(item)] = item }
        var queue = ordered[...]
        return items.map { item in
            guard known.contains(id(item)), let next = queue.popFirst(), let replacement = byID[next] else { return item }
            return replacement
        }
    }
}

/// One drag-to-reorder gesture. The order at drag start is the snapshot; live
/// moves only update the preview, so nothing reaches storage unless the drag is
/// committed, and a cancelled drag simply returns the snapshot.
struct ReorderSession: Equatable {
    let snapshot: [String]
    private(set) var current: [String]

    init(snapshot: [String]) {
        self.snapshot = snapshot
        self.current = snapshot
    }

    mutating func preview(_ ids: [String]) { current = ids }

    /// False when the preview is back at the snapshot order, so a no-op drag does not save.
    var changed: Bool { current != snapshot }

    func committed() -> [String] { current }
    func cancelled() -> [String] { snapshot }
}
