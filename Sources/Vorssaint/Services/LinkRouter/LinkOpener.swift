// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The one sanctioned way to open a link from inside Vorssaint when no
/// browser was chosen explicitly. A bare NSWorkspace open of a web URL would
/// be handed back to Vorssaint by LaunchServices once it is the default
/// browser, so web links go through the router, which always ends in a
/// concrete browser. The person's rules apply, but an in-app link never pops
/// the picker: with no matching rule it opens in the fallback browser. Sites that already open with `withApplicationAt` (the
/// person picked the browser) bypass this deliberately.
enum LinkOpener {
    @discardableResult
    static func open(_ url: URL) -> Bool {
        if LinkCanonical.isWeb(url) {
            LinkRouterService.shared.route(LinkRequest(urls: [url], senderBundleID: nil, allowsPicker: false))
            return true
        }
        return openNonWeb(url)
    }

    /// Non-web links (mailto:, app schemes, files) are never routed. This is
    /// the single bare NSWorkspace open in the router code, and the only one
    /// the guard test allows here.
    @discardableResult
    static func openNonWeb(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}
