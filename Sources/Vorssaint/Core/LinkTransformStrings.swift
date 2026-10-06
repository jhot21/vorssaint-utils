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
    let unshortenChip: String
    let unshortenToggle: String
    let unshortenNote: String
    let unshortenPending: String
    let unshortenFailed: String
    let unshortenNoRedirect: String
    let shortenersHeader: String
    let shortenersEmpty: String
    let addShortener: String
    let shortenerSiteLabel: String
    let shortenerAddedNote: String
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
        unshortenChip: "Unshorten",
        unshortenToggle: "Resolve short links (contacts the shortener)",
        unshortenNote: "The shortener sees the lookup (your IP address and a generic browser identity) and may count it as a click. Your network can see which shortener you contact.",
        unshortenPending: "Resolving...",
        unshortenFailed: "Couldn’t resolve, using the short link",
        unshortenNoRedirect: "The short link didn’t redirect",
        shortenersHeader: "Short link hosts",
        shortenersEmpty: "No custom hosts.",
        addShortener: "Add host",
        shortenerSiteLabel: "Host",
        shortenerAddedNote: "Added hosts are contacted when Unshorten runs.",
        genericExtractToggle: "Also try any link-valued parameter on unknown sites",
        genericExtractNote: "May pick the wrong link on some sites. Off by default.",
        wrappersHeader: "Redirect links",
        wrappersEmpty: "No custom redirect rules.",
        addWrapper: "Add redirect rule",
        wrapperSiteLabel: "Site",
        wrapperParameterLabel: "Destination parameter",
        builtInBadge: "Built in",
        rewritesSettingsHeader: "Rewrites",
        rewritesEmpty: "No rewrites yet. A rewrite can send links to another site, such as a privacy-friendly front-end.",
        addRewrite: "Add rewrite",
        rewriteNameLabel: "Name",
        rewriteSiteLabel: "Only on sites (optional)",
        rewriteFindLabel: "Find (regex)",
        rewriteReplaceLabel: "Replace with ($1 for groups)",
        rewriteKeyLabel: "Key",
        rewriteKeyInvalid: "Use one unused letter. E, L, U and common shortcut letters are taken.",
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
