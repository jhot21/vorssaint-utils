// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum UnshortenState: Equatable { case notRun, resolved, noRedirect, failed }

struct PipelineOutcome: Equatable {
    var result: TransformResult
    var unshorten: UnshortenState
}

/// Extract, then Unshorten (asynchronous), then Clean. The picker and the
/// auto-open path both run it, so they cannot disagree about the order. Rewrites
/// stay separate and run after it.
enum LinkPipeline {
    /// The one predicate for "this run will contact a shortener", given the
    /// link as it is after Extract. The picker model asks it too, so what it
    /// shows as pending and what the pipeline does cannot drift apart.
    static func needsLookup(_ extractedURL: URL, chips: TransformChips, settings: TransformSettings) -> Bool {
        chips.contains(.unshorten) && ShortenerHosts.isShortener(extractedURL, rules: settings.shorteners)
    }

    /// Completion is called exactly once: synchronously when Unshorten has
    /// nothing to do (not selected, no unshortener, or the link is not a
    /// listed shortener), otherwise on the main queue.
    static func run(_ url: URL, chips: TransformChips, settings: TransformSettings,
                    unshortener: LinkUnshortening?, completion: @escaping (PipelineOutcome) -> Void) {
        let extracted = LinkTransform.extract(url, chips: chips, settings: settings)
        guard let unshortener, needsLookup(extracted.url, chips: chips, settings: settings) else {
            completion(PipelineOutcome(result: LinkTransform.cleaned(extracted, chips: chips, settings: settings),
                                       unshorten: .notRun))
            return
        }
        unshortener.resolve(extracted.url, shorteners: settings.shorteners) { outcome in
            var result = extracted
            var state = UnshortenState.failed
            switch outcome {
            case .resolved(let destination):
                result.unshortenedFrom = extracted.url
                result.url = destination
                result.beforeClean = destination
                result.applied.insert(.unshorten)
                state = .resolved
            case .noRedirect:
                state = .noRedirect
            case .failed:
                state = .failed
            }
            completion(PipelineOutcome(result: LinkTransform.cleaned(result, chips: chips, settings: settings),
                                       unshorten: state))
        }
    }
}
