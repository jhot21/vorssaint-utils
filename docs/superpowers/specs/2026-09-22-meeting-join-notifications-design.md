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
  (`postWhatsAppOrganization`) this phase's own category follows, though
  that precedent's category registration must be widened rather than
  copied verbatim — see Design decision #11. `.calendar` is Phase 1's own
  permission; someone enabling `.meetingJoin` without ever having opened
  the Calendar tab still hits the calendar permission prompt for the
  first time, via the hub (Design decision #12) — it is not "already
  granted" for them.
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
- No handling for a meeting that's been in progress for a while — a
  trigger time more than 10 minutes in the past is simply not scheduled
  (Error handling, below). A bounded grace window *inside* that 10 minutes
  (waking the Mac 2 minutes into a meeting still notifies) is in scope —
  reversed from an earlier draft of this spec after review pointed out
  that silently dropping every already-started meeting undercuts the
  actual "replace MeetingBar" goal, since MeetingBar itself surfaces a
  meeting that's already running.

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
   `.meetingJoin` entry that starts `CalendarService.shared.syncWithPreferences()`
   *then* `MeetingNotificationService.shared.syncWithPreferences()`, in
   that order — the notification service subscribes to `$events`, so it
   must exist after `CalendarService` is already running or it can miss
   the first emission. `FeatureRuntime`'s stop path for this binding calls
   both services' `stop()` in reverse order. This is the one point where
   Phase 2 touches Phase 1's own service, and it is additive (an OR
   condition), not a rewrite.
5. **Reconcile-on-change, diffed against an in-memory scheduled-id set —
   not `pendingNotificationRequests()`.** An earlier draft of this spec
   diffed directly against `UNUserNotificationCenter.current().pendingNotificationRequests()`
   on every reconcile; review caught that this is racy: `$events` can emit
   in quick succession (EKEventStoreChanged, app activation, and the
   self-scheduled refresh timer can all fire within the same second), and
   `pendingNotificationRequests()` is itself async and reflects UNCenter's
   state as of whenever its completion handler runs, not as of the
   reconcile call — two overlapping reconciles can both see the same
   "missing" identifier and both call `add`, or both see a since-removed
   one as still pending. `MeetingNotificationService` instead keeps its
   own `private var scheduledEventIDs: Set<String>` as the single source
   of truth for "what this service believes it has scheduled," updated
   synchronously as each add/remove is issued, and `reconcile(events:)`
   runs on a private serial queue (or is `actor`-isolated) so overlapping
   `$events` emissions queue rather than interleave. A notification that
   already fired (tapped or dismissed) has no bearing on this set — the
   set tracks *scheduling* intent, not delivery state, so a fired
   notification's id is only removed once its event stops qualifying
   (canceled, link removed, hidden calendar) or the offset window has
   fully elapsed.
6. **Default tap joins — no notification action button.** Confirmed
   directly: the workflow this replaces is "click the notification and
   instantly join," not "click a labeled button on it." The `didReceive`
   handler treats `response.actionIdentifier == UNNotificationDefaultActionIdentifier`
   as the join trigger, alongside the existing WhatsApp-undo branch that
   already handles its own named action.
