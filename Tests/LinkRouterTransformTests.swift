// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum LinkRouterTransformTests {
    static func run(_ suite: TestSuite) {
        runReplace(suite)
    }

    private static func replace(_ evaluator: RegexEvaluator, _ pattern: String, _ text: String,
                                _ template: String) -> RegexReplaceOutcome? {
        var outcome: RegexReplaceOutcome?
        evaluator.replace(pattern: pattern, in: text, template: template) { outcome = $0 }
        LinkRouterTestSupport.spin { outcome != nil }
        return outcome
    }

    private static func runReplace(_ suite: TestSuite) {
        let evaluator = RegexEvaluator(deadline: 0.25)
        suite.expect(replace(evaluator, #"^https://www\.youtube\.com/watch\?v=([\w-]+).*$"#,
                             "https://www.youtube.com/watch?v=abc_123&t=5",
                             "https://yt.example.test/watch?v=$1")
                        == .replaced("https://yt.example.test/watch?v=abc_123"),
                     "a rewrite substitutes capture groups with $1")
        suite.expect(replace(evaluator, #"^https://x\.test/"#, "https://y.test/", "z") == .noMatch,
                     "a pattern that does not match reports noMatch, not an unchanged replacement")
        suite.expect(replace(evaluator, "([", "https://x.test", "z") == .invalid,
                     "an unparsable pattern is invalid")
        let quick = RegexEvaluator(deadline: 0.05)
        suite.expect(replace(quick, "(a+)+$", String(repeating: "a", count: 34) + "b", "z") == .timedOut,
                     "a catastrophic pattern times out instead of hanging")
        suite.expect(replace(evaluator, "^", "https://x.test",
                             String(repeating: "x", count: RegexEvaluator.maxReplacementLength + 1)) == .invalid,
                     "a replacement longer than the cap is rejected")
    }
}
