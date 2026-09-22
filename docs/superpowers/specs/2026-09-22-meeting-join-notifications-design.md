# Meeting join notifications — Phase 2 (MeetingBar replacement)

Status: draft, awaiting implementation plan.

This is Phase 2 of the two-phase calendar feature. Phase 1 (the menu bar
Calendar tab, replacing Itsycal) is complete and shipped —
`docs/superpowers/specs/2026-09-21-menubar-calendar-view-design.md` and
`docs/superpowers/plans/2026-09-21-menubar-calendar-tab.md` — and this spec
builds directly on the `CalendarEvent`/`CalendarService` module it
established, per that spec's own "Open items" note that Phase 2 would add
the `url`/`notes` fields it deliberately left out.

## Problem

The person maintaining this fork currently runs **MeetingBar** alongside
Vorssaint for one specific workflow: when a calendar event has a
video-call link (Zoom, Google Meet, Microsoft Teams), a notification fires
when the meeting starts, and clicking it joins instantly — in the
provider's native app when one exists, otherwise the browser. Phase 1
replaced Itsycal; this phase replaces MeetingBar, closing out the full
two-app replacement goal set at the start of this project.

## Scope

- Detect a video-call link on a calendar event by scanning its EventKit
  `url`, `location`, and `notes` fields, for exactly three providers:
  **Zoom, Google Meet, Microsoft Teams** (confirmed as the providers that
  actually matter for this person's calendars — not MeetingBar's full
  ~60-provider catalog).
- A local notification when a linked meeting starts (or N minutes before,
  configurable), whose default tap joins the meeting — no separate "Join"
  button, matching the exact click-and-join workflow MeetingBar provides
  today.
- Per-provider join preference: native app first with browser fallback, or
  browser always. Google Meet has no macOS native app, so it is
  browser-only with no toggle.
- Settings live on the existing Calendar settings page (`CalendarSettings.swift`),
  as a new section — not a separate page.
- A new `AppFeature.meetingJoin`, independent of `AppFeature.calendar` (the
  Phase 1 tab), so this works even for someone who never enables the
  Calendar tab itself — this is a MeetingBar replacement first, a calendar
  companion second.

## Why this fits the project

- **Builds on Phase 1's own event model**, already fetching exactly the
  right data (`CalendarService`'s background-refreshing, permission-gated
  EventKit reader) — this phase adds two fields to `CalendarEvent` and one
  new service that consumes its existing `@Published events` stream,
  rather than standing up a second EventKit reader.
- **No new permission subsystem.** `.notifications` already exists as an
  `AppPermission` case (Keep Awake, battery, Monitor and update alerts
  already use it — `docs/PERMISSIONS.md:16`) and `Notifier.swift` already
  has a working local-notification path with a category/action precedent
  (`postWhatsAppOrganization`) this phase's own category follows. `.calendar`
  is Phase 1's own permission, already granted for anyone using either
  calendar feature.
- **No new runtime dependency.** Link detection is `NSRegularExpression`
  against three well-known, publicly documented URL shapes (Zoom, Google
  Meet, and Microsoft Teams meeting links) — no network calls, no
  provider SDKs, no external parsing library.

## Non-goals

- Not MeetingBar's full ~60-provider catalog — three providers only,
  matching what this person's calendars actually use. Adding a fourth
  provider later is a small, bounded addition to the regex catalog, not a
  redesign (noted for a future request, not scoped here).
- No "meeting starting now" fullscreen overlay, no auto-join, no
  Slack-huddle/Workplace-room detection, no custom-regex escape hatch —
  none of MeetingBar's other features beyond "notify, tap to join."
- No dedicated "Join" notification action button — the notification's
  default tap does the join (Design decision below), so there is nothing
  else to build here.
- No per-calendar or per-provider *enable/disable of detection itself* —
  detection always runs across all three providers for every event with a
  link; only the *join behavior* (native vs. browser) is configurable, and
  only for the two providers that have a native app.
- No handling for a meeting already in progress when the app launches or
  wakes from sleep with a trigger time already in the past — that
  notification is simply not scheduled (Error handling, below), not
  fired late.

## Design decisions