7. **Notification identity carries the event id AND a frozen fallback
   link — the id is authoritative when available, the frozen link is the
   safety net when it isn't.** The request's `userInfo` stores
   `CalendarEvent.id` (the same occurrence-qualified id Phase 1 already
   guarantees is unique per occurrence) so a live re-detection against
   `CalendarService.shared.events` is preferred at tap time — this
   correctly follows a link the organizer updated between scheduling and
   firing, as the original draft intended. But `userInfo` also freezes the
   `MeetingLink` (`provider` raw value, `browserURL`, `nativeAppURL`) that
   was resolved at schedule time. Review flagged a real cold-launch gap:
   the app can be fully quit when a notification is tapped, and
   `FeatureRuntime.shared.syncAtLaunch()` (`AppDelegate.swift:141`) starts
   `CalendarService`'s refresh asynchronously — `didReceive` can run before
   `events` is populated, so a lookup-by-id would find nothing and silently
   no-op on the exact tap that's supposed to join the meeting. The handler
   now tries the live lookup first and falls back to the frozen link only
   when the id isn't found in `events` yet; the live path stays the common
   case (app already running, which is true the overwhelming majority of
   the time given Vorssaint is a persistent menu bar app), so the "always
   re-run detection" behavior described above still holds whenever it can.
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
11. **Notification categories are registered from one shared call site,
    not per-feature.** Review caught a real bug risk in the original
    Components sketch: `Notifier.swift:38-58`'s `postWhatsAppOrganization`
    calls `center.setNotificationCategories([UNNotificationCategory(identifier:
    whatsAppOrganizerCategoryIdentifier, ...)])` — a literal single-element
    array. `setNotificationCategories` *replaces* the entire registered
    set; it does not merge. A naive `postMeetingJoin` following the exact
    same shape would silently unregister the WhatsApp category the moment
    it first ran (and vice versa, depending on call order), breaking
    whichever feature's category was registered first. This phase adds a
    single `Notifier.registerCategories()` called once at launch (from the
    same place `AppDelegate` already wires up `UNUserNotificationCenter.current().delegate`)
    that passes the *union* of both categories in one `setNotificationCategories`
    call; `postWhatsAppOrganization` and the new `postMeetingJoin` both
    stop calling `setNotificationCategories` themselves.
