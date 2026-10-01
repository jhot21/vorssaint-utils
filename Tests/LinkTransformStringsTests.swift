// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum LinkTransformStringsTests {
    static func run(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.linkTransform(language)
            let values = Mirror(reflecting: strings).children.compactMap { $0.value as? String }
            let tag = language.rawValue
            suite.expect(values.count == 39 && values.allSatisfy { !$0.isEmpty },
                         "link transform strings are complete (\(tag))")
            suite.expect(values.allSatisfy { !$0.contains("\u{2014}") },
                         "link transform strings contain no em dash (\(tag))")
            suite.expect(strings.rewriteTestResultFormat.components(separatedBy: "%@").count == 2
                            && strings.ruleAddedWithFormat.components(separatedBy: "%@").count == 3,
                         "link transform format strings carry the right number of specifiers (\(tag))")
        }
    }
}
