// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum UnshortenFailure: Equatable { case timedOut, tooManyHops, loop, notWeb, network }
enum UnshortenOutcome: Equatable { case resolved(URL), noRedirect, failed(UnshortenFailure) }

/// Resolves a short link. The completion arrives on the main queue, exactly
/// once, like `RegexReplacing`.
protocol LinkUnshortening: AnyObject {
    func resolve(_ url: URL, shorteners: ShortenerRules, completion: @escaping (UnshortenOutcome) -> Void)
}

/// What one request to a shortener answered. A redirect carries the already
/// resolved absolute `Location`; everything that is not a redirect with a
/// usable location is `noRedirect`.
enum HopResponse: Equatable { case redirect(URL), noRedirect, failed }

/// One request at a time, sharing a single session for the chain. The seam
/// exists so the chain logic is tested without a network.
protocol HopFetching: AnyObject {
    /// Completion on the main queue, at most once, never after `cancel()`.
    func fetch(_ url: URL, method: String, completion: @escaping (HopResponse) -> Void)
    func cancel()
}

/// Owned by the router service so its cache outlives the per-link picker
/// models. Main thread only.
final class LinkUnshortener: LinkUnshortening {
    static let maxHops = 5
    static let defaultBudget: TimeInterval = 6

    private let budget: TimeInterval
    private let makeFetcher: () -> HopFetching
    /// Short link to destination, for this run of the app only. Failures are
    /// never stored, and nothing is written to disk.
    private var cache: [URL: URL] = [:]

    init(budget: TimeInterval = LinkUnshortener.defaultBudget, makeFetcher: @escaping () -> HopFetching) {
        self.budget = budget
        self.makeFetcher = makeFetcher
    }

    func resolve(_ url: URL, shorteners: ShortenerRules, completion: @escaping (UnshortenOutcome) -> Void) {
        if let hit = cache[url] {
            DispatchQueue.main.async { completion(.resolved(hit)) }
            return
        }
        Chain(origin: url, rules: shorteners, fetcher: makeFetcher(), budget: budget) { [weak self] outcome in
            if case .resolved(let destination) = outcome { self?.cache[url] = destination }
            completion(outcome)
        }.start()
    }

    private final class Chain {
        private var current: URL
        private var hops = 0
        private var visited: Set<URL>
        private var finished = false
        private var deadline: DispatchWorkItem?
        private let rules: ShortenerRules
        private let fetcher: HopFetching
        private let budget: TimeInterval
        private let completion: (UnshortenOutcome) -> Void

        init(origin: URL, rules: ShortenerRules, fetcher: HopFetching, budget: TimeInterval,
             completion: @escaping (UnshortenOutcome) -> Void) {
            self.current = origin
            self.visited = [origin]
            self.rules = rules
            self.fetcher = fetcher
            self.budget = budget
            self.completion = completion
        }

        func start() {
            let work = DispatchWorkItem { [self] in finish(.failed(.timedOut)) }
            deadline = work
            DispatchQueue.main.asyncAfter(deadline: .now() + budget, execute: work)
            step(method: "HEAD")
        }

        private func step(method: String) {
            fetcher.fetch(current, method: method) { [self] response in handle(response, method: method) }
        }

        private func handle(_ response: HopResponse, method: String) {
            guard !finished else { return }
            switch response {
            case .failed:
                finish(.failed(.network))
            case .noRedirect:
                if method == "HEAD" {
                    step(method: "GET")
                } else {
                    // A shortener that answers without redirecting is not a
                    // destination, at the first hop or any later one, so it
                    // is never reported as resolved.
                    finish(.noRedirect)
                }
            case .redirect(let next):
                guard LinkCanonical.isWeb(next), let host = next.host, !host.isEmpty else {
                    finish(.failed(.notWeb))
                    return
                }
                hops += 1
                guard visited.insert(next).inserted else { finish(.failed(.loop)); return }
                guard ShortenerHosts.isShortener(next, rules: rules) else { finish(.resolved(next)); return }
                guard hops < LinkUnshortener.maxHops else { finish(.failed(.tooManyHops)); return }
                current = next
                step(method: "HEAD")
            }
        }

        private func finish(_ outcome: UnshortenOutcome) {
            guard !finished else { return }
            finished = true
            // Cancelling the timer lets a chain that resolved quickly be
            // released now instead of at the deadline.
            deadline?.cancel()
            deadline = nil
            fetcher.cancel()
            completion(outcome)
        }
    }
}