12. **The `.calendar` permission prompt for `.meetingJoin`-only users goes
    through the existing hub flow — no new bespoke UI.** Someone enabling
    `.meetingJoin` without `.calendar` hits the same permission-request
    surface any other feature's hub toggle already provides (the standard
    "this feature needs access to X" hub-portal prompt), not a new
    in-context prompt inside `CalendarSettings.swift`. This was an open
    question in an earlier draft; settling it here means the implementation
    plan does not need to design new permission UI — it reuses what every
    other permissioned feature in the hub already does.

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
  exact patterns against real invite links, not just this spec's sketch).
  Review ran the original sketch's patterns through actual Python
  matching against both valid links and adversarial near-misses and found
  two real classes of bug, both fixed in the revised patterns below:

  - **Unanchored host matching produced false positives.**
    `[\w.-]*zoom\.(?:us|com)` matches `evilzoom.com` and `myzoom.us`
    (`zoom.us`/`zoom.com` need not be the actual host — the pattern only
    checks that those characters appear somewhere before a `/`). The
    revised pattern anchors the host explicitly after the scheme:
    `https?://(?:[\w-]+\.)*zoom\.(?:us|com)/(?:j|my|webinar)/[^\s"'<>]+`
    (the `(?:[\w-]+\.)*` prefix allows legitimate subdomains like
    `company.zoom.us` while `zoom\.(?:us|com)` must be the actual
    registrable domain, not a substring anywhere in the host).
  - **Overly narrow character classes truncated real query strings.**
    `[\w?=&-]+` excludes `.`, `%`, and `/`, all of which appear in real
    Zoom/Teams meeting-id and password query parameters — review's Python
    test showed the original pattern truncating a real invite URL
    mid-query. The revised patterns use `[^\s"'<>]+` (anything but
    whitespace or characters that would terminate a URL embedded in HTML
    or plain text) for the path/query tail instead.

  Revised patterns:
  - Zoom: `https?://(?:[\w-]+\.)*zoom\.(?:us|com)/(?:j|my|webinar)/[^\s"'<>]+`,
    native scheme `zoommtg://zoom.us/join?confno=<meeting-id>` built from
    the matched URL's path/query — **except** a `/my/<name>` personal-room
    link, which stays browser-only (see Error handling).
  - Google Meet: `https?://meet\.google\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}`
    (Meet's actual `xxx-xxxx-xxx` room-code shape) rather than the
    original `[a-z-]+`, which also matched non-meeting paths like
    `meet.google.com/landing` or `meet.google.com/about` — no native
    scheme. The exact code-shape regex is still an approximation of a
    format Google does not publicly document as stable; flagged as an
    Open item for real-link validation, not asserted as final here.
  - Microsoft Teams: `https?://teams\.(?:microsoft|live)\.com/l/meetup-join/[^\s"'<>]+`,
    native scheme built by swapping the `https` scheme for `msteams`. The
    original pattern's `[\w%.-]+` truncated at `@`, which real Teams
    meetup-join URLs contain (in the organizer/thread-id segment) — fixed
    by the same `[^\s"'<>]+` tail. `teams.live.com` (the consumer/personal
    Teams domain, distinct from `teams.microsoft.com`) is added since
    review noted MeetingBar itself treats both as the same provider; this
    is a scope addition flagged for confirmation in the implementation
    plan, not asserted as settled.

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

      // Source of truth for "what this service believes it has scheduled" —
      // see Design decision #5. Mutated synchronously as add/remove is
      // issued; reconcile runs serialized so overlapping $events emissions
      // never interleave two reads/writes of this set.
      private var scheduledEventIDs: Set<String> = []
      private let reconcileQueue = DispatchQueue(label: "meeting-join.reconcile")

      private func reconcile(events: [CalendarEvent]) { ... }
  }
  ```

  The pure decision logic — given the current event list, the configured
  offset, and the current `scheduledEventIDs`, which ids to add and which
  to remove — is factored into a standalone, testable function (or a small
  protocol `MeetingReconcileDeciding` this service conforms to) that takes
  no `UNUserNotificationCenter` dependency, per the Testing section's
  narrowing of the untested OS-wrapping surface.

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
  `postMeetingJoin(event:link:offset:)`-shaped entry point that builds a
  `UNTimeIntervalNotificationTrigger` — this file's first use of a
  non-nil trigger; every existing `Notifier` call fires immediately
  (`trigger: nil`). Unlike `postWhatsAppOrganization`, this method does
  **not** call `setNotificationCategories` itself — that call moves to
  the new shared `registerCategories()` (Design decision #11), and both
  `postWhatsAppOrganization` and `postMeetingJoin` lose their own
  category-registration call as part of this change.
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
  `energyProfile` (`.periodic`, not `.idle` — the feature schedules
  timed system notifications on a rolling basis via reconcile, which is
  the same category of recurring background work `.periodic` denotes
  elsewhere in this catalog; `.idle` is reserved for features with no
  ongoing activity of their own, which undersells what this feature
  actually does even though it has no *polling loop* of its own),
  `SettingsPage` destination
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
   `CalendarService.shared.$events`. `CalendarService` publishes this
   `@Published` property on every `refresh()` call unconditionally — it
   has no equality gate, so `MeetingNotificationService` sees an emission
   on every EventKit-store-changed notification, app activation, clock/day
   change, and self-scheduled refresh timer tick, not only on a real
   content change. Each emission is routed onto `reconcileQueue`
   (serialized, Design decision #5) rather than assumed to represent a
   meaningful change; `reconcile(events:)` itself is cheap to run
   redundantly since it diffs against `scheduledEventIDs` rather than
   doing work per emission.
3. `reconcile(events:)` filters to non-all-day events with
   `MeetingLinkSupport.detect(for:) != nil`, computes each one's trigger
   date (`event.start` minus the configured offset), drops any whose
   trigger date is more than 10 minutes in the past (Error handling —
   revised from "any amount in the past" to allow the in-scope grace
   window), and builds the desired set of notification identifiers (one
   per qualifying event, keyed by `event.id`).
4. It diffs the desired set against `scheduledEventIDs` (Design decision
   #5) — not `pendingNotificationRequests()` — removing ids present in
   `scheduledEventIDs` but absent from the desired set (event no longer
   qualifying: canceled, link removed, hidden calendar), adding ids in the
   desired set but absent from `scheduledEventIDs`, leaving everything
   else untouched. Both add and remove update `scheduledEventIDs`
   synchronously as they're issued, and both call through to
   `UNUserNotificationCenter` using this feature's own category-scoped
   identifiers, so a stray or leftover request from a previous run is
   still cleaned up correctly even though `scheduledEventIDs` itself isn't
   persisted across launches (a fresh launch starts with an empty set and
   an empty diff against a clean desired set — no stale system requests
   from a prior run collide, since request identifiers are derived
   deterministically from `event.id`).
5. Each added request uses `Notifier.postMeetingJoin(event:link:offset:)`,
   itself building a `UNTimeIntervalNotificationTrigger` (floor 0.5s, per
   `UNTimeIntervalNotificationTrigger`'s own minimum) and a
   `UNMutableNotificationContent` with `categoryIdentifier` set to the new
   meeting-join category and `userInfo` carrying both `eventIDKey = event.id`
   and the frozen `MeetingLink` fields (Design decision #7).
6. When the notification fires and the person taps it,
   `AppDelegate.userNotificationCenter(_:didReceive:)` reads `event.id`
   from `userInfo` and tries `CalendarService.shared.events` first; if
   found, it re-runs `MeetingLinkSupport.detect(for:)` for a fresh link
   (the common case — the app is normally already running). If not found
   (cold-launch race, Design decision #7), it falls back to the frozen
   `MeetingLink` from `userInfo`. Either way it then opens the resolved
   link: native app first if the provider has one and its own toggle is on
   (resolved via `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)`,
   matching `CalendarAgendaListView.openInCalendar`'s own resolve-or-fail
   pattern), browser otherwise. If neither the live lookup nor the frozen
   fallback resolves anything, the tap no-ops (Error handling).

## Error handling & edge cases

- **A trigger time in the past when `reconcile` runs, within a 10-minute
  grace window**, is still scheduled — with its trigger clamped to fire
  1 second from now rather than at the original (past) time, so someone
  whose Mac wakes 2 minutes into a meeting still gets notified and can
  join, matching the reversed Non-goal above. **Past that 10-minute
  window**, the event is not scheduled at all — a meeting the person's
  Mac missed by that much is treated as over for notification purposes.
  10 minutes is this spec's own chosen boundary (not verified against
  MeetingBar's own source), picked as long enough to cover typical
  sleep-wake and cold-launch delays without notifying for meetings that
  are plausibly already wrapping up; the implementation plan may tune it.
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
  or the calendar it belongs to was just hidden in settings) — the live
  lookup fails, but the frozen `MeetingLink` in `userInfo` (Design
  decision #7) still resolves, so the tap still joins the meeting even
  though the event no longer exists in `CalendarService.shared.events`.
  This is a deliberate difference from "no-op": a person tapping a
  notification for a meeting they're trying to join right now should
  still be able to join it even if the calendar entry itself changed
  underneath them. The tap only truly no-ops if neither the live lookup
  nor the frozen fallback yields a link (userInfo malformed or missing —
  should not happen in practice, but guarded defensively).
- **`didReceive` runs before `CalendarService` has finished its first
  post-launch refresh** (cold launch, notification tapped from a fully
  quit state) — the live lookup in `CalendarService.shared.events` finds
  nothing yet, so the handler falls back to the frozen `MeetingLink`
  (Design decision #7) rather than silently no-op-ing on the exact tap
  meant to join a meeting.
- **Declined or canceled events** never reach this service — `CalendarService`
  already filters those out during EventKit fetch (Phase 1, unchanged), so
  `MeetingNotificationService` only ever sees events someone actually
  plans to attend.
- **`stop()` and a reconcile pass clear notifications very differently —
  this distinction is deliberate, not an inconsistency.** A *reconcile*
  clearing a notification (link removed, event canceled, calendar hidden,
  or — see below — permission revoked) is this service actively deciding
  the notification is no longer warranted, and it removes it immediately.
  `stop()` itself does the opposite: it only cancels the `$events`
  subscription so no *further* reconciles run; it does **not** walk
  `scheduledEventIDs` and cancel each one. A meeting notification already
  queued for the next few minutes still fires even if the feature is
  switched off moments before — removing it on `stop()` would be
  surprising (someone expects the meeting they were just notified about
  to still exist), and if the feature is re-enabled, the first reconcile
  after re-enabling naturally cleans up anything genuinely stale by then.
  The asymmetry is intentional: reconcile reacts to the calendar data
  changing; `stop()` reacts to the feature toggle changing, and a feature
  toggle isn't itself evidence a meeting stopped being real.
- **Calendar permission revoked while notifications are already
  scheduled** (a person turns off calendar access in System Settings
  mid-session) — `CalendarService.shared.events` goes empty on its next
  refresh once the permission-denied state is detected, which `reconcile`
  reads exactly like any other empty/no-longer-qualifying result: every
  currently-scheduled meeting-join notification is removed via the normal
  diff, `scheduledEventIDs` becomes empty, and nothing schedules again
  until permission is restored and a real event list starts flowing.
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
- **Named false-positive/truncation regression cases**, from the specific
  failures review's Python testing surfaced against the pre-revision
  patterns — each must be a named test, not folded into a generic
  near-miss case, so a future regex edit can't silently reintroduce them:
  - `https://evilzoom.com/j/12345` and `https://myzoom.us/j/12345` must
    NOT match Zoom (unanchored-host false positive).
  - `https://meet.google.com/landing` and `https://meet.google.com/about`
    must NOT match Google Meet (non-room-code path false positive).
  - A Teams meetup-join URL containing `@` in its organizer/thread-id
    segment must match in full, not truncate at the `@` (character-class
    truncation).
  - A Zoom URL with a query string containing `.`, `%`, or `/` (a realistic
    password/tracking parameter) must capture the full query, not truncate
    at the first disallowed character.
