// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// English only, for every language: link transforms are a fork feature and
/// follow the convention of not translating those into every language.
struct LinkTransformFeatureStrings {
    let searchPlaceholder: String
    let extractChip: String
    let cleanChip: String
    let rewritesHeader: String
    let rewriteFailed: String
    let rewritePending: String
    let ruleAddedWithFormat: String
}

extension FeatureStrings {
    static func linkTransform(_ language: AppLanguage) -> LinkTransformFeatureStrings { .enUS }
}

extension LinkTransformFeatureStrings {
    static let enUS = LinkTransformFeatureStrings(
        searchPlaceholder: "Open with...",
        extractChip: "Extract destination",
        cleanChip: "Clean",
        rewritesHeader: "Rewrite",
        rewriteFailed: "Rewrite failed, using the original link",
        rewritePending: "Rewriting...",
        ruleAddedWithFormat: "Rule added for %@, with %@"
    )
}
