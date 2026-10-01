// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum LinkRouterDefaultBrowserTests {
    /// Mirrors what the spike found on macOS: setting `http` succeeds and
    /// moves both schemes, while setting `https` on its own reports a
    /// permissions error (-54) even though the handler may already be right.
    private final class FakeBackend: DefaultHandlerBackend {
        var handlers: [String: String] = ["http": "com.apple.Safari", "https": "com.apple.Safari"]
        var installed: Set<String> = ["com.apple.Safari", "com.google.Chrome", "me"]
        var failing = false
        var sets: [String] = []
        func currentHandler(forScheme scheme: String) -> String? { handlers[scheme] }
        func isInstalled(bundleID: String) -> Bool { installed.contains(bundleID) }
        func setHandler(bundleID: String, forScheme scheme: String, completion: @escaping (Error?) -> Void) {
            sets.append("\(scheme)=\(bundleID)")
            if failing { completion(NSError(domain: "test", code: 1)); return }
            if scheme == "http" {
                handlers["http"] = bundleID
                handlers["https"] = bundleID
                completion(nil)
            } else {
                completion(NSError(domain: NSOSStatusErrorDomain, code: -54))
            }
        }
    }

    static func run(_ suite: TestSuite) {
        let name = "vorss.tests.linkrouter.default"
        let defaults = UserDefaults(suiteName: name)!
        func fresh() -> (FakeBackend, DefaultBrowserManager) {
            defaults.removePersistentDomain(forName: name)
            let backend = FakeBackend()
            return (backend, DefaultBrowserManager(backend: backend, selfBundleID: "me", defaults: defaults,
                                                   allowsMakingDefault: true))
        }
        defer { defaults.removePersistentDomain(forName: name) }

        // Status
        var (backend, manager) = fresh()
        suite.expect(manager.status == .other("com.apple.Safari"), "another default browser is reported with its identifier")
        backend.handlers = ["http": "me", "https": "me"]
        suite.expect(manager.status == .isDefault, "both schemes owned by Vorssaint is the default state")
        backend.handlers = ["http": "com.apple.Safari", "https": "me"]
        suite.expect(manager.status == .partial, "owning only one scheme is reported as partial")
        backend.handlers = [:]
        suite.expect(manager.status == .other(nil), "no handler at all is reported without a name")
        backend.handlers = ["http": "com.google.Chrome", "https": "com.apple.Safari"]
        suite.expect(manager.status == .other("com.apple.Safari"),
                     "when http and https disagree, the https handler is the one named")

        // Make default captures the previous browser first, then sets both schemes.
        (backend, manager) = fresh()
        var made: DefaultBrowserManager.MakeDefaultResult?
        manager.makeDefault { made = $0 }
        suite.expect(made == .set && manager.status == .isDefault
                        && manager.previousBundleID == "com.apple.Safari"
                        && backend.sets.first == "http=me" && Set(backend.sets) == ["https=me", "http=me"],
                     "making Vorssaint the default stores the previous browser and sets http first, then https")

        // Making it default again must not overwrite the stored previous browser with Vorssaint.
        manager.makeDefault { _ in }
        suite.expect(manager.previousBundleID == "com.apple.Safari",
                     "the stored previous browser is never overwritten while Vorssaint is the handler")

        // Restore
        var restored: DefaultBrowserManager.RestoreResult?
        manager.restorePrevious { restored = $0 }
        suite.expect(restored == .restored && backend.handlers["https"] == "com.apple.Safari"
                        && backend.handlers["http"] == "com.apple.Safari",
                     "restoring hands both schemes back to the previous browser, despite the https permission error")
        suite.expect(manager.previousBundleID == nil, "a successful restore clears the stored browser")

        manager.restorePrevious { restored = $0 }
        suite.expect(restored == .notDefault, "restoring when Vorssaint is not the handler does nothing")

        (backend, manager) = fresh()
        backend.handlers = ["http": "me", "https": "me"]
        manager.restorePrevious { restored = $0 }
        suite.expect(restored == .noPrevious && backend.sets.isEmpty,
                     "restoring with nothing stored does not touch the system")

        (backend, manager) = fresh()
        manager.makeDefault { _ in }
        backend.installed.remove("com.apple.Safari")
        manager.restorePrevious { restored = $0 }
        suite.expect(restored == .previousMissing && backend.handlers["https"] == "me",
                     "a previous browser that was uninstalled is reported, not guessed")

        (backend, manager) = fresh()
        manager.makeDefault { _ in }
        backend.failing = true
        manager.restorePrevious { restored = $0 }
        suite.expect(restored == .failed && manager.previousBundleID == "com.apple.Safari",
                     "a failed restore keeps the stored browser so it can be retried")

        (backend, manager) = fresh()
        backend.failing = true
        manager.makeDefault { made = $0 }
        suite.expect(made == .failed, "a declined or failed set is reported")

        // Development builds may not become the default.
        defaults.removePersistentDomain(forName: name)
        let dev = DefaultBrowserManager(backend: backend, selfBundleID: "me", defaults: defaults,
                                        allowsMakingDefault: false)
        backend.failing = false
        backend.sets = []
        dev.makeDefault { made = $0 }
        suite.expect(made == .unavailable && backend.sets.isEmpty,
                     "a development build refuses to become the default browser")

        // Fallback browser: the live system handler beats the stored one.
        (backend, manager) = fresh()
        defaults.set("com.google.Chrome", forKey: DefaultsKey.linkRouterPreviousDefault)
        suite.expect(manager.effectiveFallbackBundleID == "com.apple.Safari",
                     "a live non-Vorssaint handler wins over a stale stored previous browser")
        backend.handlers = ["http": "me", "https": "me"]
        suite.expect(manager.effectiveFallbackBundleID == "com.google.Chrome",
                     "when Vorssaint is the handler the stored previous browser is used")
        backend.handlers = ["http": "com.vorssaint.utils.dev", "https": "com.vorssaint.utils.dev"]
        suite.expect(manager.effectiveFallbackBundleID == "com.google.Chrome",
                     "any Vorssaint build as the handler falls through to the stored browser")
        defaults.removeObject(forKey: DefaultsKey.linkRouterPreviousDefault)
        backend.handlers = ["http": "me", "https": "me"]
        suite.expect(manager.effectiveFallbackBundleID == nil,
                     "Vorssaint as handler with nothing stored gives no fallback")
        defaults.set("com.google.Chrome", forKey: DefaultsKey.linkRouterPreviousDefault)
        backend.handlers = ["http": "gone.browser", "https": "gone.browser"]
        suite.expect(manager.effectiveFallbackBundleID == "com.google.Chrome",
                     "a live handler that is not installed falls back to the stored browser")
        defaults.set("gone.too", forKey: DefaultsKey.linkRouterPreviousDefault)
        suite.expect(manager.effectiveFallbackBundleID == nil, "an uninstalled stored browser is not offered")
    }
}
