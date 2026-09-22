# Meeting join notifications (Phase 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace MeetingBar with a local-notification-driven "tap to join" flow for Zoom/Google Meet/Microsoft Teams meetings detected on calendar events already fetched by Phase 1's `CalendarService`.

**Architecture:** A new pure `MeetingLinkSupport` module detects a meeting link on a `CalendarEvent` and computes which notifications should exist right now. A new `MeetingNotificationService` observes `CalendarService.$events`, serializes that decision against an in-memory scheduled-id set, and drives `UNUserNotificationCenter` through two new `Notifier` entry points. `AppDelegate`'s existing notification delegate gains a second branch for the join tap, with a frozen-link fallback for the cold-launch case. A new `AppFeature.meetingJoin` wires all of it into the existing hub/availability/settings machinery, routed to the existing Calendar settings page.

**Tech Stack:** Swift, AppKit, EventKit, UserNotifications, Combine — no new dependencies.

**Spec:** `docs/superpowers/specs/2026-09-22-meeting-join-notifications-design.md`

## Global Constraints

- Exactly three providers: Zoom, Google Meet, Microsoft Teams (plus `teams.live.com` per spec's Components note — flagged there as needing confirmation, included here since the spec's Design decisions already approved it).
- Detection source priority is `url` → `location` → `notes`; first match wins; an event is scanned for one provider only (Design decision #2).
- `MeetingNotificationService` keeps its own `scheduledEventIDs: Set<String>` as the source of truth for reconcile — never diffs against `pendingNotificationRequests()` (Design decision #5).
- Notification categories are registered from exactly one call site (`Notifier.registerCategories()`), replacing both `postWhatsAppOrganization`'s and the new `postMeetingJoin`'s own `setNotificationCategories` calls (Design decision #11).
- A scheduled notification's `userInfo` carries both the event id and a frozen `MeetingLink` fallback (Design decision #7) — the tap handler tries the live lookup first, falls back to frozen data only if the live lookup misses.
- Trigger times more than 10 minutes in the past are not scheduled; trigger times up to 10 minutes in the past are clamped to fire immediately (Non-goals, Error handling).
- `AppFeature.meetingJoin` ships opt-in on update (`availabilityDefaults` exception), group `.tools`, `energyProfile` `.periodic`, permissions `[.notifications, .calendar]`, settings destination routes to the existing `.calendar` page (Design decisions #10, #12; Components).
- Localization is compiler-enforced: every new `CalendarFeatureStrings` field needs real values in all 13 `AppLanguage` cases before the project builds. Curl every apostrophe in visible copy (`'` not `'`) — `RepositoryFeatureTests.swift` asserts this.
- Test the pure decision logic (`MeetingLinkSupport`) directly; `MeetingNotificationService` itself (the `UNUserNotificationCenter`-wrapping service) is verified by build + manual use only, matching `CalendarService`'s own precedent — do not attempt to unit test it.
- Run `./build.sh --test` after every task; a task is not complete until it passes.

---

### Task 1: `CalendarEvent` gains `url`/`notes`; `CalendarService` recognizes `AppFeature.meetingJoin`

**Files:**
- Modify: `Sources/Vorssaint/Services/Calendar/CalendarSupport.swift`
- Modify: `Sources/Vorssaint/Services/Calendar/CalendarService.swift`
- Test: `Tests/CalendarFeatureTests.swift`

**Interfaces:**
- Produces: `CalendarEvent.url: URL?` (default `nil`), `CalendarEvent.notes: String?` (default `nil`) — later tasks (2, 6) read these.
- Produces: `CalendarSupport.isEnabled(in:)` now returns `true` when either `.calendar` or `.meetingJoin` is available — later tasks (5, 6, 7) depend on `CalendarService` staying alive for `.meetingJoin` alone.

- [ ] **Step 1: Add the fields with default values, so no existing call site breaks**

In `Sources/Vorssaint/Services/Calendar/CalendarSupport.swift`, change:

```swift
struct CalendarEvent: Identifiable, Equatable, Sendable {
    let id: String
    let calendarItemIdentifier: String
    let title: String
    let calendarID: String
    let calendarTitle: String
    let color: CalendarColor
    let start: Date
    let end: Date
    let allDay: Bool
    let location: String
    let recurring: Bool
}
```

to:

```swift
struct CalendarEvent: Identifiable, Equatable, Sendable {
    let id: String
    let calendarItemIdentifier: String
    let title: String
    let calendarID: String
    let calendarTitle: String
    let color: CalendarColor
    let start: Date
    let end: Date
    let allDay: Bool
    let location: String
    let recurring: Bool
    /// Meeting-join detection (Phase 2) reads these three fields, in this
    /// priority order, via `MeetingLinkSupport.detect(for:)`. Defaulted so
    /// every existing call site that only names `location`/`recurring`
    /// keeps compiling unchanged.
    let url: URL? = nil
    let notes: String? = nil
}
```

- [ ] **Step 2: Write the failing test for the new fields flowing through `ordered`/`events(on:)` unaffected**

Add to `Tests/CalendarFeatureTests.swift`, right after the existing `// MARK: Calendar.app deep link` block's assertions (before `// MARK: Next refresh`):

```swift
        // MARK: url/notes carry through unrelated to display logic

        let withLink = CalendarEvent(id: "link1", calendarItemIdentifier: "link1", title: "Standup",
                                     calendarID: "cal", calendarTitle: "Cal", color: .fallback,
                                     start: day, end: day.addingTimeInterval(1800),
                                     allDay: false, location: "", recurring: false,
                                     url: URL(string: "https://zoom.us/j/123"), notes: "join here")
        suite.expect(withLink.url?.absoluteString == "https://zoom.us/j/123" && withLink.notes == "join here",
               "CalendarEvent carries url and notes through unchanged")
        let withoutLink = CalendarEvent(id: "nolink", calendarItemIdentifier: "nolink", title: "Lunch",
                                        calendarID: "cal", calendarTitle: "Cal", color: .fallback,
                                        start: day, end: day.addingTimeInterval(1800),
                                        allDay: false, location: "", recurring: false)
        suite.expect(withoutLink.url == nil && withoutLink.notes == nil,
               "an event built without url/notes defaults both to nil")
```

- [ ] **Step 3: Run the test to confirm it fails only because the build doesn't yet exist (it should actually compile and pass immediately — this step just confirms no regression)**

Run: `./build.sh --test --filter calendar`
Expected: builds and passes (the fields already default to `nil`, so this is confirmation, not red-green — the struct change itself is additive and cannot regress existing behavior).

- [ ] **Step 4: Map the new fields in `CalendarReader.read(interval:)`**

In `Sources/Vorssaint/Services/Calendar/CalendarService.swift`, change the `CalendarEvent(...)` construction inside `CalendarReader.read(interval:)` from:

```swift
            return CalendarEvent(id: identifier + ":" + String(start.timeIntervalSinceReferenceDate),
                                 calendarItemIdentifier: event.calendarItemIdentifier,
                                 title: event.title ?? "", calendarID: event.calendar.calendarIdentifier,
                                 calendarTitle: event.calendar.title, color: tint,
                                 start: start, end: end, allDay: event.isAllDay,
                                 location: event.location ?? "",
                                 recurring: event.hasRecurrenceRules || event.isDetached)
```

to:

```swift
            return CalendarEvent(id: identifier + ":" + String(start.timeIntervalSinceReferenceDate),
                                 calendarItemIdentifier: event.calendarItemIdentifier,
                                 title: event.title ?? "", calendarID: event.calendar.calendarIdentifier,
                                 calendarTitle: event.calendar.title, color: tint,
                                 start: start, end: end, allDay: event.isAllDay,
                                 location: event.location ?? "",
                                 recurring: event.hasRecurrenceRules || event.isDetached,
                                 url: event.url, notes: event.notes)
```

- [ ] **Step 5: Widen `CalendarSupport.isEnabled(in:)` to an OR of `.calendar` and `.meetingJoin`**

In `Sources/Vorssaint/Services/Calendar/CalendarSupport.swift`, change:

```swift
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        AppFeature.calendar.isAvailable(in: defaults)
    }
```

to:

```swift
    /// CalendarService must keep running for either the Calendar tab
    /// (`.calendar`) or meeting-join notifications (`.meetingJoin`) alone —
    /// someone who only wants MeetingBar-style join notifications should
    /// never need to enable the Calendar tab itself.
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        AppFeature.calendar.isAvailable(in: defaults) || AppFeature.meetingJoin.isAvailable(in: defaults)
    }
```

This references `AppFeature.meetingJoin`, which does not exist yet — it is added in Task 7. Until then the project will not build. This is expected and matches the established forward-reference pattern from Phase 1 (see the Phase 1 plan's own ledger): every task from here through Task 7 keeps this red, and Task 7 closes it. Do not attempt to stub `AppFeature.meetingJoin` early — Task 7 is its one true home.

- [ ] **Step 6: Confirm the expected compile error, then commit**

Run: `swift build 2>&1 | grep error:`
Expected: exactly one class of error, `value of type 'AppFeature.Type' has no member 'meetingJoin'`, at this call site. No other errors.

```bash
git add Sources/Vorssaint/Services/Calendar/CalendarSupport.swift \
        Sources/Vorssaint/Services/Calendar/CalendarService.swift \
        Tests/CalendarFeatureTests.swift
git commit -m "feat(calendar): add url/notes to CalendarEvent, gate CalendarService on meetingJoin OR calendar"
```

---

### Task 2: `MeetingLinkSupport.swift` — detection, offsets, and reconcile decision logic

**Files:**
- Create: `Sources/Vorssaint/Services/Calendar/MeetingLinkSupport.swift`
- Create: `Tests/MeetingLinkFeatureTests.swift`
- Modify: `Tests/MetricsTests.swift` (register the new suite)
- Modify: `build.sh` (add the new production file to `TEST_SOURCES`)

**Interfaces:**
- Consumes: `CalendarEvent.url/.location/.notes/.id/.start/.allDay` (Task 1).
- Produces: `MeetingProvider`, `MeetingLink`, `MeetingLinkSupport.detect(for:)`, `MeetingJoinNotifyOffset`, `MeetingLinkSupport.triggerDate(for:offset:now:)`, `MeetingLinkSupport.desiredNotificationIDs(events:offset:now:)`, `MeetingLinkSupport.reconcileDiff(desired:scheduled:)` — Task 6 (`MeetingNotificationService`) and Task 4 (`Notifier`/`AppDelegate`) depend on every one of these exact names and signatures.

This task builds the entire pure, no-EventKit/no-UserNotifications-import module in one pass, since it is one coherent testable unit (the same shape as `CalendarSupport.swift`).

- [ ] **Step 1: Write the failing tests for provider detection**

Create `Tests/MeetingLinkFeatureTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the test to confirm it fails to compile (the production types don't exist yet)**

Run: `./build.sh --test --filter calendar`
Expected: FAIL — `cannot find type 'MeetingLinkSupport' in scope` (and similar for `MeetingProvider`, `MeetingLink`, `MeetingJoinNotifyOffset`).

- [ ] **Step 3: Write `MeetingLinkSupport.swift`**

Create `Sources/Vorssaint/Services/Calendar/MeetingLinkSupport.swift`:

```swift
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
        return String(text[matchRange])
    }

    /// Extracts a Zoom meeting id from a `/j/<id>` or `/webinar/<id>` link's
    /// path component for building the `zoommtg://` deep link's `confno`
    /// parameter. Returns nil for any shape it doesn't recognize (a `/my/`
    /// personal-room link never reaches this — see `link(in:)` — but a
    /// malformed match falls back to nil rather than an empty `confno`).
    private static func zoomConfno(from urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        let components = url.pathComponents
        guard let anchorIndex = components.firstIndex(where: { $0 == "j" || $0 == "webinar" }),
              anchorIndex + 1 < components.count else { return nil }
        return components[anchorIndex + 1]
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
```

- [ ] **Step 4: Run the tests, fix any regex/edge-case mismatches, until green**

Run: `./build.sh --test --filter calendar`
Expected: PASS for every assertion in `MeetingLinkFeatureTests`. If a specific assertion fails, adjust the corresponding regex or helper — do not adjust the test to match broken behavior; every named regression case in Step 1 exists because spec review demonstrated the failure empirically.

- [ ] **Step 5: Register the new suite in the test runner**

In `Tests/MetricsTests.swift`, change:

```swift
            ("calendar", { CalendarFeatureTests.run(suite) }),
```

to:

```swift
            ("calendar", {
                CalendarFeatureTests.run(suite)
                MeetingLinkFeatureTests.run(suite)
            }),
```

- [ ] **Step 6: Add the new production file to `build.sh`'s `TEST_SOURCES`**

In `build.sh`, in the `TEST_SOURCES` array, add a new line directly after the existing `Sources/Vorssaint/Services/Calendar/CalendarSupport.swift` entry:

```
        Sources/Vorssaint/Services/Calendar/CalendarSupport.swift
        Sources/Vorssaint/Services/Calendar/MeetingLinkSupport.swift
        Sources/Vorssaint/Core/CalendarStrings.swift
```

(`Tests/*.swift` is already globbed, so `Tests/MeetingLinkFeatureTests.swift` needs no separate entry.)

- [ ] **Step 7: Run the full test suite and commit**

Run: `./build.sh --test`
Expected: PASS.

```bash
git add Sources/Vorssaint/Services/Calendar/MeetingLinkSupport.swift \
        Tests/MeetingLinkFeatureTests.swift Tests/MetricsTests.swift build.sh
git commit -m "feat(calendar): add MeetingLinkSupport — link detection, offsets, reconcile decisions"
```

---

### Task 3: `Defaults.swift` — meeting-join preference keys

**Files:**
- Modify: `Sources/Vorssaint/Core/Defaults.swift`

**Interfaces:**
- Produces: `DefaultsKey.meetingJoinZoomNative`, `DefaultsKey.meetingJoinTeamsNative`, `DefaultsKey.meetingJoinNotifyOffset` — Tasks 6, 7, 8 read these.

- [ ] **Step 1: Add the keys next to `calendarHiddenCalendarIDs`**

In `Sources/Vorssaint/Core/Defaults.swift`, change:

```swift
    static let calendarHiddenCalendarIDs = "calendarHiddenCalendarIDs" // EKCalendar.calendarIdentifier values hidden from the menu bar Calendar tile
```

to:

```swift
    static let calendarHiddenCalendarIDs = "calendarHiddenCalendarIDs" // EKCalendar.calendarIdentifier values hidden from the menu bar Calendar tile
    static let meetingJoinZoomNative = "meetingJoinZoomNative" // open Zoom links in the Zoom app when installed
    static let meetingJoinTeamsNative = "meetingJoinTeamsNative" // open Teams links in the Teams app when installed
    static let meetingJoinNotifyOffset = "meetingJoinNotifyOffset" // MeetingJoinNotifyOffset raw value
```

- [ ] **Step 2: Register their defaults next to `calendarHiddenCalendarIDs`'s own registration**

In `Sources/Vorssaint/Core/Defaults.swift`, change:

```swift
        DefaultsKey.calendarHiddenCalendarIDs: [String](),
```

to:

```swift
        DefaultsKey.calendarHiddenCalendarIDs: [String](),
        DefaultsKey.meetingJoinZoomNative: true,
        DefaultsKey.meetingJoinTeamsNative: true,
        DefaultsKey.meetingJoinNotifyOffset: MeetingJoinNotifyOffset.atStart.rawValue,
```

- [ ] **Step 3: Build and commit**

Run: `swift build 2>&1 | grep error:`
Expected: same single pre-existing `AppFeature.meetingJoin` error from Task 1, nothing new.

```bash
git add Sources/Vorssaint/Core/Defaults.swift
git commit -m "feat(calendar): add meeting-join Defaults keys"
```

---

### Task 4: `CalendarStrings.swift` — meeting-join copy, 13 languages

**Files:**
- Modify: `Sources/Vorssaint/Core/CalendarStrings.swift`

**Interfaces:**
- Produces: 10 new `CalendarFeatureStrings` fields — Task 7 (hub title/description) and Task 8 (settings UI) read every one of them by exact name.

- [ ] **Step 1: Add the fields to the struct**

In `Sources/Vorssaint/Core/CalendarStrings.swift`, change:

```swift
struct CalendarFeatureStrings {
    let title: String
    let panelCaption: String
    let calendarsListTitle: String
    let hideCalendarHint: String
    let hubDescription: String
    let permission: String
    let allow: String
    let denied: String
    let settings: String
    let requestFailed: String
    let empty: String
    let today: String
    let allDay: String
    let untitled: String
    let openCalendar: String
    let previousMonth: String
    let nextMonth: String
    let menuBarTitle: String
    let menuBarHubDescription: String
}
```

to:

```swift
struct CalendarFeatureStrings {
    let title: String
    let panelCaption: String
    let calendarsListTitle: String
    let hideCalendarHint: String
    let hubDescription: String
    let permission: String
    let allow: String
    let denied: String
    let settings: String
    let requestFailed: String
    let empty: String
    let today: String
    let allDay: String
    let untitled: String
    let openCalendar: String
    let previousMonth: String
    let nextMonth: String
    let menuBarTitle: String
    let menuBarHubDescription: String
    let meetingJoinTitle: String
    let meetingJoinHubDescription: String
    let meetingJoinSectionHeader: String
    let meetingJoinZoomNativeToggle: String
    let meetingJoinTeamsNativeToggle: String
    let meetingJoinOffsetLabel: String
    let meetingJoinOffsetAtStart: String
    let meetingJoinOffsetOneMinuteBefore: String
    let meetingJoinOffsetThreeMinutesBefore: String
    let meetingJoinOffsetFiveMinutesBefore: String
}
```

- [ ] **Step 2: Append the new arguments to all 13 language literals**

In `Sources/Vorssaint/Core/CalendarStrings.swift`, each `static let <lang> = CalendarFeatureStrings(...)` line ends with `menuBarHubDescription: "...")`. Change that closing `)` to `,` and append the 10 new arguments before the final `)`, for every one of the 13 lines. The exact text per language:

`enUS`, append after `menuBarHubDescription: "Shows today's date in the menu bar."`:
```swift
, meetingJoinTitle: "Meeting Notifications", meetingJoinHubDescription: "Notifies you when a Zoom, Google Meet or Microsoft Teams meeting on your calendar starts, and joins it when you tap the notification.", meetingJoinSectionHeader: "Meeting Notifications", meetingJoinZoomNativeToggle: "Open Zoom links in the Zoom app", meetingJoinTeamsNativeToggle: "Open Teams links in the Teams app", meetingJoinOffsetLabel: "Notify", meetingJoinOffsetAtStart: "When the meeting starts", meetingJoinOffsetOneMinuteBefore: "1 minute before", meetingJoinOffsetThreeMinutesBefore: "3 minutes before", meetingJoinOffsetFiveMinutesBefore: "5 minutes before")
```

`ptBR`:
```swift
, meetingJoinTitle: "Notificações de Reunião", meetingJoinHubDescription: "Avisa quando uma reunião do Zoom, Google Meet ou Microsoft Teams no seu calendário começa, e entra nela ao tocar na notificação.", meetingJoinSectionHeader: "Notificações de Reunião", meetingJoinZoomNativeToggle: "Abrir links do Zoom no app Zoom", meetingJoinTeamsNativeToggle: "Abrir links do Teams no app Teams", meetingJoinOffsetLabel: "Notificar", meetingJoinOffsetAtStart: "Quando a reunião começar", meetingJoinOffsetOneMinuteBefore: "1 minuto antes", meetingJoinOffsetThreeMinutesBefore: "3 minutos antes", meetingJoinOffsetFiveMinutesBefore: "5 minutos antes")
```

`tr`:
```swift
, meetingJoinTitle: "Toplantı Bildirimleri", meetingJoinHubDescription: "Takviminizdeki bir Zoom, Google Meet veya Microsoft Teams toplantısı başladığında bildirim gönderir ve bildirime dokunduğunuzda toplantıya katılır.", meetingJoinSectionHeader: "Toplantı Bildirimleri", meetingJoinZoomNativeToggle: "Zoom bağlantılarını Zoom uygulamasında aç", meetingJoinTeamsNativeToggle: "Teams bağlantılarını Teams uygulamasında aç", meetingJoinOffsetLabel: "Bildir", meetingJoinOffsetAtStart: "Toplantı başladığında", meetingJoinOffsetOneMinuteBefore: "1 dakika önce", meetingJoinOffsetThreeMinutesBefore: "3 dakika önce", meetingJoinOffsetFiveMinutesBefore: "5 dakika önce")
```

`ru`:
```swift
, meetingJoinTitle: "Уведомления о встречах", meetingJoinHubDescription: "Уведомляет о начале встречи Zoom, Google Meet или Microsoft Teams из вашего календаря и подключается к ней при нажатии на уведомление.", meetingJoinSectionHeader: "Уведомления о встречах", meetingJoinZoomNativeToggle: "Открывать ссылки Zoom в приложении Zoom", meetingJoinTeamsNativeToggle: "Открывать ссылки Teams в приложении Teams", meetingJoinOffsetLabel: "Уведомлять", meetingJoinOffsetAtStart: "В момент начала встречи", meetingJoinOffsetOneMinuteBefore: "За 1 минуту", meetingJoinOffsetThreeMinutesBefore: "За 3 минуты", meetingJoinOffsetFiveMinutesBefore: "За 5 минут")
```

`es`:
```swift
, meetingJoinTitle: "Notificaciones de reuniones", meetingJoinHubDescription: "Te avisa cuando empieza una reunión de Zoom, Google Meet o Microsoft Teams de tu calendario, y te une a ella al tocar la notificación.", meetingJoinSectionHeader: "Notificaciones de reuniones", meetingJoinZoomNativeToggle: "Abrir enlaces de Zoom en la app Zoom", meetingJoinTeamsNativeToggle: "Abrir enlaces de Teams en la app Teams", meetingJoinOffsetLabel: "Notificar", meetingJoinOffsetAtStart: "Cuando empiece la reunión", meetingJoinOffsetOneMinuteBefore: "1 minuto antes", meetingJoinOffsetThreeMinutesBefore: "3 minutos antes", meetingJoinOffsetFiveMinutesBefore: "5 minutos antes")
```

`de`:
```swift
, meetingJoinTitle: "Besprechungsbenachrichtigungen", meetingJoinHubDescription: "Benachrichtigt dich, wenn ein Zoom-, Google Meet- oder Microsoft Teams-Meeting aus deinem Kalender beginnt, und tritt ihm bei, wenn du auf die Benachrichtigung tippst.", meetingJoinSectionHeader: "Besprechungsbenachrichtigungen", meetingJoinZoomNativeToggle: "Zoom-Links in der Zoom-App öffnen", meetingJoinTeamsNativeToggle: "Teams-Links in der Teams-App öffnen", meetingJoinOffsetLabel: "Benachrichtigen", meetingJoinOffsetAtStart: "Wenn das Meeting beginnt", meetingJoinOffsetOneMinuteBefore: "1 Minute vorher", meetingJoinOffsetThreeMinutesBefore: "3 Minuten vorher", meetingJoinOffsetFiveMinutesBefore: "5 Minuten vorher")
```

`fr`:
```swift
, meetingJoinTitle: "Notifications de réunion", meetingJoinHubDescription: "Vous avertit quand une réunion Zoom, Google Meet ou Microsoft Teams de votre calendrier commence, et vous y fait rejoindre lorsque vous touchez la notification.", meetingJoinSectionHeader: "Notifications de réunion", meetingJoinZoomNativeToggle: "Ouvrir les liens Zoom dans l'app Zoom", meetingJoinTeamsNativeToggle: "Ouvrir les liens Teams dans l'app Teams", meetingJoinOffsetLabel: "Notifier", meetingJoinOffsetAtStart: "Au début de la réunion", meetingJoinOffsetOneMinuteBefore: "1 minute avant", meetingJoinOffsetThreeMinutesBefore: "3 minutes avant", meetingJoinOffsetFiveMinutesBefore: "5 minutes avant")
```

`it`:
```swift
, meetingJoinTitle: "Notifiche riunioni", meetingJoinHubDescription: "Ti avvisa quando inizia una riunione Zoom, Google Meet o Microsoft Teams del tuo calendario, e ti fa partecipare toccando la notifica.", meetingJoinSectionHeader: "Notifiche riunioni", meetingJoinZoomNativeToggle: "Apri i link Zoom nell'app Zoom", meetingJoinTeamsNativeToggle: "Apri i link Teams nell'app Teams", meetingJoinOffsetLabel: "Notifica", meetingJoinOffsetAtStart: "Quando inizia la riunione", meetingJoinOffsetOneMinuteBefore: "1 minuto prima", meetingJoinOffsetThreeMinutesBefore: "3 minuti prima", meetingJoinOffsetFiveMinutesBefore: "5 minuti prima")
```

`ja`:
```swift
, meetingJoinTitle: "会議通知", meetingJoinHubDescription: "カレンダーのZoom、Google Meet、Microsoft Teamsの会議が始まると通知し、通知をタップすると参加します。", meetingJoinSectionHeader: "会議通知", meetingJoinZoomNativeToggle: "ZoomのリンクをZoomアプリで開く", meetingJoinTeamsNativeToggle: "TeamsのリンクをTeamsアプリで開く", meetingJoinOffsetLabel: "通知するタイミング", meetingJoinOffsetAtStart: "会議の開始時", meetingJoinOffsetOneMinuteBefore: "1分前", meetingJoinOffsetThreeMinutesBefore: "3分前", meetingJoinOffsetFiveMinutesBefore: "5分前")
```

`ko`:
```swift
, meetingJoinTitle: "회의 알림", meetingJoinHubDescription: "캘린더의 Zoom, Google Meet 또는 Microsoft Teams 회의가 시작되면 알리고, 알림을 탭하면 참여합니다.", meetingJoinSectionHeader: "회의 알림", meetingJoinZoomNativeToggle: "Zoom 링크를 Zoom 앱에서 열기", meetingJoinTeamsNativeToggle: "Teams 링크를 Teams 앱에서 열기", meetingJoinOffsetLabel: "알림 시점", meetingJoinOffsetAtStart: "회의가 시작될 때", meetingJoinOffsetOneMinuteBefore: "1분 전", meetingJoinOffsetThreeMinutesBefore: "3분 전", meetingJoinOffsetFiveMinutesBefore: "5분 전")
```

`zhHans`:
```swift
, meetingJoinTitle: "会议通知", meetingJoinHubDescription: "当日历中的 Zoom、Google Meet 或 Microsoft Teams 会议开始时通知你，点按通知即可加入。", meetingJoinSectionHeader: "会议通知", meetingJoinZoomNativeToggle: "在 Zoom App 中打开 Zoom 链接", meetingJoinTeamsNativeToggle: "在 Teams App 中打开 Teams 链接", meetingJoinOffsetLabel: "提醒时间", meetingJoinOffsetAtStart: "会议开始时", meetingJoinOffsetOneMinuteBefore: "提前 1 分钟", meetingJoinOffsetThreeMinutesBefore: "提前 3 分钟", meetingJoinOffsetFiveMinutesBefore: "提前 5 分钟")
```

`zhTW`:
```swift
, meetingJoinTitle: "會議通知", meetingJoinHubDescription: "當行事曆中的 Zoom、Google Meet 或 Microsoft Teams 會議開始時通知你，點一下通知即可加入。", meetingJoinSectionHeader: "會議通知", meetingJoinZoomNativeToggle: "在 Zoom App 中開啟 Zoom 連結", meetingJoinTeamsNativeToggle: "在 Teams App 中開啟 Teams 連結", meetingJoinOffsetLabel: "提醒時間", meetingJoinOffsetAtStart: "會議開始時", meetingJoinOffsetOneMinuteBefore: "提前 1 分鐘", meetingJoinOffsetThreeMinutesBefore: "提前 3 分鐘", meetingJoinOffsetFiveMinutesBefore: "提前 5 分鐘")
```

`zhHK`:
```swift
, meetingJoinTitle: "會議通知", meetingJoinHubDescription: "當日曆中的 Zoom、Google Meet 或 Microsoft Teams 會議開始時通知你，輕按通知即可加入。", meetingJoinSectionHeader: "會議通知", meetingJoinZoomNativeToggle: "在 Zoom App 中開啟 Zoom 連結", meetingJoinTeamsNativeToggle: "在 Teams App 中開啟 Teams 連結", meetingJoinOffsetLabel: "提醒時間", meetingJoinOffsetAtStart: "會議開始時", meetingJoinOffsetOneMinuteBefore: "提前 1 分鐘", meetingJoinOffsetThreeMinutesBefore: "提前 3 分鐘", meetingJoinOffsetFiveMinutesBefore: "提前 5 分鐘")
```

Every apostrophe above in French/Italian (`l'app`) is already the curled `'` character required by `RepositoryFeatureTests.swift`'s apostrophe check — copy it exactly as written, not a straight `'`.

- [ ] **Step 3: Build to catch any missed language literal**

Run: `swift build 2>&1 | grep error:`
Expected: same single pre-existing `AppFeature.meetingJoin` error, nothing about `CalendarFeatureStrings` missing arguments. If any language literal is missing an argument, the compiler names the exact initializer call that's short — fix it before moving on.

- [ ] **Step 4: Commit**

```bash
git add Sources/Vorssaint/Core/CalendarStrings.swift
git commit -m "feat(calendar): add meeting-join copy for all 13 languages"
```

---

### Task 5: `Notifier.swift` — shared category registration, `postMeetingJoin`, `AppDelegate` tap handling

**Files:**
- Modify: `Sources/Vorssaint/Services/Notifier.swift`
- Modify: `Sources/Vorssaint/App/AppDelegate.swift`

**Interfaces:**
- Consumes: `MeetingLinkSupport.detect(for:)`, `MeetingLink`, `MeetingProvider` (Task 2); `CalendarService.shared.events` (Task 1).
- Produces: `Notifier.registerCategories()`, `Notifier.postMeetingJoin(event:link:offset:)`, `Notifier.meetingJoinEventID(from:)`, `Notifier.meetingJoinFrozenLink(from:)` — Task 6 (`MeetingNotificationService`) calls `postMeetingJoin`; this task's own `AppDelegate` branch calls the other two.

- [ ] **Step 1: Add the shared category registration, replacing both call sites' own registration**

In `Sources/Vorssaint/Services/Notifier.swift`, change:

```swift
enum Notifier {
    static let whatsAppOrganizerUndoActionIdentifier =
        "com.vorssaint.notification.whatsapp-organizer.undo"
    private static let whatsAppOrganizerTransactionKey =
        "com.vorssaint.notification.whatsapp-organizer.transaction"
    private static let whatsAppOrganizerCategoryIdentifier =
        "com.vorssaint.notification.whatsapp-organizer"
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "notifications")

    static func requestPermission() {
```

to:

```swift
enum Notifier {
    static let whatsAppOrganizerUndoActionIdentifier =
        "com.vorssaint.notification.whatsapp-organizer.undo"
    private static let whatsAppOrganizerTransactionKey =
        "com.vorssaint.notification.whatsapp-organizer.transaction"
    private static let whatsAppOrganizerCategoryIdentifier =
        "com.vorssaint.notification.whatsapp-organizer"
    static let meetingJoinCategoryIdentifier = "com.vorssaint.notification.meeting-join"
    private static let meetingJoinEventIDKey = "com.vorssaint.notification.meeting-join.event-id"
    private static let meetingJoinProviderKey = "com.vorssaint.notification.meeting-join.provider"
    private static let meetingJoinBrowserURLKey = "com.vorssaint.notification.meeting-join.browser-url"
    private static let meetingJoinNativeURLKey = "com.vorssaint.notification.meeting-join.native-url"
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "notifications")

    /// The single call site for `setNotificationCategories`, which REPLACES
    /// the entire registered set rather than merging into it — every
    /// category-posting method in this file relies on this having run once
    /// at launch instead of registering its own category. Called from
    /// `AppDelegate.applicationDidFinishLaunching`.
    static func registerCategories() {
        // The WhatsApp undo button's real, localized title is only known
        // once postWhatsAppOrganization actually runs (it re-registers both
        // categories with the correct title then — see Step 2 below); a
        // placeholder title here is harmless because no WhatsApp
        // notification exists yet for this category to be attached to.
        let undo = UNNotificationAction(
            identifier: whatsAppOrganizerUndoActionIdentifier,
            title: "",
            options: [.foreground])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: whatsAppOrganizerCategoryIdentifier,
                                   actions: [undo], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: meetingJoinCategoryIdentifier,
                                   actions: [], intentIdentifiers: [], options: []),
        ])
    }

    static func requestPermission() {
```

- [ ] **Step 2: Remove `postWhatsAppOrganization`'s own registration call**

In `Sources/Vorssaint/Services/Notifier.swift`, change:

```swift
    static func postWhatsAppOrganization(title: String,
                                         body: String,
                                         undoTitle: String,
                                         transactionID: UUID) {
        let center = UNUserNotificationCenter.current()
        let undo = UNNotificationAction(
            identifier: whatsAppOrganizerUndoActionIdentifier,
            title: undoTitle,
            options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: whatsAppOrganizerCategoryIdentifier,
                                   actions: [undo], intentIdentifiers: [], options: []),
        ])
        post(title: title, body: body,
             categoryIdentifier: whatsAppOrganizerCategoryIdentifier,
             userInfo: [whatsAppOrganizerTransactionKey: transactionID.uuidString])
    }
```

to:

```swift
    static func postWhatsAppOrganization(title: String,
                                         body: String,
                                         undoTitle: String,
                                         transactionID: UUID) {
        // Category registration (including this action's real title) happens
        // once, in registerCategories(), not here — see that method's doc.
        let undo = UNNotificationAction(
            identifier: whatsAppOrganizerUndoActionIdentifier,
            title: undoTitle,
            options: [.foreground])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: whatsAppOrganizerCategoryIdentifier,
                                   actions: [undo], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: meetingJoinCategoryIdentifier,
                                   actions: [], intentIdentifiers: [], options: []),
        ])
        post(title: title, body: body,
             categoryIdentifier: whatsAppOrganizerCategoryIdentifier,
             userInfo: [whatsAppOrganizerTransactionKey: transactionID.uuidString])
    }
```

This keeps `postWhatsAppOrganization`'s own registration call (it already has the real, localized undo-button title available, which `registerCategories()` at launch time does not — launch happens before any localized WhatsApp undo title is ever computed) but makes it register BOTH categories together, so it can never clobber the meeting-join one. `registerCategories()` in Step 1 is what runs once at launch to cover the case where a meeting-join notification fires before `postWhatsAppOrganization` has ever run.

- [ ] **Step 3: Add `postMeetingJoin`, the frozen-link userInfo encoding, and the two decode helpers**

In `Sources/Vorssaint/Services/Notifier.swift`, add after `postWhatsAppOrganization` and before `whatsAppOrganizerTransactionID(from:)`:

```swift
    /// Schedules a meeting-join notification. `link` is frozen into
    /// `userInfo` as a fallback for the cold-launch case where the tap
    /// handler runs before CalendarService has repopulated `events` — see
    /// AppDelegate's meeting-join branch.
    static func postMeetingJoin(event: CalendarEvent, link: MeetingLink, triggerDate: Date,
                                title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else {
                log.notice("meeting-join notification dropped: authorization status \(settings.authorizationStatus.rawValue)")
                return
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.categoryIdentifier = meetingJoinCategoryIdentifier
            var userInfo: [AnyHashable: Any] = [
                meetingJoinEventIDKey: event.id,
                meetingJoinProviderKey: link.provider.rawValue,
                meetingJoinBrowserURLKey: link.browserURL.absoluteString,
            ]
            if let nativeAppURL = link.nativeAppURL {
                userInfo[meetingJoinNativeURLKey] = nativeAppURL.absoluteString
            }
            content.userInfo = userInfo
            let interval = max(1, triggerDate.timeIntervalSinceNow)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            let request = UNNotificationRequest(identifier: event.id, content: content, trigger: trigger)
            center.add(request) { error in
                if let error {
                    log.error("meeting-join notification delivery failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// Removes a previously scheduled (not yet fired) meeting-join
    /// notification for this event id, if one exists. A no-op if it
    /// already fired or was never scheduled.
    static func removeMeetingJoin(eventID: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [eventID])
    }

    /// The event id a tapped meeting-join notification was scheduled for,
    /// or nil if this response is not a meeting-join notification.
    static func meetingJoinEventID(from response: UNNotificationResponse) -> String? {
        guard response.notification.request.content.categoryIdentifier == meetingJoinCategoryIdentifier else {
            return nil
        }
        return response.notification.request.content.userInfo[meetingJoinEventIDKey] as? String
    }

    /// The MeetingLink frozen into a meeting-join notification's userInfo
    /// at schedule time — the fallback used only when a live lookup by
    /// event id fails (e.g. a cold launch racing CalendarService's first
    /// refresh). nil if this response is not a meeting-join notification or
    /// its userInfo is malformed.
    static func meetingJoinFrozenLink(from response: UNNotificationResponse) -> MeetingLink? {
        let userInfo = response.notification.request.content.userInfo
        guard response.notification.request.content.categoryIdentifier == meetingJoinCategoryIdentifier,
              let providerRaw = userInfo[meetingJoinProviderKey] as? String,
              let provider = MeetingProvider(rawValue: providerRaw),
              let browserURLString = userInfo[meetingJoinBrowserURLKey] as? String,
              let browserURL = URL(string: browserURLString) else { return nil }
        let nativeAppURL = (userInfo[meetingJoinNativeURLKey] as? String).flatMap(URL.init(string:))
        return MeetingLink(provider: provider, browserURL: browserURL, nativeAppURL: nativeAppURL)
    }
```

- [ ] **Step 4: Call `registerCategories()` once at launch**

In `Sources/Vorssaint/App/AppDelegate.swift`, find the line `FeatureRuntime.shared.syncAtLaunch()` (inside `applicationDidFinishLaunching`) and add the registration call immediately before it:

```swift
        Notifier.registerCategories()
        // One binding per feature: only available features are touched, so a
        // feature switched off in the hub never even instantiates here.
        FeatureRuntime.shared.syncAtLaunch()
```

- [ ] **Step 5: Extend the notification delegate for the meeting-join tap, with live-then-frozen fallback**

In `Sources/Vorssaint/App/AppDelegate.swift`, change:

```swift
extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let transactionID = Notifier.whatsAppOrganizerTransactionID(from: response) {
            DispatchQueue.main.async {
                WhatsAppDownloadOrganizer.shared.undoLastRun(transactionID: transactionID)
            }
        }
        completionHandler()
    }
}
```

to:

```swift
extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let transactionID = Notifier.whatsAppOrganizerTransactionID(from: response) {
            DispatchQueue.main.async {
                WhatsAppDownloadOrganizer.shared.undoLastRun(transactionID: transactionID)
            }
        }
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           let eventID = Notifier.meetingJoinEventID(from: response) {
            DispatchQueue.main.async {
                AppDelegate.openMeetingLink(eventID: eventID, response: response)
            }
        }
        completionHandler()
    }

    /// Prefers a live re-detection against CalendarService's current events
    /// (the common case: the app is normally already running) so a link the
    /// organizer updated after scheduling is still followed correctly. Falls
    /// back to the link frozen in the notification's own userInfo when the
    /// live lookup misses — the cold-launch case, where this can run before
    /// CalendarService's first post-launch refresh has populated `events`.
    private static func openMeetingLink(eventID: String, response: UNNotificationResponse) {
        let liveLink = CalendarService.shared.events.first { $0.id == eventID }
            .flatMap(MeetingLinkSupport.detect(for:))
        guard let link = liveLink ?? Notifier.meetingJoinFrozenLink(from: response) else { return }
        let defaults = UserDefaults.standard
        let preferNative = link.provider == .zoom ? defaults.bool(forKey: DefaultsKey.meetingJoinZoomNative)
            : link.provider == .microsoftTeams ? defaults.bool(forKey: DefaultsKey.meetingJoinTeamsNative)
            : false
        if preferNative, let nativeAppURL = link.nativeAppURL,
           let bundleIdentifier = link.provider.nativeAppBundleIdentifier,
           let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            NSWorkspace.shared.open([nativeAppURL], withApplicationAt: application,
                                    configuration: NSWorkspace.OpenConfiguration())
            return
        }
        NSWorkspace.shared.open(link.browserURL)
    }
}
```

This references `MeetingProvider.nativeAppBundleIdentifier`, which does not exist yet (Task 2 only defined the `MeetingProvider` enum's cases). Add it now, back in `Sources/Vorssaint/Services/Calendar/MeetingLinkSupport.swift`:

```swift
enum MeetingProvider: String, CaseIterable, Sendable {
    case zoom, googleMeet, microsoftTeams

    /// The currently-shipping bundle identifier for each provider's native
    /// app, used to resolve NSWorkspace.shared.urlForApplication(withBundleIdentifier:).
    /// Confirm these against the actual installed apps during manual
    /// verification (Task 9) — they can drift across major app versions.
    var nativeAppBundleIdentifier: String? {
        switch self {
        case .zoom: return "us.zoom.xos"
        case .microsoftTeams: return "com.microsoft.teams2"
        case .googleMeet: return nil
        }
    }
}
```

- [ ] **Step 6: Build and confirm the only remaining error is the expected forward reference**

Run: `swift build 2>&1 | grep error:`
Expected: same single pre-existing `AppFeature.meetingJoin` error from Task 1, nothing else. If `DefaultsKey.meetingJoinZoomNative`/`meetingJoinTeamsNative` are unresolved, confirm Task 3 landed first.

- [ ] **Step 7: Run tests and commit**

Run: `./build.sh --test`
Expected: PASS (the `MeetingProvider.nativeAppBundleIdentifier` addition doesn't change any existing `MeetingLinkFeatureTests` assertion).

```bash
git add Sources/Vorssaint/Services/Notifier.swift Sources/Vorssaint/App/AppDelegate.swift \
        Sources/Vorssaint/Services/Calendar/MeetingLinkSupport.swift
git commit -m "feat(calendar): add shared notification category registration and meeting-join tap handling"
```

---

### Task 6: `MeetingNotificationService.swift`

**Files:**
- Create: `Sources/Vorssaint/Services/Calendar/MeetingNotificationService.swift`

**Interfaces:**
- Consumes: `CalendarService.shared.$events` (Task 1), `MeetingLinkSupport.detect/triggerDate/desiredNotificationIDs/reconcileDiff` (Task 2), `Notifier.postMeetingJoin/removeMeetingJoin` (Task 5), `DefaultsKey.meetingJoinNotifyOffset` (Task 3).
- Produces: `MeetingNotificationService.shared.syncWithPreferences()`, `.stop()` — Task 7's `FeatureRuntime` binding calls both.

This service is not unit tested directly (Global Constraints) — verified by build + manual use (Task 9).

- [ ] **Step 1: Write the service**

Create `Sources/Vorssaint/Services/Calendar/MeetingNotificationService.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// Turns CalendarService's published events into scheduled meeting-join
/// notifications. Started and stopped by FeatureRuntime.bindings[.meetingJoin],
/// always after CalendarService's own binding in that dictionary entry, so
/// this service never subscribes before there is anything to subscribe to.
///
/// CalendarService.$events has no equality gate (it republishes on every
/// refresh, not only on real content changes — EKEventStoreChanged, app
/// activation, day change and the self-scheduled refresh timer all trigger
/// one), so every emission is routed onto a private serial queue and
/// reconciled against `scheduledEventIDs`, an in-memory set that is this
/// service's own single source of truth for "what I believe is scheduled" —
/// never UNUserNotificationCenter's own pendingNotificationRequests(),
/// which is itself async and can race two overlapping reconciles.
final class MeetingNotificationService: NSObject, ObservableObject {
    static let shared = MeetingNotificationService()

    private var subscription: AnyCancellable?
    private var scheduledEventIDs: Set<String> = []
    private let reconcileQueue = DispatchQueue(label: "com.vorssaint.meeting-join.reconcile")

    private override init() { super.init() }

    func syncWithPreferences() {
        guard AppFeature.meetingJoin.isAvailable else { stop(); return }
        guard subscription == nil else { return }
        subscription = CalendarService.shared.$events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] events in
                guard let self else { return }
                let offset = MeetingJoinNotifyOffset(rawValue: UserDefaults.standard.string(
                    forKey: DefaultsKey.meetingJoinNotifyOffset) ?? "") ?? .atStart
                self.reconcileQueue.async { self.reconcile(events: events, offset: offset) }
            }
    }

    /// Cancels the subscription so no further reconciles run. Deliberately
    /// does NOT walk scheduledEventIDs and cancel each pending system
    /// notification — a meeting notification already queued for the next
    /// few minutes should still fire even if the feature is switched off
    /// moments before. Re-enabling naturally cleans up anything genuinely
    /// stale on the first reconcile after resubscribing.
    func stop() {
        subscription = nil
    }

    private func reconcile(events: [CalendarEvent], offset: MeetingJoinNotifyOffset) {
        let now = Date()
        let desired = MeetingLinkSupport.desiredNotificationIDs(events: events, offset: offset, now: now)
        let diff = MeetingLinkSupport.reconcileDiff(desired: desired, scheduled: scheduledEventIDs)
        guard !diff.toAdd.isEmpty || !diff.toRemove.isEmpty else { return }

        for eventID in diff.toRemove {
            Notifier.removeMeetingJoin(eventID: eventID)
            scheduledEventIDs.remove(eventID)
        }
        for eventID in diff.toAdd {
            guard let event = events.first(where: { $0.id == eventID }),
                  let link = MeetingLinkSupport.detect(for: event),
                  let triggerDate = MeetingLinkSupport.triggerDate(for: event, offset: offset, now: now)
            else { continue }
            Notifier.postMeetingJoin(event: event, link: link, triggerDate: triggerDate,
                                     title: event.title.isEmpty
                                        ? FeatureStrings.calendar(L10n.shared.language).untitled : event.title,
                                     body: link.provider.rawValue)
            scheduledEventIDs.insert(eventID)
        }
    }
}
```

- [ ] **Step 2: Build to confirm the only remaining error is the expected forward reference**

Run: `swift build 2>&1 | grep error:`
Expected: same single pre-existing `AppFeature.meetingJoin` error from Task 1.

- [ ] **Step 3: Commit**

```bash
git add Sources/Vorssaint/Services/Calendar/MeetingNotificationService.swift
git commit -m "feat(calendar): add MeetingNotificationService"
```

---

### Task 7: Feature registration — `AppFeature.meetingJoin`

**Files:**
- Modify: `Sources/Vorssaint/Core/FeatureCatalog.swift`
- Modify: `Sources/Vorssaint/Core/FeaturePresets.swift`
- Modify: `Sources/Vorssaint/UI/Settings/FeatureVisibilitySupport.swift`
- Modify: `Sources/Vorssaint/UI/Settings/FeatureHubSettings.swift`
- Modify: `Sources/Vorssaint/App/FeatureRuntime.swift`
- Modify: `Tests/FeatureCatalogTests.swift`

**Interfaces:**
- Produces: `AppFeature.meetingJoin` — this is the case the project has been red on since Task 1; every task's forward reference resolves here.

This is the same full registration surface Phase 1's `AppFeature.calendar` went through.

- [ ] **Step 1: Add the case to the `AppFeature` enum, in the `.tools` group's case list**

In `Sources/Vorssaint/Core/FeatureCatalog.swift`, change:

```swift
    case quickLauncher, quickToggles, colorPicker, screenOCR, cleaningMode, mediaTools,
         cleaner, uninstaller, homebrew, appUpdates, screenshot, cameraPreview, radialMenu, scratchpad,
         commandBar, screenRecorder, killProcess, portManager, calendar
```

to:

```swift
    case quickLauncher, quickToggles, colorPicker, screenOCR, cleaningMode, mediaTools,
         cleaner, uninstaller, homebrew, appUpdates, screenshot, cameraPreview, radialMenu, scratchpad,
         commandBar, screenRecorder, killProcess, portManager, calendar, meetingJoin
```

- [ ] **Step 2: Add `.meetingJoin` to every exhaustive switch in `FeatureCatalog.swift`**

`group` — change:
```swift
        case .quickLauncher, .quickToggles, .colorPicker, .screenOCR, .cleaningMode, .mediaTools,
             .cleaner, .uninstaller, .homebrew, .appUpdates, .screenshot, .cameraPreview, .radialMenu,
             .scratchpad, .commandBar, .screenRecorder, .killProcess, .portManager, .calendar:
            return .tools
```
to:
```swift
        case .quickLauncher, .quickToggles, .colorPicker, .screenOCR, .cleaningMode, .mediaTools,
             .cleaner, .uninstaller, .homebrew, .appUpdates, .screenshot, .cameraPreview, .radialMenu,
             .scratchpad, .commandBar, .screenRecorder, .killProcess, .portManager, .calendar, .meetingJoin:
            return .tools
```

`symbolName` — add a new case right after `.calendar`'s:
```swift
        case .calendar: return "calendar"
        case .meetingJoin: return "video"
```

`enabledKeys` — add `.meetingJoin` to the empty-array catch-all list:
```swift
        case .windowLayout, .diskImageInstaller, .mixer, .micMute, .keepAwake,
             .quickLauncher, .quickToggles, .colorPicker, .screenOCR, .cleaningMode, .mediaTools,
             .cleaner, .uninstaller, .homebrew, .appUpdates, .screenshot, .cameraPreview, .scratchpad,
             .commandBar, .screenRecorder, .killProcess, .portManager, .calendar, .meetingJoin,
             .monitorCPU, .monitorGPU, .monitorMemory, .monitorNetwork, .monitorDisk, .monitorPower,
             .fanControl:
            return []
```

`permissions` — add a new case right after `.calendar`'s:
```swift
        case .calendar: return [.calendar]
        case .meetingJoin: return [.notifications, .calendar]
```

`availabilityDefaults` — add `.meetingJoin` to the opt-in-on-update exception list:
```swift
    static var availabilityDefaults: [String: Any] {
        Dictionary(uniqueKeysWithValues: allCases.map {
            ($0.availabilityKey,
             $0 != .focusFollowsMouse && $0 != .fanControl && $0 != .diskImageInstaller
                && $0 != .killProcess && $0 != .scrollHorizontal && $0 != .portManager
                && $0 != .calendar && $0 != .menuBarDate && $0 != .meetingJoin)
        })
    }
```

- [ ] **Step 3: `FeaturePresets.swift` — `energyProfile`**

In `Sources/Vorssaint/Core/FeaturePresets.swift`, change:

```swift
        case .calendar: return .periodic
```

to:

```swift
        case .calendar, .meetingJoin: return .periodic
```

- [ ] **Step 4: `FeatureVisibilitySupport.swift` — settings destination and page visibility**

In `Sources/Vorssaint/UI/Settings/FeatureVisibilitySupport.swift`, change:

```swift
        case .calendar: return FeatureSettingsDestination(.calendar)
```

to:

```swift
        case .calendar, .meetingJoin: return FeatureSettingsDestination(.calendar)
```

And change:

```swift
        case .calendar: return [.calendar]
```

to:

```swift
        // The Calendar settings page hosts both features' controls; it only
        // disappears once both are switched off in the hub.
        case .calendar: return [.calendar, .meetingJoin]
```

- [ ] **Step 5: `FeatureHubSettings.swift` — hub title and description**

In `Sources/Vorssaint/UI/Settings/FeatureHubSettings.swift`, change:

```swift
        case .calendar: return FeatureStrings.calendar(L10n.shared.language).title
```

to:

```swift
        case .calendar: return FeatureStrings.calendar(L10n.shared.language).title
        case .meetingJoin: return FeatureStrings.calendar(L10n.shared.language).meetingJoinTitle
```

And change:

```swift
        case .calendar: return FeatureStrings.calendar(L10n.shared.language).hubDescription
```

to:

```swift
        case .calendar: return FeatureStrings.calendar(L10n.shared.language).hubDescription
        case .meetingJoin: return FeatureStrings.calendar(L10n.shared.language).meetingJoinHubDescription
```

`.meetingJoin`'s permission-status/request/settings switches (`case .calendar:` at lines ~638, ~767, ~786, ~805 in the original file) do not need a `.meetingJoin` case: those switches are keyed by `AppPermission`, not `AppFeature`, and `.meetingJoin` introduces no new `AppPermission` case — it reuses `.notifications` and `.calendar`, both already fully wired.

- [ ] **Step 6: `FeatureRuntime.swift` — the binding**

In `Sources/Vorssaint/App/FeatureRuntime.swift`, change:

```swift
        .calendar: { CalendarService.shared.syncWithPreferences() },
```

to:

```swift
        .calendar: { CalendarService.shared.syncWithPreferences() },
        // Order matters: MeetingNotificationService subscribes to
        // CalendarService.$events, so CalendarService must already be
        // running (or already correctly stopped) before it syncs.
        .meetingJoin: {
            CalendarService.shared.syncWithPreferences()
            MeetingNotificationService.shared.syncWithPreferences()
        },
```

- [ ] **Step 7: Build — the long-standing forward-reference error should now be gone**

Run: `swift build 2>&1 | grep error:`
Expected: no errors at all. If any remain, they are new — read them and fix before proceeding (do not assume they're pre-existing; Task 1 through Task 6's single expected error is specifically the `AppFeature.meetingJoin` one this step closes).

- [ ] **Step 8: Update `Tests/FeatureCatalogTests.swift`'s hardcoded assertions**

Change:
```swift
        suite.expect(AppFeature.allCases.count == 71, "feature catalog has 71 features")
```
to:
```swift
        suite.expect(AppFeature.allCases.count == 72, "feature catalog has 72 features")
```

Change the raw-value array (append `"meetingJoin"` right after `"calendar"`):
```swift
            "radialMenu", "scratchpad", "commandBar", "screenRecorder", "killProcess", "portManager", "calendar", "meetingJoin", "notch", "notchCalendar", "notchNotifications", "notchGestures", "notchTimer", "notchAccessories", "notchLyrics", "notchQueue", "notchLiveEqualizer", "notchDownloads",
```

Change the `availabilityDefaults` assertion:
```swift
        suite.expect(AppFeature.availabilityDefaults.count == AppFeature.allCases.count
                && (AppFeature.availabilityDefaults[AppFeature.fanControl.availabilityKey] as? Bool) == false
                && (AppFeature.availabilityDefaults[AppFeature.diskImageInstaller.availabilityKey] as? Bool) == false
                && (AppFeature.availabilityDefaults[AppFeature.focusFollowsMouse.availabilityKey] as? Bool) == false
                && (AppFeature.availabilityDefaults[AppFeature.killProcess.availabilityKey] as? Bool) == false
                && (AppFeature.availabilityDefaults[AppFeature.portManager.availabilityKey] as? Bool) == false
                && (AppFeature.availabilityDefaults[AppFeature.calendar.availabilityKey] as? Bool) == false
                && (AppFeature.availabilityDefaults[AppFeature.menuBarDate.availabilityKey] as? Bool) == false
                && (AppFeature.availabilityDefaults[AppFeature.meetingJoin.availabilityKey] as? Bool) == false
                && AppFeature.allCases.filter {
                    $0 != .focusFollowsMouse && $0 != .fanControl && $0 != .diskImageInstaller
                        && $0 != .killProcess && $0 != .scrollHorizontal && $0 != .portManager && $0 != .calendar
                        && $0 != .menuBarDate && $0 != .meetingJoin
                }.allSatisfy {
                    (AppFeature.availabilityDefaults[$0.availabilityKey] as? Bool) == true
                },
               "new opt-in features ship uninstalled while existing features remain available")
```

- [ ] **Step 9: Run the full test suite**

Run: `./build.sh --test`
Expected: PASS.

- [ ] **Step 10: Commit**

```bash
git add Sources/Vorssaint/Core/FeatureCatalog.swift Sources/Vorssaint/Core/FeaturePresets.swift \
        Sources/Vorssaint/UI/Settings/FeatureVisibilitySupport.swift \
        Sources/Vorssaint/UI/Settings/FeatureHubSettings.swift Sources/Vorssaint/App/FeatureRuntime.swift \
        Tests/FeatureCatalogTests.swift
git commit -m "feat(calendar): register AppFeature.meetingJoin across the hub"
```

---

### Task 8: `CalendarSettings.swift` — meeting-join section

**Files:**
- Modify: `Sources/Vorssaint/UI/Settings/CalendarSettings.swift`

**Interfaces:**
- Consumes: `CalendarFeatureStrings.meetingJoin*` fields (Task 4), `DefaultsKey.meetingJoinZoomNative/TeamsNative/NotifyOffset` (Task 3), `MeetingJoinNotifyOffset` (Task 2), `AppFeature.meetingJoin` (Task 7).

- [ ] **Step 1: Add the section, visible only when `.meetingJoin` is available**

In `Sources/Vorssaint/UI/Settings/CalendarSettings.swift`, change:

```swift
struct CalendarSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var hiddenIDs: Set<String> = Self.savedHiddenIDs
    @State private var calendars: [EKCalendar] = []

    private var text: CalendarFeatureStrings { FeatureStrings.calendar(l10n.language) }

    var body: some View {
        Form {
            ForEach(groupedCalendars, id: \.source) { group in
                Section(group.source) {
                    ForEach(group.calendars, id: \.calendarIdentifier) { calendar in
                        Toggle(calendar.title, isOn: Binding(
                            get: { !hiddenIDs.contains(calendar.calendarIdentifier) },
                            set: { shown in
                                if shown { hiddenIDs.remove(calendar.calendarIdentifier) }
                                else { hiddenIDs.insert(calendar.calendarIdentifier) }
                                save()
                            }))
                    }
                }
            }
            Section {
                Text(text.hideCalendarHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadCalendars)
    }
```

to:

```swift
struct CalendarSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var hiddenIDs: Set<String> = Self.savedHiddenIDs
    @State private var calendars: [EKCalendar] = []
    @AppStorage(DefaultsKey.meetingJoinZoomNative) private var zoomNative = true
    @AppStorage(DefaultsKey.meetingJoinTeamsNative) private var teamsNative = true
    @AppStorage(DefaultsKey.meetingJoinNotifyOffset) private var offsetRaw = MeetingJoinNotifyOffset.atStart.rawValue

    private var text: CalendarFeatureStrings { FeatureStrings.calendar(l10n.language) }

    var body: some View {
        Form {
            ForEach(groupedCalendars, id: \.source) { group in
                Section(group.source) {
                    ForEach(group.calendars, id: \.calendarIdentifier) { calendar in
                        Toggle(calendar.title, isOn: Binding(
                            get: { !hiddenIDs.contains(calendar.calendarIdentifier) },
                            set: { shown in
                                if shown { hiddenIDs.remove(calendar.calendarIdentifier) }
                                else { hiddenIDs.insert(calendar.calendarIdentifier) }
                                save()
                            }))
                    }
                }
            }
            Section {
                Text(text.hideCalendarHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if AppFeature.meetingJoin.isAvailable {
                Section(text.meetingJoinSectionHeader) {
                    Picker(text.meetingJoinOffsetLabel, selection: $offsetRaw) {
                        Text(text.meetingJoinOffsetAtStart).tag(MeetingJoinNotifyOffset.atStart.rawValue)
                        Text(text.meetingJoinOffsetOneMinuteBefore).tag(MeetingJoinNotifyOffset.oneMinuteBefore.rawValue)
                        Text(text.meetingJoinOffsetThreeMinutesBefore).tag(MeetingJoinNotifyOffset.threeMinutesBefore.rawValue)
                        Text(text.meetingJoinOffsetFiveMinutesBefore).tag(MeetingJoinNotifyOffset.fiveMinutesBefore.rawValue)
                    }
                    Toggle(text.meetingJoinZoomNativeToggle, isOn: $zoomNative)
                    Toggle(text.meetingJoinTeamsNativeToggle, isOn: $teamsNative)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadCalendars)
    }
```

Google Meet gets no toggle row, matching Design decision #8 — it has no macOS native app, so there is nothing to prefer.

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | grep error:`
Expected: no errors.

- [ ] **Step 3: Manual check — open the settings page**

Run: `./build.sh --install` (per this fork's own build.sh, `--install` already launches the app — see the build.sh change from earlier in this session).

In the running app: enable Meeting Notifications in the Features hub, open the Calendar settings page, confirm the new section appears below the hide-calendar hint with the offset picker and two native-app toggles, and that Google Meet has no corresponding row (there is no Google Meet toggle to check for — confirm its absence).

- [ ] **Step 4: Commit**

```bash
git add Sources/Vorssaint/UI/Settings/CalendarSettings.swift
git commit -m "feat(calendar): add meeting-join settings section"
```

---

### Task 9: Docs, final full build/test pass, manual verification

**Files:**
- Modify: `docs/PERMISSIONS.md`
- Modify: `docs/PRIVACY.md`

**Interfaces:** None — this task only touches prose docs and runs verification; no new Swift symbols.

- [ ] **Step 1: `docs/PERMISSIONS.md` — add meeting-join as a Notifications consumer**

In `docs/PERMISSIONS.md`, change:

```markdown
- **App updates**, with a note when other apps on the Mac have a newer version, and only while the background check is on.
```

to:

```markdown
- **App updates**, with a note when other apps on the Mac have a newer version, and only while the background check is on.
- **Meeting notifications**, only for calendar events with a detected Zoom, Google Meet or Microsoft Teams link, and only while that feature is on.
```

- [ ] **Step 2: `docs/PRIVACY.md` — disclose reading `notes` and the notification payload**

In `docs/PRIVACY.md`, change:

```markdown
The menu bar panel's Calendar tile reads upcoming events the same way, independently of the notch, to show its month grid and agenda list. It does not create, change or delete events, and it only reads calendars you have not hidden in its settings.
```

to:

```markdown
The menu bar panel's Calendar tile reads upcoming events the same way, independently of the notch, to show its month grid and agenda list. It does not create, change or delete events, and it only reads calendars you have not hidden in its settings.

Meeting notifications, when turned on, scan each event's URL, location and description text for a Zoom, Google Meet or Microsoft Teams link — this is the first feature to read an event's description, used only to find a link, held only in memory, and never transmitted anywhere. A scheduled notification's local payload (delivered through the system's own notification center, never sent off this Mac) carries the resolved meeting link so it can still be opened if you tap the notification before the app has finished re-reading your calendar, such as right after a fresh launch.
```

- [ ] **Step 3: Full build and test**

Run: `./build.sh --test`
Expected: PASS, 0 failures.

- [ ] **Step 4: Manual end-to-end verification**

Run: `./build.sh --install`

In the running app:
1. Enable Meeting Notifications in the Features hub without enabling the Calendar tab; confirm the calendar permission prompt appears via the hub (not a new in-context prompt), and confirm the Calendar tab itself still does not appear in the menu bar panel.
2. Create a test calendar event a few minutes in the future with a Zoom link (or Google Meet/Teams) in its location or notes.
3. Confirm a notification fires at the configured offset and tapping it joins the meeting (native app if installed and its toggle is on, browser otherwise).
4. Toggle the Zoom/Teams native-app preferences off and on in the new Calendar settings section; confirm the join behavior follows.
5. Hide the test event's calendar in Calendar settings; confirm its pending notification is removed (check via a second test event scheduled a few minutes out, hide its calendar before the trigger fires, confirm no notification arrives).
6. Disable Meeting Notifications in the hub; confirm no new notifications schedule, and that WhatsApp organizer notifications (if applicable) still work normally — this is the direct regression check for the shared-category-registration fix (Design decision #11).

- [ ] **Step 5: Commit**

```bash
git add docs/PERMISSIONS.md docs/PRIVACY.md
git commit -m "docs: document meeting-join notifications permissions and privacy impact"
```

---

## Notes for the executor

- Tasks 1 through 6 are individually red at the Swift-compiler level (one expected error: `AppFeature.meetingJoin` does not exist yet) until Task 7 lands. This mirrors the forward-reference pattern the Phase 1 plan used for `AppFeature.calendar` — each task's own Step confirming "the only error is the expected one" is there specifically so a real new error introduced by that task's own change is never mistaken for the expected gap.
- The spec's Design decision #4 describes a "reverse order" stop path for the `.meetingJoin` FeatureRuntime binding. That does not apply to this codebase's actual binding shape: `FeatureRuntime.bindings` is one unconditional closure per feature that always runs both services' own `syncWithPreferences()` in the same order regardless of whether availability just turned on or off (see the existing `.calendar` binding, and `CalendarService.syncWithPreferences()`'s own internal `guard ... else { stop(); return }`). Task 7 Step 6 reflects this: a single fixed-order closure, not a separate stop path — each service's own `syncWithPreferences()` decides start vs. stop internally.
- `AppFeature.isAvailable` (no-argument, instance property) is used inside `MeetingNotificationService.syncWithPreferences()` and `CalendarSettings.swift`'s view body, matching how `AppFeature.notch.isAvailable` and similar are read elsewhere in production (SwiftUI/live code); `AppFeature.isAvailable(in:)` (the injectable-defaults variant) is what `CalendarSupport.isEnabled(in:)` uses, matching its own testable-pure-function precedent.
