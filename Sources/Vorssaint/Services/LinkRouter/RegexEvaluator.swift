// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Evaluates user regexes off the main thread and races a deadline.
/// NSRegularExpression cannot be cancelled, so a pathological pattern keeps a
/// worker busy until it finishes; the caller simply stops waiting for it.
/// Completions are always delivered on the main queue, exactly once.
final class RegexEvaluator: RegexEvaluating {
    private let deadline: TimeInterval
    private let workQueue = DispatchQueue(label: "com.vorssaint.link-router.regex",
                                          qos: .userInitiated, attributes: .concurrent)
    private let lock = NSLock()
    private var compiled: [String: NSRegularExpression] = [:]
    private var rejected: Set<String> = []

    init(deadline: TimeInterval = 0.25) {
        self.deadline = deadline
    }

    func evaluate(pattern: String, in text: String, completion: @escaping (RegexOutcome) -> Void) {
        guard let regex = regex(for: pattern) else {
            DispatchQueue.main.async { completion(.invalid) }
            return
        }
        let once = Once(completion)
        workQueue.async {
            let range = NSRange(text.startIndex..., in: text)
            once.fire(regex.firstMatch(in: text, options: [], range: range) != nil ? .match : .noMatch)
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + deadline) {
            once.fire(.timedOut)
        }
    }

    private func regex(for pattern: String) -> NSRegularExpression? {
        lock.lock(); defer { lock.unlock() }
        if rejected.contains(pattern) { return nil }
        if let cached = compiled[pattern] { return cached }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            rejected.insert(pattern)
            return nil
        }
        compiled[pattern] = regex
        return regex
    }

    private final class Once<Outcome> {
        private let lock = NSLock()
        private var fired = false
        private let completion: (Outcome) -> Void
        init(_ completion: @escaping (Outcome) -> Void) { self.completion = completion }
        func fire(_ outcome: Outcome) {
            lock.lock()
            let first = !fired
            fired = true
            lock.unlock()
            guard first else { return }
            DispatchQueue.main.async { self.completion(outcome) }
        }
    }
}

extension RegexEvaluator: RegexReplacing {
    /// Longest result accepted. A URL this long is not a link anyone meant;
    /// the cap stops a template from ballooning a rewrite.
    static let maxReplacementLength = 8192

    func replace(pattern: String, in text: String, template: String,
                 completion: @escaping (RegexReplaceOutcome) -> Void) {
        guard let regex = regex(for: pattern) else {
            DispatchQueue.main.async { completion(.invalid) }
            return
        }
        let once = Once(completion)
        workQueue.async {
            let range = NSRange(text.startIndex..., in: text)
            guard regex.firstMatch(in: text, options: [], range: range) != nil else {
                once.fire(.noMatch)
                return
            }
            let replaced = regex.stringByReplacingMatches(in: text, options: [], range: range,
                                                          withTemplate: template)
            once.fire(replaced.count <= Self.maxReplacementLength ? .replaced(replaced) : .invalid)
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + deadline) {
            once.fire(.timedOut)
        }
    }
}
