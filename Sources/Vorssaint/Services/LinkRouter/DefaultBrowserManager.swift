// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// What the manager needs from LaunchServices, so tests can fake it.
protocol DefaultHandlerBackend {
    func currentHandler(forScheme scheme: String) -> String?
    func setHandler(bundleID: String, forScheme scheme: String, completion: @escaping (Error?) -> Void)
    func isInstalled(bundleID: String) -> Bool
}

struct WorkspaceHandlerBackend: DefaultHandlerBackend {
    func currentHandler(forScheme scheme: String) -> String? {
        guard let probe = URL(string: "\(scheme)://example.com"),
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: probe) else { return nil }
        return Bundle(url: appURL)?.bundleIdentifier
    }

    func setHandler(bundleID: String, forScheme scheme: String, completion: @escaping (Error?) -> Void) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            completion(NSError(domain: "LinkRouter", code: 1))
            return
        }
        // macOS shows its own confirmation dialog; the person may decline.
        NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: scheme) { error in
            DispatchQueue.main.async { completion(error) }
        }
    }

    func isInstalled(bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }
}

/// Captures the browser that was default before Vorssaint, makes Vorssaint the
/// handler for http and https, and gives the role back. Nothing here runs
/// unless the person asked: enabling the feature never changes the default.
final class DefaultBrowserManager {
    enum Status: Equatable { case isDefault, other(String?), partial }
    enum RestoreResult: Equatable { case restored, notDefault, noPrevious, previousMissing, failed }
    enum MakeDefaultResult: Equatable { case set, unavailable, failed }

    private static let schemes = ["https", "http"]

    /// A development build that became the default and was then deleted
    /// would strand every link, so it is never allowed to.
    static var allowsMakingDefaultInThisBuild: Bool {
        #if VORSSAINT_DEVELOPMENT
        return false
        #else
        return true
        #endif
    }

    private let backend: DefaultHandlerBackend
    private let selfBundleID: String
    private let defaults: UserDefaults
    private let allowsMakingDefault: Bool

    init(backend: DefaultHandlerBackend = WorkspaceHandlerBackend(),
         selfBundleID: String = BrowserCatalog.ownBundleID,
         defaults: UserDefaults = .standard,
         allowsMakingDefault: Bool = DefaultBrowserManager.allowsMakingDefaultInThisBuild) {
        self.backend = backend
        self.selfBundleID = selfBundleID
        self.defaults = defaults
        self.allowsMakingDefault = allowsMakingDefault
    }

    var canMakeDefault: Bool { allowsMakingDefault }

    var previousBundleID: String? {
        let value = defaults.string(forKey: DefaultsKey.linkRouterPreviousDefault) ?? ""
        return value.isEmpty ? nil : value
    }

    var status: Status {
        let handlers = Self.schemes.map { backend.currentHandler(forScheme: $0) }
        if handlers.allSatisfy({ $0 == selfBundleID }) { return .isDefault }
        if handlers.contains(where: { $0 == selfBundleID }) { return .partial }
        return .other(handlers.first ?? nil)
    }

    func makeDefault(completion: @escaping (MakeDefaultResult) -> Void) {
        guard allowsMakingDefault else { completion(.unavailable); return }
        // Only capture while someone else still owns https, so a second tap
        // can never replace the real previous browser with Vorssaint.
        if let current = backend.currentHandler(forScheme: "https"), current != selfBundleID {
            defaults.set(current, forKey: DefaultsKey.linkRouterPreviousDefault)
        }
        setAll(to: selfBundleID) { ok in completion(ok ? .set : .failed) }
    }

    func restorePrevious(completion: @escaping (RestoreResult) -> Void) {
        let owned = Self.schemes.contains { backend.currentHandler(forScheme: $0) == selfBundleID }
        guard owned else { completion(.notDefault); return }
        guard let previous = previousBundleID else { completion(.noPrevious); return }
        guard backend.isInstalled(bundleID: previous) else { completion(.previousMissing); return }
        setAll(to: previous) { [defaults] ok in
            if ok { defaults.removeObject(forKey: DefaultsKey.linkRouterPreviousDefault) }
            completion(ok ? .restored : .failed)
        }
    }

    /// Sets `http` first, then `https`. On macOS, `http` moves both schemes,
    /// while `https` on its own reports a permissions error (-54) even when
    /// the handler is already right (found by the spike). So an individual
    /// error is not trusted: success means both handlers read back as the
    /// requested browser.
    private func setAll(to bundleID: String, completion: @escaping (Bool) -> Void) {
        var remaining = ["http", "https"]
        func next() {
            guard let scheme = remaining.first else {
                completion(Self.schemes.allSatisfy { backend.currentHandler(forScheme: $0) == bundleID })
                return
            }
            remaining.removeFirst()
            backend.setHandler(bundleID: bundleID, forScheme: scheme) { _ in next() }
        }
        next()
    }
}
