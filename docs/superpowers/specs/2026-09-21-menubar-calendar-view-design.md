# Menu bar calendar tab — Phase 1 (Itsycal replacement)

Status: draft, awaiting implementation plan.

This is Phase 1 of a two-phase feature. Phase 2 (meeting-link detection and
join notifications, replacing MeetingBar) is a separate spec, built on top
of the event model this phase establishes.

## Problem

The person maintaining this fork currently runs two third-party menu bar
apps: **Itsycal**, for a quick glance at their calendar (month grid with
event dots, upcoming-events agenda list), and **MeetingBar**, for
video-call join notifications. The goal is to replace both with a native
Vorssaint feature, reachable from the existing menu bar panel rather than
a separate app/icon.

Vorssaint already has a calendar view, but it lives inside the "Dynamic
Island" notch feature, which this person does not use and does not want to
adopt just to get a calendar. They want a **menu bar panel tile** instead —
the same interaction shape as Clipboard, Port Manager, Window Layout, and
the panel's other utilities.

## Scope

Phase 1 only: the calendar-viewing experience.

- A new "Calendar" tile in the menu bar panel's utility tray.
- A month grid (current month, prev/today/next navigation) with up to
  3 dot colors per day for that day's calendars, matching Itsycal's
  dot-color contract.
- An agenda list below the grid showing upcoming events grouped by day.
  Clicking a day in the grid filters/scrolls the agenda to that day
  (confirmed in brainstorming — not a pure glance-only view like the
  screenshot Itsycal reference).
- Per-calendar show/hide in Settings, matching Itsycal's checklist.
- Calendar permission request UI, matching the existing Notch calendar's
  pattern and copy.

Explicitly **not** in Phase 1 (Phase 2's territory): video-call link
detection, join notifications, per-provider open-behavior settings,
notification-timing settings.

## Why a new, independent module — not shared code with the Notch calendar

Vorssaint already has a mature calendar data/render layer for the Dynamic
Island: `NotchCalendarService.swift` (an actor-based `EKEventStore` reader
plus an `ObservableObject` lifecycle owner), `NotchCalendarSupport.swift`
(pure grid/date functions), and `NotchCalendarView.swift` (SwiftUI
rendering). On the surface this looks like exactly what Phase 1 needs.

Two things rule out reusing it directly:

1. **It doesn't carry the data Phase 2 needs.** `NotchCalendarEvent`
   (`NotchCalendarSupport.swift`) has no `url`, `notes`, or `location`
   field — `NotchCalendarService`'s `EKEvent` → `NotchCalendarEvent`
   mapping never reads them. Phase 2's link detector needs exactly those
   fields. Reusing the Notch type as-is means Phase 2 can't work; extending
   it means editing a file that is not ours.
2. **That feature is under active upstream development**, per this fork's
   sync history — this repo periodically merges upstream, and Dynamic
   Island's calendar code has already changed substantially between two
   recent sync cycles. A "shared" module built by extracting or modifying
   `NotchCalendarService`/`NotchCalendarSupport` becomes fork-only code
   sitting on a moving target: every future sync that touches Dynamic
   Island's calendar internals would likely land inside that shared module
   and force a manual conflict re-resolve, the same shape of work this
   fork's syncs already require for much smaller features (see this
   session's resolution of the 2026-09-21 sync PR, where every conflict
   was in files both sides had independently extended).

Building a new, self-contained module — new files, own event type, own
service — costs some duplication of the fetch/predicate/filter logic
(~50-80 lines) against a stable, low-churn layer (`EKEventStore` querying
hasn't changed shape in this codebase across the observed sync history).
That trade is worth it: it keeps every future sync's conflict surface to
pure *additions* (new enum cases, new dictionary entries) in shared files
like `Defaults.swift` and `FeatureCatalog.swift` — the same additive
pattern this session's conflicts already showed is low-risk to resolve —
rather than *contested edits* inside a file upstream is actively rewriting.

The one thing actually shared with the Notch calendar is calendar
*permission state* — `Permissions.shared.calendarAccess`
(`Core/Permissions.swift`) and the existing
`NSCalendarsFullAccessUsageDescription` entitlement/usage string. That
layer is generic permission plumbing, not calendar-feature logic, and
isn't part of Dynamic Island's active development — safe to depend on
directly.

## Non-goals

- No event creation/editing. Read-only, same restraint as the Notch
  calendar and as this fork's other feature additions (e.g. Command Bar's
  bookmark sources are also read-only).
