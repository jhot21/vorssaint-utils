// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct RoutingRule: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case glob, regex }
    /// Why the router disabled a rule on its own.
    enum Flag: String, Codable { case tooSlow, invalidRegex }

    var id: UUID
    var pattern: String
    var kind: Kind
    var browserBundleID: String
    var sourceAppBundleID: String?
    var isEnabled: Bool
    var flag: Flag?
    /// Which edits this rule applies. Nil means "the global default", which
    /// is different from an empty set ("none, even if the default is on").
    var chips: TransformChips?
    var rewriteID: UUID?

    init(id: UUID = UUID(), pattern: String, kind: Kind = .glob, browserBundleID: String,
         sourceAppBundleID: String? = nil, isEnabled: Bool = true, flag: Flag? = nil,
         chips: TransformChips? = nil, rewriteID: UUID? = nil) {
        self.id = id
        self.pattern = pattern
        self.kind = kind
        self.browserBundleID = browserBundleID
        self.sourceAppBundleID = sourceAppBundleID
        self.isEnabled = isEnabled
        self.flag = flag
        self.chips = chips
        self.rewriteID = rewriteID
    }
}