1. **`CalendarEvent` gains `url: URL?` and `notes: String?`.** Reverses
   Phase 1's deferral, which existed only because nothing needed the
   fields yet (Phase 1's spec: "cheap to add today... expensive to
   retrofit later" was explicitly rejected in favor of "add fields when a
   phase actually needs them" — this is that phase). `notes` is real data
   -minimization exposure (arbitrary free text, potentially sensitive) —
   accepted here because it is genuinely necessary: most real calendar
   invites place a Zoom/Meet/Teams link only in the event description, not
   the location field alone, so skipping `notes` would make detection
   fail on the majority of real invites. Documented in `docs/PRIVACY.md`
   (Repo conventions, below).
2. **Detection is a pure, source-priority scan — `url` → `location` →
   `notes`** — matching the field a person is most likely to have
   deliberately placed a link in (the event's own URL field is the most
   explicit signal EventKit exposes) before falling back to free text.
   First match wins; an event is never scanned for a *second* provider
   once one matches, since a meeting has one link in practice.
3. **`MeetingNotificationService` is a new, independent service**, not
   logic bolted onto `CalendarService`. `CalendarService`'s job stays "read
   and publish events"; this service's job is "turn published events into
   scheduled notifications." This mirrors an existing precedent in this
   codebase: `ClipboardAutoClearService` sits beside `ClipboardHistoryService`
   rather than inside it, for the same separation-of-concerns reason.
4. **`CalendarService` must run for `AppFeature.meetingJoin` alone**, even
   without `AppFeature.calendar`. `CalendarSupport.isEnabled()` (currently
   `AppFeature.calendar.isAvailable(in:)`) becomes "`.calendar` OR
   `.meetingJoin` is available," and `FeatureRuntime.bindings` gets a new
   `.meetingJoin` entry that also calls `CalendarService.shared.syncWithPreferences()`.
   This is the one point where Phase 2 touches Phase 1's own service,
   and it is additive (an OR condition), not a rewrite.
5. **Reconcile-on-change, diffed against actual pending requests — no
   separate dismissal-tracking set.** `MeetingNotificationService` observes
   `CalendarService.shared.$events`; on each change it computes the desired
   notification set (one per timed, linked, future-triggering event) and
   diffs it against `UNUserNotificationCenter.current().pendingNotificationRequests()`,
   adding what's missing and removing what's stale. A notification that
   already fired (and was tapped, or dismissed) is simply no longer
   "pending" by the time of the next reconcile — the diff itself is the
   dismissal-safety mechanism, so no extra state needs to be persisted or
   cleaned up.
6. **Default tap joins — no notification action button.** Confirmed
   directly: the workflow this replaces is "click the notification and
   instantly join," not "click a labeled button on it." The `didReceive`
   handler treats `response.actionIdentifier == UNNotificationDefaultActionIdentifier`
   as the join trigger, alongside the existing WhatsApp-undo branch that
   already handles its own named action.
7. **Notification identity carries the event id, not the resolved link.**
   The request's `userInfo` stores `CalendarEvent.id` (the same
   occurrence-qualified id Phase 1 already guarantees is unique per
   occurrence); at tap time, the handler looks the event back up in
   `CalendarService.shared.events` and re-runs detection, rather than
   freezing a URL into the notification at schedule time. This means a
   link that changes between scheduling and firing (an organizer updates
   the invite) is still followed correctly.
8. **Per-provider join preference: two booleans, not a settings object.**
   `meetingJoinZoomNative` and `meetingJoinTeamsNative` (both default
   `true` — native app first, per the earlier confirmed preference), no
   key for Google Meet since it has no native macOS app and is always
   browser. Matches the two-provider scope exactly; no need for a richer
   per-provider structure this phase doesn't use.
9. **Notification timing: one global offset, not per-provider or
   per-calendar.** A single `DefaultsKey.meetingJoinNotifyOffset` storing
   one of `atStart, oneMinuteBefore, threeMinutesBefore, fiveMinutesBefore`
   (MeetingBar's own choice of offsets, confirmed to matter for this
   workflow), defaulting to `atStart` — the most literal reading of "a
   notification when the meeting starts," with earlier warning available
   as an explicit opt-in.
10. **`AppFeature.meetingJoin` ships opt-in on update**, matching every
    other feature this fork has added (Calendar, Port Manager, etc.) — a
    fresh install gets it available immediately; an existing install only
    gets it after opting in via the hub, since it requests `.notifications`
    behavior a person didn't have before.

## Components

New files:

- `Sources/Vorssaint/Services/Calendar/MeetingLinkSupport.swift` — pure
  functions and types, no EventKit/UserNotifications imports, fully
  testable like `CalendarSupport.swift`:

  ```swift
  enum MeetingProvider: String, CaseIterable {
      case zoom, googleMeet, microsoftTeams

      var hasNativeApp: Bool { self != .googleMeet }
      var nativeAppBundleIdentifier: String? {
          switch self {
          case .zoom: return "us.zoom.xos"
          case .microsoftTeams: return "com.microsoft.teams2"
          case .googleMeet: return nil
          }
      }
  }

  struct MeetingLink: Equatable {
      let provider: MeetingProvider
      let browserURL: URL
      let nativeAppURL: URL?   // nil for Google Meet, and for a Zoom
                                // personal-room link (excluded — see
                                // Error handling)
  }

  enum MeetingLinkSupport {
      static func detect(for event: CalendarEvent) -> MeetingLink? { ... }
  }
  ```

  `detect(for:)` tries, in order: `event.url?.absoluteString`,
  `event.location`, `event.notes` — the first candidate string that
  matches any provider's regex wins; the function returns immediately
  once a source produces a match, per Design decision #2.

  Per-provider regex (illustrative — the implementation plan pins the
  exact patterns against real invite links, not just this spec's sketch):
  - Zoom: `https?://[\w.-]*zoom\.(?:us|com)/(?:j|my|webinar)/[\w?=&-]+`,
    native scheme `zoommtg://zoom.us/join?confno=<meeting-id>` built from
    the matched URL's path/query — **except** a `/my/<name>` personal-room
    link, which stays browser-only (see Error handling).
  - Google Meet: `https?://meet\.google\.com/[a-z-]+` — no native scheme.
  - Microsoft Teams: `https?://teams\.microsoft\.com/l/meetup-join/[\w%.-]+`,
    native scheme built by swapping the `https` scheme for `msteams`.

- `Sources/Vorssaint/Services/Calendar/MeetingNotificationService.swift` —
  the scheduler:

  ```swift
  final class MeetingNotificationService: NSObject, ObservableObject {
      static let shared = MeetingNotificationService()
      func syncWithPreferences() { ... }  // subscribes to CalendarService.$events
      func stop() { ... }                  // cancels the subscription, does
                                            // NOT remove already-scheduled
                                            // system notifications (see
                                            // Error handling)
      private func reconcile(events: [CalendarEvent]) async { ... }
  }
  ```

Modified files:

- `Sources/Vorssaint/Services/Calendar/CalendarSupport.swift`: `CalendarEvent`
  gains `url: URL?` and `notes: String?` (both after `location`, before
  `recurring`, matching the field's conceptual grouping with the other
  EventKit-sourced content fields).
- `Sources/Vorssaint/Services/Calendar/CalendarService.swift`: `CalendarReader.read(interval:)`
  maps `event.url` and `event.notes` into the new fields;
  `CalendarSupport.isEnabled()` becomes `AppFeature.calendar.isAvailable(in:
  defaults) || AppFeature.meetingJoin.isAvailable(in: defaults)`.
- `Sources/Vorssaint/Services/Notifier.swift`: a new
  `postMeetingJoin(event:link:offset:)`-shaped entry point (mirroring
  `postWhatsAppOrganization`'s category-registration shape) that builds a
  `UNTimeIntervalNotificationTrigger` — this file's first use of a
  non-nil trigger; every existing `Notifier` call fires immediately
  (`trigger: nil`).
- `Sources/Vorssaint/App/AppDelegate.swift`: `userNotificationCenter(_:didReceive:withCompletionHandler:)`
  gains a branch for the meeting-join category, alongside the existing
  WhatsApp-undo branch — on `UNNotificationDefaultActionIdentifier`, looks
  up the event by id, re-detects its link, and opens it (Design decision
  #7).
- `Sources/Vorssaint/Core/FeatureCatalog.swift`, `FeaturePresets.swift`,
  `App/FeatureRuntime.swift`, `UI/Settings/FeatureVisibilitySupport.swift`,
  `UI/Settings/FeatureHubSettings.swift`: the same full registration
  surface Phase 1's `AppFeature.calendar` went through — `AppFeature.meetingJoin`
  case, `group` (`.tools`, matching `.calendar`'s own group — this is a
  notification/join feature, not a monitor), `symbolName`, `enabledKeys`
  (`[]`, on-demand like `.calendar`), `permissions`
  (`[.notifications, .calendar]`), `availabilityDefaults` exception list,
  `energyProfile` (`.idle` — no polling of its own; it rides
  `CalendarService`'s own refresh cycle), `SettingsPage` destination
  (routes to the *existing* Calendar settings page, not a new one —
  `FeatureSettingsDestination(.calendar)`, matching Phase 1's own
  `AppFeature.calendar` destination exactly), `hubTitle`/`hubDescription`.
- `Sources/Vorssaint/UI/Settings/CalendarSettings.swift`: a new section
  below the per-calendar checklist — the notification-timing picker and
  the two native-app toggles (each visible only when its provider
  `hasNativeApp`, i.e. Google Meet gets no toggle row at all).
- `Sources/Vorssaint/Core/Defaults.swift`: `meetingJoinZoomNative`,
  `meetingJoinTeamsNative` (both registered `true`), `meetingJoinNotifyOffset`
  (registered `"atStart"`).
- `Sources/Vorssaint/Core/CalendarStrings.swift`: new fields for the
  settings section's copy (join-mode toggle labels, offset picker option
  labels, hub title/description) — 13 languages, same file Phase 1 already
  established for this feature.

## Data flow

1. `CalendarService` already fetches and publishes `events` (Phase 1,
   unchanged) — now including `url`/`notes` on each `CalendarEvent`.
2. `MeetingNotificationService.syncWithPreferences()` subscribes to
   `CalendarService.shared.$events`. On every emission (a real change —
   `CalendarService` only publishes when its fetch result changes), it
   calls `reconcile(events:)`.
3. `reconcile(events:)` filters to non-all-day events with
   `MeetingLinkSupport.detect(for:) != nil`, computes each one's trigger
   date (`event.start` minus the configured offset), drops any whose
   trigger date is already in the past (Error handling), and builds the
   desired set of notification identifiers (one per qualifying event,
   keyed by `event.id`).
4. It reads `UNUserNotificationCenter.current().pendingNotificationRequests()`
   (filtered to this feature's own category identifier, so it never
   touches WhatsApp's or any other feature's pending requests), diffs
   against the desired set: removes requests for events no longer
   qualifying (canceled, link removed, hidden calendar), adds requests for
   newly-qualifying events, leaves everything else untouched — an
   already-scheduled notification is never re-created merely because
   `reconcile` ran again.
5. Each added request uses `Notifier.postMeetingJoin(event:link:offset:)`,
   itself building a `UNTimeIntervalNotificationTrigger` (floor 0.5s, per
   `UNTimeIntervalNotificationTrigger`'s own minimum) and a
   `UNMutableNotificationContent` with `categoryIdentifier` set to the new
   meeting-join category and `userInfo[eventIDKey] = event.id`.
6. When the notification fires and the person taps it,
   `AppDelegate.userNotificationCenter(_:didReceive:)` reads `event.id`
   from `userInfo`, looks it up in `CalendarService.shared.events`
   (falling back to no-op if the event is gone — see Error handling),
   re-runs `MeetingLinkSupport.detect(for:)` for a fresh link, and opens
   it: native app first if the provider has one and its own toggle is on
   (resolved via `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)`,
   matching `CalendarAgendaListView.openInCalendar`'s own resolve-or-fail
   pattern), browser otherwise.

## Error handling & edge cases

- **A trigger time already in the past when `reconcile` runs** (app was
  asleep, or just launched, past a meeting's own notification moment) is
  not scheduled at all — matches Non-goals: no late-firing notification
  for a meeting that already started minutes ago.
- **A Zoom personal-room link (`/my/<name>`)** is detected as a Zoom
  meeting for browser purposes, but excluded from the native-app rewrite
  — a personal room's native deep link behaves differently (it may
  prompt to start a room rather than join a specific meeting), so it
  stays browser-only regardless of the person's native-app toggle,
  matching MeetingBar's own documented exclusion for this exact link
  shape.
- **The native app isn't installed** (a stale bundle-identifier lookup
  from `NSWorkspace`) falls back to the browser automatically — this is
  not a failure state requiring a notification of its own; the meeting
  still opens.
- **The event is gone by the time the notification is tapped** (deleted,
  or the calendar it belongs to was just hidden in settings) — the tap
  does nothing rather than crash or show an error; there's nothing
  actionable to offer someone at that point.
- **Declined or canceled events** never reach this service — `CalendarService`
  already filters those out during EventKit fetch (Phase 1, unchanged), so
  `MeetingNotificationService` only ever sees events someone actually
  plans to attend.
- **`MeetingNotificationService.stop()`** (when `AppFeature.meetingJoin`
  and `AppFeature.calendar` are both turned off) cancels the `$events`
  subscription but does **not** remove already-scheduled system
  notifications — a meeting notification already queued for the next few
  minutes still fires even if the feature is switched off moments before;
  removing it would be surprising (someone expects the meeting they were
  just notified about to still exist), and the next `reconcile` after
  re-enabling naturally cleans up anything genuinely stale.
- **A calendar hidden in Settings mid-session** (Phase 1's
  `calendarHiddenCalendarIDs`) removes its events from
  `CalendarService.shared.events` on the next refresh, which `reconcile`
  then picks up as no-longer-qualifying — existing pending notifications
  for that calendar's events are removed on the next reconcile pass, same
  as any other event that stops qualifying.

## Testing

Pure `MeetingLinkSupport` functions get real tests, following
`CalendarSupport`'s and Phase 1's established pattern — a new
`Tests/MeetingLinkFeatureTests.swift` (or an addition to
`Tests/CalendarFeatureTests.swift`, exact placement an implementation-plan
decision), with synthetic `CalendarEvent` fixtures:

- Detection priority: an event with both a `location` match and a `notes`
  match returns the `location` one (source priority, Design decision #2).
- Each provider's regex against at least one real-shaped example URL
  (Zoom `/j/`, Google Meet, Teams `/l/meetup-join/`) and at least one
  near-miss that must NOT match (guards against overly broad patterns).
- The Zoom personal-room exclusion: a `/my/<name>` link detects as Zoom
  but produces a `nil` `nativeAppURL`.
- No match across all three sources returns `nil`, not a false positive.
- Trigger-time computation for each offset option, including the
  already-in-the-past case correctly producing "do not schedule."

`MeetingNotificationService`'s reconcile logic itself — like
`CalendarService`, its structural twin — is not directly unit tested (it
wraps `UNUserNotificationCenter`, matching the precedent that
EventKit/UserNotifications-wrapping services in this codebase are verified
by build + manual use, not unit tests); its pure decision logic (which
events qualify, what identifiers are desired) should be factored into
`MeetingLinkSupport` or a similarly pure helper wherever possible, so the
untested surface stays as small as the actual OS-API wrapping.

The registration surface (`AppFeature.meetingJoin`) needs the same
`Tests/FeatureCatalogTests.swift` updates Phase 1's `.calendar` and
`.menuBarDate` additions already required — hardcoded `AppFeature.allCases.count`,
the raw-value array, and the `availabilityDefaults` opt-in-on-update
assertion.

## Repo conventions this touches

- **Localization is compiler-enforced.** New fields on
  `CalendarFeatureStrings` (join-mode toggle labels, offset picker
  options, hub copy) need values in all 13 shipped languages before the
  project compiles, same as every prior addition to this file.
- **Docs drift.** `docs/PERMISSIONS.md`'s Notifications section
  (`docs/PERMISSIONS.md:94-103`) gains a new consumer ("meeting-join
  alerts, only for events with a detected video-call link"). `docs/PRIVACY.md`
  needs a new paragraph disclosing that this feature reads event
  descriptions (`notes`) to find meeting links — the first feature in this
  codebase to read that specific field, worth being explicit that it's
  used only for link-pattern matching, held only in memory, and never
  transmitted anywhere.
- **Settings page shape.** The new section in `CalendarSettings.swift`
  follows the same `Form`/`Section` shape Phase 1 already established
  there, not a new page — per the settings-location decision above.

## Open items for the implementation plan

- Exact regex patterns need validation against real, current invite links
  for all three providers before merging — provider URL shapes drift over
  time (Teams in particular has changed its meetup-join URL format more
  than once), so the patterns sketched in Components are a starting point
  the implementation plan should verify, not treat as final.
- Whether `MeetingLinkFeatureTests.swift` is its own file or folds into
  `Tests/CalendarFeatureTests.swift` — both fit the repo's per-feature test
  file convention; a separate file keeps `CalendarFeatureTests.swift` from
  growing past what one pass of TDD steps can reasonably cover in one
  plan task.
- The exact native-app bundle identifiers sketched in Components
  (`us.zoom.xos`, `com.microsoft.teams2`) should be confirmed against
  the actual currently-shipping bundle IDs for each app during
  implementation — these do occasionally change across major app
  versions.
- PR/commit split: at minimum (1) `CalendarEvent` field additions +
  `MeetingLinkSupport` + tests, (2) `MeetingNotificationService` +
  `Notifier`/`AppDelegate` wiring, (3) feature registration, (4) settings
  UI + docs — each independently buildable, final split confirmed in the
  implementation plan.