- No cross-calendar-account merging beyond what EventKit already presents
  as one unified event list — "per-calendar show/hide" operates on
  EventKit's own `EKCalendar` list, not a custom account model.
- No video-call link detection, join notifications, or notification action
  of any kind — see Phase 2, not this spec.
- No pin/floating-window mode (visible in the Itsycal reference
  screenshot's pin icon) — this is a panel tile like every other utility,
  opened and closed the same way Clipboard or Port Manager are.
- No in-app event creation button (the reference screenshot's "+") — out
  of scope, matches "read-only calendar glance."

## Design decisions

1. **Own EventKit reader, not a shared/extracted one.** See "Why a new,
   independent module" above.
2. **Month grid: pure SwiftUI (`LazyVGrid`/`Grid`), not an
   `NSViewRepresentable`-wrapped AppKit view.** Itsycal itself uses
   hand-rolled `NSView` subclasses with manual hit-testing
   (`MoCalGrid`/`MoCalCell`), but this codebase's UI layer is SwiftUI
   throughout, including an existing in-repo precedent for a SwiftUI
   month-grid-with-dots (`NotchCalendarMonthView` — referenced for the
   *pattern*, not reused as code, per the module-independence decision
   above). Matching the codebase's own convention outweighs Itsycal's
   AppKit approach.
3. **Background-refreshing service, not fetch-on-open.** Phase 2 will need
   a live-in-the-background service regardless, to catch meetings starting
   while the panel is closed. Building the `NotchCalendarService`-shaped
   lifecycle (self-scheduled refresh to the next event boundary,
   `EKEventStoreChanged` observer, day-rollover handling, `stop()` on
   sleep/lock) now avoids doing this twice.
4. **Capture `url`/`notes`/`location` on the event model now, unused until
   Phase 2.** Cheap to add today; expensive to retrofit later without
   touching every call site that already consumes the event type.
5. **Day selection filters the agenda** (confirmed in brainstorming,
   diverging from the reference screenshot's non-filtering behavior) —
   clicking a grid day scrolls/filters the agenda list to that day,
   matching Itsycal's actual (not just pictured) behavior.
6. **Calendar visibility: opt-out, not opt-in.** Stored as a hidden-ID set
   (`calendarHiddenCalendarIDs`), empty by default, so every calendar shows
   immediately on a fresh install with no setup required — nobody has to
   individually enable every calendar they already use. Itsycal's own
   preference storage is opt-in (a `SelectedCalendars` allow-list), but
   that requires the first-run experience to already know every calendar
   exists; opt-out needs no such bootstrapping.

## Components

New files, all under a new `Calendar` grouping, parallel to how `Notch`,
`CommandBar`, and `Clipboard` each have their own `Services/<Feature>/` and
view files:

- `Sources/Vorssaint/Services/Calendar/CalendarService.swift` — actor-based
  `EKEventStore` reader (`CalendarReader`) plus an `ObservableObject`
  singleton (`CalendarService.shared`) owning the refresh lifecycle:
  `refresh()` (cancels in-flight work, re-fetches, self-schedules a `Timer`
  to the next event boundary), `syncWithPreferences()`,
  `EKEventStoreChanged`/day-rollover/sleep-lock observers, `stop()`. Same
  shape as `NotchCalendarService`, independent type.
- `Sources/Vorssaint/Services/Calendar/CalendarSupport.swift` — pure
  functions: month-grid day math, `dotColors(on:events:)` (nil / empty /
  up to 3 colors, Itsycal's delegate contract), `upcomingGroups(events:
  from:)` grouping events into `(Date, [CalendarEvent])` for the agenda.
- `Sources/Vorssaint/UI/MenuPanel/PanelCalendarView.swift` — the tile's
  root view, following the `PanelClipboardView`/`PanelPortManagerView`
  shape: takes a back-closure, resets `PanelInteractionState.shared`.
- `Sources/Vorssaint/UI/MenuPanel/CalendarMonthGridView.swift` — the grid
  itself: prev/today/next navigation, day cells with dots, selection
  state.
- `Sources/Vorssaint/UI/MenuPanel/CalendarAgendaListView.swift` — the
  upcoming-events list, day-grouped, scrolls/filters to the grid's
  selected day.
- `Sources/Vorssaint/UI/Settings/CalendarSettings.swift` — one toggle per
  `EKCalendar`, grouped by source/account (mirrors Itsycal's checklist;
  structurally follows this codebase's existing settings-page shape, e.g.
  `NotchSettings.swift`'s `@AppStorage`-per-toggle pattern).

**Data model** (in `CalendarSupport.swift` or a dedicated
`CalendarEvent.swift`):

```swift
struct CalendarEvent: Identifiable {
    let id: String                       // EKEvent.eventIdentifier
    let calendarItemIdentifier: String
    let title: String
    let calendarID: String               // EKCalendar.calendarIdentifier
    let calendarTitle: String
    let color: NSColor                   // EKCalendar.cgColor
    let start: Date
    let end: Date
    let allDay: Bool
    let location: String?
    let notes: String?
    let url: URL?                        // EKEvent.url
    let recurring: Bool
}
```

**Registration** (additive changes to shared files — the low-conflict-risk
pattern from Design decision #1):

- `Sources/Vorssaint/UI/MenuPanel/MenuPanelView.swift`: new
  `UtilityPanelItem.calendar` case, mapped to a new `AppFeature.calendar`.
- `Sources/Vorssaint/Core/FeatureCatalog.swift`: new `AppFeature.calendar`
  case, group `.tools` (matching Command Bar/Port Manager), permissions
  `[.calendars]` if `AppPermission` already has a calendar case (it should
  — `docs/PERMISSIONS.md` already lists "Calendars" as a permission row
  for the Notch feature) — confirm the exact `AppPermission` case name
  during implementation.
- `Sources/Vorssaint/Core/Defaults.swift`: new `DefaultsKey.panelUtilityCalendar`
  (Bool, registered `true`, panel visibility toggle) and
  `DefaultsKey.calendarHiddenCalendarIDs` (String, registered `""`,
  delimited list of hidden `EKCalendar.calendarIdentifier` values —
  same storage shape as `windowPreviewExcludedApps`/
  `clipboardHistoryIgnoredApps`).
- `Sources/Vorssaint/Core/FeatureStrings.swift` (or a new
  `CalendarFeatureStrings.swift` alongside `CommandBarStrings.swift`): a
  new localized-strings struct, one value per shipped language (13 today —
  see Repo conventions).

## Data flow

1. On panel open (or app launch, since the service runs in the
   background per Design decision #3), `CalendarService.refresh()` fetches
   a bounded window: the visible month plus a ~30-day agenda lookahead —
   bounding the fetch the way Itsycal's `EventCenter` decouples "what range
   needs fetching" from "what's currently displayed."
2. `CalendarReader.fetch(interval:)` builds an `EKEventStore` predicate for
   that range, filters out canceled and declined events (matching both
   `NotchCalendarService` and Itsycal's own filtering), maps each `EKEvent`
   to `CalendarEvent`.
3. `CalendarService` applies the `calendarHiddenCalendarIDs` filter before
   publishing `@Published events: [CalendarEvent]`.
4. `CalendarMonthGridView` derives dot colors per visible day via
   `CalendarSupport.dotColors(on:events:)`.
5. `CalendarAgendaListView` derives day-grouped upcoming events via
   `CalendarSupport.upcomingGroups(events:from:)`; selecting a grid day
   scrolls/filters this list to that day (Design decision #5).
6. `CalendarService` re-fetches on `EKEventStoreChanged` (an external
   calendar edit), on day rollover, and self-schedules to the next event
   boundary — the same reasons `NotchCalendarService` does, independently
   implemented.
7. `stop()` on sleep/lock, matching the Notch calendar's resource
   discipline.

## Error handling & edge cases

- `Permissions.shared.calendarAccess != .fullAccess` → `PanelCalendarView`
  shows a permission-request card, reusing the Notch calendar's existing
  copy/pattern (not its code) — request button, explanation, System
  Settings deep link.
- EventKit fetch failure (store unavailable, predicate error) → treat as
  an empty event list; the view shows no events but doesn't crash. No
  distinct error UI — matches this codebase's existing "silent empty
  state" convention for failed background reads (see the bookmarks spec's
  `CommandBarFileSearch` precedent).
- All-day events are included but flagged (`allDay`) so the agenda can
  render them without a time range.
- Recurring events are expanded by EventKit itself (predicate-based fetch
  already returns individual occurrences); `recurring` is carried through
  for Phase 2's benefit (a recurring meeting's link doesn't need
  re-detecting every occurrence, though the exact reuse mechanism is a
  Phase 2 decision).
- A calendar deleted/removed mid-session (its `calendarIdentifier` still
  present in `calendarHiddenCalendarIDs`) is simply inert — no cleanup
  pass needed, matching how other identifier-set preferences in this
  codebase (e.g. `windowPreviewExcludedApps`) tolerate stale entries.

## Testing

Pure `CalendarSupport` functions get real tests, injected with synthetic
`CalendarEvent` fixtures — no live EventKit access needed:

- Month-grid day math (correct days shown for a given month, including
  leading/trailing days from adjacent months).
- `dotColors(on:events:)`: nil for no events, correct set for 1-3+
  distinct calendar colors on one day.
- `upcomingGroups(events:from:)`: correct day-grouping and ordering,
  all-day events included, canceled/declined events already filtered
  upstream so not re-tested here.

Following the repo's established location for this kind of test (per the
bookmarks spec's precedent): a new `MARK` section in `Tests/MetricsTests.swift`
— **except** this repo's test file has since been split into per-feature
files (`Tests/ClipboardFeatureTests.swift`,
`Tests/CommandBarFeatureTests.swift`, etc., from the 2026-09-21 sync's
`refactor(tests): split independent feature suites` change) — so the
actual target is a new `Tests/CalendarFeatureTests.swift`, registered as a
new suite entry in `MetricsTests.swift`'s `groups` array, matching that
newer convention instead of the older single-file one.

The new `AppFeature.calendar` case needs matching entries added to
`Tests/FeatureCatalogTests.swift`'s exhaustive permission/hub tables —
this repo's test suite enforces exhaustiveness on `AppFeature`-keyed
switches (seen directly in this session: adding `AppFeature.commandBar`'s
`.fullDiskAccess` permission required updating a stale `activeSet`
assertion in that same file).

Outside the pure-function harness: verified by `./build.sh` and
`./build.sh --test`, plus manual use — grid navigation, dot accuracy
against a real calendar with events, agenda day-filtering, permission-card
behavior with access both denied and granted, and calendar show/hide
actually reflected in the panel.

## Repo conventions this touches

- **Localization is compiler-enforced, not optional.** Every new
  user-facing string (tile label, grid nav labels/accessibility strings,
  agenda empty state, permission-card copy if not reusing the Notch
  calendar's exact strings, settings toggle labels) is a new field on a
  `*FeatureStrings` struct, which means a value in all 13 shipped
  languages before it compiles — matching the pattern this session already
  worked through for Clipboard's `pasteAfterSelect`/`menuBarPreview`
  strings.
- **Docs drift.** `docs/PERMISSIONS.md`'s "Calendars" row currently reads
  "Upcoming appointments in the notch" — gains a second consumer (this
  panel tile). `docs/PRIVACY.md`'s "Optional notch features" section
  describes calendar access as notch-specific ("Calendar access is
  requested only from the permission button. The notch reads upcoming
  events...") — needs a parallel paragraph, or a rewording that isn't
  notch-scoped, once this feature also reads calendar data outside the
  notch.
- **Settings page shape.** `CalendarSettings.swift` follows
  `NotchSettings.swift`'s established shape: `@AppStorage` per toggle,
  `@ObservedObject` on the new `CalendarService`, one section for
  visibility toggles plus a per-calendar checklist section.

## Open items for the implementation plan

- Exact `AppPermission` case name for calendar access — confirm it exists
  or needs adding, and how `AppFeature.calendar`'s permission-gating
  integrates with the already-published `Permissions.shared.calendarAccess`.
- Agenda lookahead window (30 days suggested above) and month-grid fetch
  range are implementation-plan-level tuning, not fixed by this spec.
- Whether `CalendarSettings.swift` needs its own settings-page entry point
  (a new item in whatever top-level settings navigation lists Clipboard,
  Command Bar, etc.) or nests under an existing "Panel" settings area —
  confirm against the current Settings navigation structure during
  implementation.
- PR/commit split: at minimum (1) service + data model + tests, (2) grid
  view, (3) agenda view + day-selection wiring, (4) settings page +
  registration + docs — each independently buildable and reviewable,
  final split to be confirmed in the implementation plan.