- The Zoom personal-room exclusion: a `/my/<name>` link detects as Zoom
  but produces a `nil` `nativeAppURL`.
- No match across all three sources returns `nil`, not a false positive.
- Trigger-time computation for each offset option, including: the
  already-more-than-10-minutes-in-the-past case correctly producing "do
  not schedule," and the within-the-10-minute-grace-window case correctly
  producing a clamped near-immediate trigger rather than the original
  (past) time.
- The reconcile decision logic (add/remove/keep given a desired set and
  the current `scheduledEventIDs`) gets its own tests against the pure
  helper or protocol seam described in Components — inputs and expected
  add/remove sets, no `UNUserNotificationCenter` involved, following
  review's suggestion that this logic is worth a real test seam precisely
  because it's easy to get subtly wrong (as the original
  `pendingNotificationRequests()`-diffing draft was).

`MeetingNotificationService` itself — like `CalendarService`, its
structural twin — is not directly unit tested where it actually touches
`UNUserNotificationCenter` (matching the precedent that EventKit/UserNotifications-wrapping
services in this codebase are verified by build + manual use, not unit
tests). That untested surface is now deliberately narrow: the decision
logic (which events qualify, what identifiers to add/remove) is factored
out into the pure helper/protocol seam described in Components and tested
directly, per the point above — only the actual `add`/`remove` calls
against `UNUserNotificationCenter` itself stay outside the unit-test
boundary.

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
  transmitted anywhere. It should also note that a scheduled notification's
  `userInfo` (Design decision #7) carries the resolved meeting link
  (provider, browser URL, native app URL) as local notification-request
  payload — still local-only, delivered through `UNUserNotificationCenter`
  and never transmitted off-device, but worth stating explicitly since
  it's the first feature in this codebase to persist link data into a
  system notification payload rather than holding it only in an
  in-process `@Published` property.
- **Settings page shape.** The new section in `CalendarSettings.swift`
  follows the same `Form`/`Section` shape Phase 1 already established
  there, not a new page — per the settings-location decision above.

## Open items for the implementation plan

- The revised regex patterns in Components fix the specific
  false-positive/truncation bugs review found (unanchored hosts,
  truncating character classes), but still need validation against real,
  current invite links for all three providers before merging — provider
  URL shapes drift over time (Teams in particular has changed its
  meetup-join URL format more than once, and the Google Meet room-code
  shape isn't publicly documented as stable), so they remain a starting
  point the implementation plan should verify, not treat as final. The
  `teams.live.com` scope addition (Design decision, Components) also
  needs confirming — it wasn't part of the originally-approved
  three-provider scope.
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
