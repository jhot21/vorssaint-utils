// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum MeetingLinkFeatureTests {
    static func run(_ suite: TestSuite) {
        let day = Calendar.current.startOfDay(for: Date())

        func makeEvent(id: String = "e1", start: Date = Date(), end: Date? = nil,
                       allDay: Bool = false, location: String = "",
                       url: URL? = nil, notes: String? = nil) -> CalendarEvent {
            CalendarEvent(id: id, calendarItemIdentifier: id, title: "Meeting",
                         calendarID: "cal", calendarTitle: "Cal", color: .fallback,
                         start: start, end: end ?? start.addingTimeInterval(1800),
                         allDay: allDay, location: location, recurring: false,
                         url: url, notes: notes)
        }

        // MARK: Source priority

        let bothMatch = makeEvent(url: URL(string: "https://meet.google.com/abc-defg-hij"),
                                  notes: "https://zoom.us/j/123456789")
        suite.expect(MeetingLinkSupport.detect(for: bothMatch)?.provider == .googleMeet,
               "url is scanned before notes when both match (source priority)")
        let locationOverNotes = makeEvent(location: "https://zoom.us/j/123456789",
                                          notes: "https://meet.google.com/abc-defg-hij")
        suite.expect(MeetingLinkSupport.detect(for: locationOverNotes)?.provider == .zoom,
               "location is scanned before notes when both match")

        // MARK: Each provider, real-shaped link

        suite.expect(MeetingLinkSupport.detect(for: makeEvent(
            notes: "Join: https://zoom.us/j/123456789?pwd=abcXYZ"))?.provider == .zoom,
               "a real-shaped Zoom /j/ link is detected")
        suite.expect(MeetingLinkSupport.detect(for: makeEvent(
            notes: "https://meet.google.com/abc-defg-hij"))?.provider == .googleMeet,
               "a real-shaped Google Meet link is detected")
        suite.expect(MeetingLinkSupport.detect(for: makeEvent(
            notes: "https://teams.microsoft.com/l/meetup-join/19%3ameeting_ABC%40thread.v2/0"
        ))?.provider == .microsoftTeams,
               "a real-shaped Teams /l/meetup-join/ link is detected")
        suite.expect(MeetingLinkSupport.detect(for: makeEvent(
            notes: "https://teams.live.com/l/meetup-join/19%3ameeting_ABC%40thread.v2/0"
        ))?.provider == .microsoftTeams,
               "teams.live.com is recognized as Microsoft Teams")

        // MARK: Named false-positive/truncation regressions (from spec review)

        suite.expect(MeetingLinkSupport.detect(for: makeEvent(notes: "https://evilzoom.com/j/12345")) == nil,
               "an unrelated host containing 'zoom' is never mistaken for Zoom")
        suite.expect(MeetingLinkSupport.detect(for: makeEvent(notes: "https://myzoom.us/j/12345")) == nil,
               "an unrelated host containing 'zoom.us' as a substring is never mistaken for Zoom")
        suite.expect(MeetingLinkSupport.detect(for: makeEvent(notes: "See https://meet.google.com/landing")) == nil,
               "Google Meet's own landing page is not a meeting link")
        suite.expect(MeetingLinkSupport.detect(for: makeEvent(notes: "See https://meet.google.com/about")) == nil,
               "Google Meet's own about page is not a meeting link")
        let teamsWithAt = makeEvent(notes:
            "https://teams.microsoft.com/l/meetup-join/19:meeting_ABC@thread.v2/0?context=abc")
        suite.expect(MeetingLinkSupport.detect(for: teamsWithAt)?.browserURL.absoluteString.hasSuffix("context=abc") == true,
               "a literal '@' in a Teams organizer/thread-id segment does not truncate the match")
        let zoomWithDottedQuery = makeEvent(notes: "https://company.zoom.us/j/123456789?pwd=Ab.C%2F1-2")
        suite.expect(MeetingLinkSupport.detect(for: zoomWithDottedQuery)?.browserURL.absoluteString
                .contains("pwd=Ab.C%2F1-2") == true,
               "a Zoom query string containing '.', '%%', and '/' is captured in full")

        // MARK: Zoom subdomain and personal room

        suite.expect(MeetingLinkSupport.detect(for: makeEvent(
            notes: "https://company.zoom.us/j/123456789"))?.provider == .zoom,
               "a legitimate company subdomain of zoom.us is still recognized")
        let personalRoom = makeEvent(notes: "https://zoom.us/my/jane.doe")
        let personalRoomLink = MeetingLinkSupport.detect(for: personalRoom)
        suite.expect(personalRoomLink?.provider == .zoom && personalRoomLink?.nativeAppURL == nil,
               "a Zoom personal-room link detects as Zoom but has no native deep link")

        // MARK: No match

        suite.expect(MeetingLinkSupport.detect(for: makeEvent(notes: "Lunch with the team, no video call")) == nil,
               "plain text with no provider link returns nil")
        suite.expect(MeetingLinkSupport.detect(for: makeEvent()) == nil,
               "an event with empty url/location/notes returns nil")

        // MARK: Native app URLs

        let zoomLink = MeetingLinkSupport.detect(for: makeEvent(notes: "https://zoom.us/j/123456789?pwd=xyz"))
        suite.expect(zoomLink?.nativeAppURL?.absoluteString.hasPrefix("zoommtg://") == true,
               "a joinable Zoom link produces a zoommtg:// native URL")
        let meetLink = MeetingLinkSupport.detect(for: makeEvent(notes: "https://meet.google.com/abc-defg-hij"))
        suite.expect(meetLink?.nativeAppURL == nil, "Google Meet never has a native app URL")
        let teamsLink = MeetingLinkSupport.detect(for: makeEvent(
            notes: "https://teams.microsoft.com/l/meetup-join/19%3ameeting_ABC%40thread.v2/0"))
        suite.expect(teamsLink?.nativeAppURL?.absoluteString.hasPrefix("msteams://") == true,
               "a joinable Teams link produces an msteams:// native URL")

        // MARK: Trigger date + 10-minute grace window

        let offsetNone = MeetingJoinNotifyOffset.atStart
        let future = makeEvent(start: day.addingTimeInterval(3600))
        suite.expect(MeetingLinkSupport.triggerDate(for: future, offset: offsetNone, now: day) != nil,
               "a future event's trigger date is scheduled")
        let justMissed = makeEvent(start: day.addingTimeInterval(-300)) // 5 minutes ago
        let clamped = MeetingLinkSupport.triggerDate(for: justMissed, offset: offsetNone, now: day)
        suite.expect(clamped != nil && clamped! > day,
               "an event whose trigger passed less than 10 minutes ago is still scheduled, clamped to fire immediately")
        let longMissed = makeEvent(start: day.addingTimeInterval(-700)) // ~11.7 minutes ago
        suite.expect(MeetingLinkSupport.triggerDate(for: longMissed, offset: offsetNone, now: day) == nil,
               "an event whose trigger passed more than 10 minutes ago is not scheduled")
        let fiveBefore = MeetingJoinNotifyOffset.fiveMinutesBefore
        let withOffset = makeEvent(start: day.addingTimeInterval(3600))
        suite.expect(MeetingLinkSupport.triggerDate(for: withOffset, offset: fiveBefore, now: day)
                == day.addingTimeInterval(3600 - 300),
               "the fiveMinutesBefore offset subtracts exactly 300 seconds from the event start")

        // MARK: Reconcile decision logic

        let qualifying = makeEvent(id: "q1", start: day.addingTimeInterval(3600),
                                   notes: "https://zoom.us/j/123456789")
        let nonQualifying = makeEvent(id: "n1", start: day.addingTimeInterval(3600), notes: "no link here")
        let allDayWithLink = makeEvent(id: "ad1", start: day, allDay: true,
                                       notes: "https://zoom.us/j/123456789")
        let desired = MeetingLinkSupport.desiredNotificationIDs(
            events: [qualifying, nonQualifying, allDayWithLink], offset: .atStart, now: day)
        suite.expect(desired == ["q1"],
               "only non-all-day events with a detected link and a schedulable trigger are desired")

        let diffAdding = MeetingLinkSupport.reconcileDiff(desired: ["a", "b"], scheduled: ["a"])
        suite.expect(diffAdding.toAdd == ["b"] && diffAdding.toRemove.isEmpty,
               "a desired id not yet scheduled is added, and nothing already-correct is touched")
        let diffRemoving = MeetingLinkSupport.reconcileDiff(desired: ["a"], scheduled: ["a", "b"])
        suite.expect(diffRemoving.toAdd.isEmpty && diffRemoving.toRemove == ["b"],
               "a scheduled id no longer desired is removed")
        let diffNoOp = MeetingLinkSupport.reconcileDiff(desired: ["a"], scheduled: ["a"])
        suite.expect(diffNoOp.toAdd.isEmpty && diffNoOp.toRemove.isEmpty,
               "an already-correct set produces no changes")
    }
}
