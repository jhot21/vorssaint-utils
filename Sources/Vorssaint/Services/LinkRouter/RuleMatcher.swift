// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum RegexOutcome: Equatable { case match, noMatch, invalid, timedOut }

/// Regex matching is asynchronous because NSRegularExpression can neither time
/// out nor be cancelled; the concrete evaluator races a deadline instead.
protocol RegexEvaluating: AnyObject {
    func evaluate(pattern: String, in text: String, completion: @escaping (RegexOutcome) -> Void)
}

struct RuleFailure: Equatable {
    let id: UUID
    let flag: RoutingRule.Flag
}

struct RuleMatchResult: Equatable {
    var rule: RoutingRule?
    var failures: [RuleFailure]
}

enum RuleMatcher {
    static let maxRegexPatternLength = 256
    static let maxRegexTextLength = 2048

    /// First enabled rule, in list order, that matches. Glob rules resolve
    /// synchronously; a regex rule hands off to the evaluator and the search
    /// resumes from its completion. Completion is called exactly once.
    static func firstMatch(url: URL, sourceApp: String?, rules: [RoutingRule],
                           evaluator: RegexEvaluating,
                           completion: @escaping (RuleMatchResult) -> Void) {
        guard let link = LinkCanonical.link(for: url) else {
            completion(RuleMatchResult(rule: nil, failures: []))
            return
        }
        var failures: [RuleFailure] = []

        func step(_ index: Int) {
            guard index < rules.count else {
                completion(RuleMatchResult(rule: nil, failures: failures))
                return
            }
            let rule = rules[index]
            guard rule.isEnabled, sourceMatches(rule, sourceApp) else { step(index + 1); return }
            switch rule.kind {
            case .glob:
                if GlobMatcher.matches(pattern: rule.pattern, link: link) {
                    completion(RuleMatchResult(rule: rule, failures: failures))
                } else {
                    step(index + 1)
                }
            case .regex:
                guard rule.pattern.count <= maxRegexPatternLength else {
                    failures.append(RuleFailure(id: rule.id, flag: .invalidRegex))
                    step(index + 1)
                    return
                }
                let text = url.absoluteString
                guard text.count <= maxRegexTextLength else { step(index + 1); return }
                evaluator.evaluate(pattern: rule.pattern, in: text) { outcome in
                    switch outcome {
                    case .match:
                        completion(RuleMatchResult(rule: rule, failures: failures))
                    case .noMatch:
                        step(index + 1)
                    case .invalid:
                        failures.append(RuleFailure(id: rule.id, flag: .invalidRegex))
                        step(index + 1)
                    case .timedOut:
                        failures.append(RuleFailure(id: rule.id, flag: .tooSlow))
                        step(index + 1)
                    }
                }
            }
        }
        step(0)
    }

    private static func sourceMatches(_ rule: RoutingRule, _ sourceApp: String?) -> Bool {
        guard let required = rule.sourceAppBundleID, !required.isEmpty else { return true }
        return sourceApp == required
    }
}
