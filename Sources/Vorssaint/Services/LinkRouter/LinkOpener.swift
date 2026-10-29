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

    /// Like `open(_:)`, but reports a launch the system refused. A web link is
    /// queued on the router, which always ends in a browser, so it reports
    /// success.
    static func open(_ url: URL, completion: @escaping (Error?) -> Void) {
        if LinkCanonical.isWeb(url) {
            LinkRouterService.shared.route(LinkRequest(urls: [url], senderBundleID: nil, allowsPicker: false))
            completion(nil)
            return
        }
        NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            completion(error)
        }
    }

    /// Non-web links (mailto:, app schemes, files) are never routed. This is
    /// one of the two bare NSWorkspace opens in the router code, and the only
    /// ones the guard test allows here.
    @discardableResult
    static func openNonWeb(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}
