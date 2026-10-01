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
    // Settings
    let defaultChipsHeader: String
    let extractToggle: String
    let cleanToggle: String
    let genericExtractToggle: String
    let genericExtractNote: String
    let wrappersHeader: String
    let wrappersEmpty: String
    let addWrapper: String
    let wrapperSiteLabel: String
    let wrapperParameterLabel: String
    let builtInBadge: String
    let rewritesSettingsHeader: String
    let rewritesEmpty: String
    let addRewrite: String
    let rewriteNameLabel: String
    let rewriteSiteLabel: String
    let rewriteFindLabel: String
    let rewriteReplaceLabel: String
    let rewriteKeyLabel: String
    let rewriteKeyInvalid: String
    let rewriteTestLabel: String
    let rewriteTestResultFormat: String
    let rewriteTestNoChange: String
    let rewriteTestFailed: String
    let urlLineModeLabel: String
    let urlLineOff: String
    let urlLineHostPath: String
    let urlLineFull: String
    let ruleChipsLabel: String
    let ruleChipsDefault: String
    let ruleRewriteLabel: String
    let ruleRewriteNone: String
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
        ruleAddedWithFormat: "Rule added for %@, with %@",
        defaultChipsHeader: "Edits applied by default",
        extractToggle: "Extract the destination from redirect links",
        cleanToggle: "Remove tracking parameters",
        genericExtractToggle: "Also try any link-valued parameter on unknown sites",
        genericExtractNote: "May pick the wrong link on some sites. Off by default.",
        wrappersHeader: "Redirect links",
        wrappersEmpty: "No custom redirect rules.",
        addWrapper: "Add redirect rule",
        wrapperSiteLabel: "Site",
        wrapperParameterLabel: "Parameter with the destination",
        builtInBadge: "Built in",
        rewritesSettingsHeader: "Rewrites",
        rewritesEmpty: "No rewrites yet. A rewrite can send links to another site, such as a privacy-friendly front-end.",
        addRewrite: "Add rewrite",
        rewriteNameLabel: "Name",
        rewriteSiteLabel: "Only on sites (optional)",
        rewriteFindLabel: "Find (regex)",
        rewriteReplaceLabel: "Replace with ($1 for groups)",
        rewriteKeyLabel: "Key",
        rewriteKeyInvalid: "Use one unused letter. E, L and common shortcut letters are taken.",
        rewriteTestLabel: "Test link",
        rewriteTestResultFormat: "Result: %@",
        rewriteTestNoChange: "No change",
        rewriteTestFailed: "Rewrite failed",
        urlLineModeLabel: "Link line",
        urlLineOff: "Off",
        urlLineHostPath: "Host and path",
        urlLineFull: "Full link",
        ruleChipsLabel: "Edits",
        ruleChipsDefault: "Use default",
        ruleRewriteLabel: "Rewrite",
        ruleRewriteNone: "None"
    )
}
