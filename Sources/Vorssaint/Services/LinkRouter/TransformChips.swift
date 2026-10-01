// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The two combinable link edits. Rewrites are a separate, exclusive choice.
struct TransformChips: OptionSet, Codable, Hashable {
    let rawValue: Int
    static let extract = TransformChips(rawValue: 1 << 0)
    static let clean = TransformChips(rawValue: 1 << 1)
}
