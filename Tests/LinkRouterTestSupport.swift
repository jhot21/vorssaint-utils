// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum LinkRouterTestSupport {
    /// Runs the main run loop until `done` or the timeout, so completions the
    /// production code delivers on the main queue can be observed.
    static func spin(timeout: TimeInterval = 5, until done: () -> Bool) {
        let end = Date().addingTimeInterval(timeout)
        while !done(), Date() < end {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }
}
