// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum LinkRouterStringsTests {
    static func run(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.linkRouter(language)
            let values = Mirror(reflecting: strings).children.compactMap { $0.value as? String }
            let tag = language.rawValue
            suite.expect(values.count == 37 && values.allSatisfy { !$0.isEmpty },
                         "link router strings are complete (\(tag))")
            suite.expect(values.allSatisfy { !$0.contains("\u{2014}") },
                         "link router strings contain no em dash (\(tag))")
            let angled = values.contains { $0.contains("\u{00AB}") || $0.contains("\u{00BB}") }
            suite.expect(angled == false || language == .fr || language == .ru,
                         "link router strings use angled quotes only in French and Russian (\(tag))")
            suite.expect(!values.contains { $0.contains("\u{201E}") } || language == .de,
                         "link router strings use the low quote only in German (\(tag))")
            suite.expect(strings.statusOtherFormat.components(separatedBy: "%@").count == 2
                            && strings.testMatchFormat.components(separatedBy: "%@").count == 2
                            && strings.ruleAddedFormat.components(separatedBy: "%@").count == 2
                            && strings.waitingFormat.components(separatedBy: "%d").count == 2,
                         "link router format strings carry exactly one specifier (\(tag))")
        }
    }
}
