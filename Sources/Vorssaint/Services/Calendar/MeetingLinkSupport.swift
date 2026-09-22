// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum MeetingProvider: String, CaseIterable, Sendable {
    case zoom, googleMeet, microsoftTeams
}

struct MeetingLink: Equatable, Sendable {
    let provider: MeetingProvider
    let browserURL: URL
    /// nil for Google Meet, and for a Zoom personal-room link (`/my/<name>`)
    /// — see MeetingLinkSupport.detect(for:).
    let nativeAppURL: URL?
}

/// How long before (or at) a meeting's start to notify. Raw values are the
/// persisted `DefaultsKey.meetingJoinNotifyOffset` value — stable once
/// shipped.
enum MeetingJoinNotifyOffset: String, CaseIterable, Sendable {
    case atStart, oneMinuteBefore, threeMinutesBefore, fiveMinutesBefore

    var seconds: TimeInterval {
        switch self {
        case .atStart: return 0
        case .oneMinuteBefore: return 60
        case .threeMinutesBefore: return 180
        case .fiveMinutesBefore: return 300
        }
    }
}

/// Pure link detection and notification-scheduling decisions, no
/// EventKit/UserNotifications imports — fully testable like
/// `CalendarSupport.swift`. `MeetingNotificationService` is the only
/// consumer that talks to `UNUserNotificationCenter`; everything here is a
/// plain function of its inputs.
enum MeetingLinkSupport {
    /// A trigger more than this far in the past is treated as over and is
    /// never scheduled; a trigger within this window is clamped to fire
    /// immediately instead of being dropped (Non-goals: bounded grace
    /// window for a meeting already in progress).
    static let gracePeriod: TimeInterval = 600

    /// Tries `event.url`, then `event.location`, then `event.notes`, in
    /// that order; the first source that matches any provider's pattern
    /// wins, and the event is never scanned for a second provider.
    static func detect(for event: CalendarEvent) -> MeetingLink? {
        let candidates = [event.url?.absoluteString, event.location, event.notes]
        for candidate in candidates {
            guard let candidate, !candidate.isEmpty else { continue }
            if let link = link(in: candidate) { return link }
        }
        return nil
    }

    private static func link(in text: String) -> MeetingLink? {
        if let match = firstMatch(of: zoomRegex, in: text) {
            let isPersonalRoom = match.contains("/my/")
            let native = (isPersonalRoom ? nil : zoomConfno(from: match))
                .flatMap { URL(string: "zoommtg://zoom.us/join?confno=" + $0) }
            return MeetingLink(provider: .zoom, browserURL: URL(string: match) ?? URL.aboutBlank,
                               nativeAppURL: native)
                .validated
        }
        if let match = firstMatch(of: googleMeetRegex, in: text) {
            return MeetingLink(provider: .googleMeet, browserURL: URL(string: match) ?? URL.aboutBlank,
                               nativeAppURL: nil).validated
        }
        if let match = firstMatch(of: teamsRegex, in: text) {
            let native = match.replacingOccurrences(of: "https://", with: "msteams://")
                .replacingOccurrences(of: "http://", with: "msteams://")
            return MeetingLink(provider: .microsoftTeams, browserURL: URL(string: match) ?? URL.aboutBlank,
                               nativeAppURL: URL(string: native)).validated
        }
        return nil
    }

    // Host-anchored: the registrable domain must actually be zoom.us/zoom.com,
    // not merely appear as a substring anywhere before the first "/".
    private static let zoomRegex =
        #"https?://(?:[\w-]+\.)*zoom\.(?:us|com)/(?:j|my|webinar)/[^\s"'<>]+"#
    // Meet's actual xxx-xxxx-xxx room-code shape; excludes non-room paths
    // like /landing or /about.
    private static let googleMeetRegex =
        #"https?://meet\.google\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}"#
    private static let teamsRegex =
        #"https?://teams\.(?:microsoft|live)\.com/l/meetup-join/[^\s"'<>]+"#

    private static func firstMatch(of pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let matchRange = Range(match.range, in: text) else { return nil }
        return trimmingTrailingPunctuation(String(text[matchRange]))
    }

    /// The URL character classes (`[^\s"'<>]+`) deliberately admit every
    /// non-space URL character, so a link ending a sentence or sitting
    /// inside parentheses captures its trailing `.`/`)`/`,` etc. into the
    /// match; left alone that punctuation leaks into `browserURL` and, for
    /// Zoom, into the `confno=` deep link. Stripped repeatedly so `).`
    /// trims to nothing.
    private static func trimmingTrailingPunctuation(_ text: String) -> String {
        let trailing: Set<Character> = [".", ",", ";", ":", "!", "?", ")", "]"]
        var trimmed = text
        while let last = trimmed.last, trailing.contains(last) {
            trimmed.removeLast()
        }
        return trimmed
    }

    /// Extracts a Zoom meeting id from a `/j/<id>` or `/webinar/<id>` link's
    /// path component for building the `zoommtg://` deep link's `confno`
    /// parameter. Returns nil for any shape it doesn't recognize — a `/my/`
    /// personal-room link never reaches this (see `link(in:)`), and a
    /// non-numeric component (e.g. `/webinar/register/WN_…`, a registration
    /// landing page, not a join) would otherwise become a garbage `confno`.
    private static func zoomConfno(from urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        let components = url.pathComponents
        guard let anchorIndex = components.firstIndex(where: { $0 == "j" || $0 == "webinar" }),
              anchorIndex + 1 < components.count else { return nil }
        let id = components[anchorIndex + 1]
        guard !id.isEmpty, id.allSatisfy(\.isNumber) else { return nil }
        return id
    }

    /// `event.start` minus the configured offset, or nil when that trigger
    /// is more than `gracePeriod` seconds in the past. A trigger inside the
    /// grace window is clamped to fire one second from `now` rather than at
    /// its original (past) time.
    static func triggerDate(for event: CalendarEvent, offset: MeetingJoinNotifyOffset,
                            now: Date) -> Date? {
        let trigger = event.start.addingTimeInterval(-offset.seconds)
        if trigger >= now { return trigger }
        let elapsed = now.timeIntervalSince(trigger)
        guard elapsed <= gracePeriod else { return nil }
        return now.addingTimeInterval(1)
    }

    /// The full set of notification identifiers that should exist right
    /// now: one per non-all-day event with a detected link and a
    /// schedulable trigger date. Identifiers are `event.id` — the same
    /// occurrence-qualified id `CalendarEvent` already guarantees is unique.
    static func desiredNotificationIDs(events: [CalendarEvent], offset: MeetingJoinNotifyOffset,
                                       now: Date = Date()) -> Set<String> {
        Set(events.compactMap { event -> String? in
            guard !event.allDay, detect(for: event) != nil,
                  triggerDate(for: event, offset: offset, now: now) != nil else { return nil }
            return event.id
        })
    }

    /// What to add and remove to make `scheduled` match `desired`, touching
    /// nothing already correct.
    static func reconcileDiff(desired: Set<String>,
                              scheduled: Set<String>) -> (toAdd: Set<String>, toRemove: Set<String>) {
        (toAdd: desired.subtracting(scheduled), toRemove: scheduled.subtracting(desired))
    }
}

private extension MeetingLink {
    /// A malformed browserURL (regex matched but `URL(string:)` failed on
    /// stray characters) is treated as no match at all, never a link with a
    /// placeholder URL.
    var validated: MeetingLink? {
        browserURL == URL.aboutBlank ? nil : self
    }
}

private extension URL {
    static let aboutBlank = URL(string: "about:blank")!
}
