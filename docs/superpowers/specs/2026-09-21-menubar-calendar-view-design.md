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

1. **It doesn't carry `url`/`notes`, which Phase 2 needs.** `NotchCalendarEvent`
   (`NotchCalendarSupport.swift:15-25`) already carries `location`,
   `calendarItemIdentifier`, and `recurring`, and already builds a
   Calendar.app deep link from them (`NotchCalendarSupport.eventURL`,
   `:105-118`) — it's more complete than a first pass at this spec assumed.
   What it genuinely lacks is `url` and `notes`, which Phase 2's link
   detector needs. That gap alone is a narrower reason to build fresh than
   originally stated, so reason 2 below is doing most of the work.
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
(`Core/Permissions.swift`) and `AppPermission.calendar`
(`FeatureCatalog.swift:48`), which already exists as a general-purpose
permission case, not something to add. That layer is generic permission
plumbing, not calendar-feature logic, and isn't part of Dynamic Island's
active development — safe to depend on directly.

One thing is shared but **not** safe to reuse verbatim: the system usage
string. `NSCalendarsFullAccessUsageDescription`
(`Resources/Info.plist:63-64`, duplicated across all 13 localized
`InfoPlist.strings` files) reads "Show your upcoming appointments in the
notch. Calendar events stay on this Mac." — this is the literal text macOS
shows in the permission prompt, and it says "notch" by name. A panel
permission card that triggers this prompt for someone who doesn't use the
notch will show them notch-specific copy for a notch-free feature. This
string has to be reworded (in all 13 languages) as part of this feature,
not treated as inert shared infrastructure.

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

Explicitly **included**, added after review: clicking an agenda event
opens it in Calendar.app, the same behavior both Itsycal and the existing
Notch calendar already provide (`NotchCalendarView.swift:269-277`, via
`NotchCalendarSupport.eventURL`). Omitting this would make the tile a
dead end for anyone who wants to see an event's full details.

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
3. **Background-refreshing service, not fetch-on-open — kept after
   review, with two gaps closed.** Phase 2 will need a live-in-the-background
   service regardless, to catch meetings starting while the panel is
   closed; building that lifecycle once, now, avoids doing it twice. Review
   raised two real gaps in the original version of this decision, both
   addressed here rather than left to the implementation plan:
   - **Lifecycle owner.** The Notch service's `stop()` is called by the
     notch's own visibility lifecycle — nothing plays that role for a panel
     tile. This service needs an explicit `FeatureRuntime.bindings[.calendar]`
     entry (see Registration) that starts it when `AppFeature.calendar`
     becomes active and calls `stop()` when it doesn't, so background
     EventKit access doesn't run for someone who's never opened the tile
     yet has the feature nominally available.
   - **Month navigation.** A plain "visible month + 30-day lookahead" fetch
     window (as originally described in Data flow) has no way to represent
     "the panel is closed, fetch nothing month-specific" *and* "the user
     clicked next month, fetch that range" at once. `CalendarService`
     needs a `showMonth(Date?)` entry point mirroring
     `NotchCalendarService.showMonth(_:)` (`:48-52`): `nil` while the panel
     is closed (background refresh still covers the agenda's lookahead
     window, just not a specific grid month), a concrete month while it's
     open, re-fetching on navigation the same way the Notch calendar does.
4. **Don't capture `notes` in Phase 1; defer both `url` and `notes` to
   Phase 2.** Reversed from the original version of this decision after
   review. The original reasoning — "cheap now, expensive to retrofit" —
   doesn't survive Design decision #1: because this is a brand-new,
   self-contained module, every call site that consumes `CalendarEvent` is
   also new and owned by this feature, so adding fields in Phase 2 touches
   only the mapper and its tests, not a retrofit. Meanwhile `notes` is
   real data-minimization exposure: it can contain arbitrary sensitive
   text, held in memory by a background service over a rolling 30-day
   window, for a field Phase 1 never displays and that `PRIVACY.md`
   doesn't yet disclose this feature reading. `location` stays in the
   model (low sensitivity, already precedented in `NotchCalendarEvent`,
   and useful for Phase 1's own agenda display).
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
7. **Three-state view: loading / content / permission-needed, not just
   content-or-empty.** Added after review — "fetch failure → empty list"
   conflated "genuinely no events" with "access was revoked mid-session"
   and had no loading state at all, while the Notch calendar view already
   models this properly (`NotchCalendarView.swift:173-177, 201-202`,
   `loading` + `ProgressView`). `PanelCalendarView` mirrors that pattern:
   a loading spinner before the first successful fetch, the permission
   card when access isn't granted, and the grid/agenda once data exists —
   genuinely-empty (access granted, zero events) renders the grid with no
   dots, not a distinct empty state.
8. **New feature ships opt-in on update, like other permission-gated
   additions.** `AppFeature.calendar` joins the
   `availabilityDefaults` exception list (`FeatureCatalog.swift:367-373`)
   alongside `.fanControl`, `.diskImageInstaller`, `.killProcess`, and
   `.portManager` — features that request a new OS permission or otherwise
   change what the app does ship uninstalled by default on update, so
   nobody already running Vorssaint sees a Calendar permission prompt
   appear unannounced after an update. A fresh install still gets Calendar
   available immediately, since `availabilityDefaults` only governs the
   update-preservation path.

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
`CalendarEvent.swift`), corrected after review to fix two bugs a first
pass had:

```swift
struct CalendarColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
}

struct CalendarEvent: Identifiable, Equatable, Sendable {
    // EKEvent.eventIdentifier alone collides across a recurring series —
    // every occurrence shares one identifier. Disambiguate with the
    // occurrence start, matching NotchCalendarService.swift:23 exactly.
    let id: String                       // eventIdentifier + ":" + start.timeIntervalSinceReferenceDate
    let calendarItemIdentifier: String
    let title: String
    let calendarID: String               // EKCalendar.calendarIdentifier
    let calendarTitle: String
    let color: CalendarColor             // sRGB components, not NSColor —
                                          // NSColor isn't Sendable and this
                                          // crosses the CalendarReader actor
                                          // boundary into @Published state;
                                          // equality also has to be reliable
                                          // for the ≤3-dot dedup below.
    let start: Date
    let end: Date
    let allDay: Bool
    let location: String?
    let recurring: Bool                  // hasRecurrenceRules || isDetached,
                                          // matching NotchCalendarService.swift:28
    // url/notes deferred to Phase 2 — see Design decision #4.
}
```

**Registration** (additive changes to shared files — the low-conflict-risk
pattern from Design decision #1). Review found this list materially
undercounted on a first pass: `AppFeature` participates in more exhaustive
switches than the Notch-independence framing suggested, and — critically —
none of them are optional, since the compiler forces every arm:

- `Sources/Vorssaint/UI/MenuPanel/MenuPanelView.swift`: new
  `UtilityPanelItem.calendar` case (`feature`, `isVisible`, `itemView`,
  `resetPanelDefaults` — `:527, 728, 752, 1047`).
- `Sources/Vorssaint/Core/FeatureCatalog.swift`: new `AppFeature.calendar`
  case in `group` (`:100`), `symbolName` (`:127`), `enabledKeys` (`:221`),
  `permissions` (`:283`, using the existing `AppPermission.calendar`
  case — `:48`), and `availabilityDefaults`'s exception list (`:367-373`,
  per Design decision #8).
- `Sources/Vorssaint/Core/FeaturePresets.swift`: `energyProfile` (`:90`)
  — likely `.periodic`, matching `clipboardHistory`'s profile for a
  background-refreshing read.
- `Sources/Vorssaint/UI/Settings/FeatureHubSettings.swift`: `hubTitle`
  (`:845`) and `hubDescription` (`:893`), each needing new localized
  strings.
- `Sources/Vorssaint/UI/Settings/FeatureVisibilitySupport.swift`: a new
  `SettingsPage.calendar` case (`:9-13`, a flat list — there is no "Panel"
  grouping to nest under) and its mapping.
- `Sources/Vorssaint/App/FeatureRuntime.swift`: a `bindings[.calendar]`
  entry (`:103` and its surrounding dictionary) that starts/stops
  `CalendarService` — this is the lifecycle owner Design decision #3
  requires, and it is easy to skip silently: `bindings` is a dictionary,
  so a missing entry compiles cleanly and simply never starts or stops the
  service.
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
- `Tests/FeatureCatalogTests.swift`: the hardcoded `AppFeature.allCases.count
  == 69` (`:290`) and the exact ordered `AppFeature`/`AppPermission`
  raw-value arrays (`:293-303`, `:448-452`) all move by one entry — these
  are assertions to update, not bugs to work around.

## Data flow

1. `FeatureRuntime.bindings[.calendar]` starts `CalendarService` when
   `AppFeature.calendar` becomes active — independent of whether the panel
   is currently open (Design decision #3's lifecycle-owner fix). Its
   always-on fetch window is the ~30-day agenda lookahead only;
   `visibleMonth` starts `nil`.
2. `PanelCalendarView.onAppear` calls `CalendarService.showMonth(currentMonth)`;
   `onDisappear` calls `showMonth(nil)` — mirroring
   `NotchCalendarService.showMonth(_:)` exactly (`:48-52`). Grid
   prev/next/today navigation calls `showMonth` again with the newly
   selected month.
3. `CalendarService.refresh()` fetches the union of the always-on
   lookahead window and (when `visibleMonth` is non-nil) that month's
   range — bounding the fetch the way Itsycal's `EventCenter` decouples
   "what range needs fetching" from "what's currently displayed."
4. `CalendarReader.fetch(interval:)` builds an `EKEventStore` predicate for
   that range, filters out canceled and declined events (matching both
   `NotchCalendarService` and Itsycal's own filtering), maps each `EKEvent`
   to `CalendarEvent`, deriving `id` from `eventIdentifier + start` and
   `color` from the calendar's sRGB components (Components section fixes).
5. `CalendarService` applies the `calendarHiddenCalendarIDs` filter before
   publishing `@Published events: [CalendarEvent]` and an explicit
   `@Published state: .loading | .content | .permissionNeeded` (Design
   decision #7).
6. `CalendarMonthGridView` derives dot colors per visible day via
   `CalendarSupport.dotColors(on:events:)`.
7. `CalendarAgendaListView` derives day-grouped upcoming events via
   `CalendarSupport.upcomingGroups(events:from:)`; selecting a grid day
   scrolls/filters this list to that day (Design decision #5). Clicking an
   agenda event opens `NSWorkspace.shared.open` on its Calendar.app deep
   link (own implementation of the same `ical://ekevent/...` construction
   `NotchCalendarSupport.eventURL` already does — not shared code, per
   Design decision #1, but the same URL shape since it's Calendar.app's
   own scheme, not this codebase's invention).
8. `CalendarService` re-fetches on `EKEventStoreChanged` (an external
   calendar edit), on day rollover, and self-schedules to the next event
   boundary — the same reasons `NotchCalendarService` does, independently
   implemented.
9. `FeatureRuntime.bindings[.calendar]` calls `stop()` when
   `AppFeature.calendar` becomes inactive; `CalendarService` itself also
   calls `stop()` on sleep/lock, matching the Notch calendar's resource
   discipline.

## Error handling & edge cases

- `Permissions.shared.calendarAccess != .fullAccess` → `PanelCalendarView`
  renders `.permissionNeeded` (Design decision #7): a permission-request
  card, reusing the Notch calendar's existing copy/pattern (not its code,
  and not its exact strings, since the usage-string rewording above means
  this feature's copy can't say "notch") — request button, explanation,
  System Settings deep link.
- EventKit fetch failure (store unavailable, predicate error) → treat as
  an empty event list within `.content` state; the view shows no events
  but doesn't crash. No distinct "failed" UI — matches this codebase's
  existing convention for failed background reads (see the bookmarks
  spec's `CommandBarFileSearch` precedent) — but this is now explicitly
  distinguished from `.loading` and `.permissionNeeded`, not conflated
  with them.
- All-day events are included but flagged (`allDay`) so the agenda can
  render them without a time range.
- Recurring events are expanded by EventKit itself (predicate-based fetch
  already returns individual occurrences); each occurrence gets its own
  `id` (occurrence-start-qualified, per the Components fix), so the
  agenda's per-day grouping and any future dedup logic treat them as
  distinct events, not collapsing to one. `recurring` is carried through
  for Phase 2's benefit — worth flagging now that Phase 2's own
  link-detection cache will need the same occurrence-qualified key if it
  wants to avoid re-detecting a recurring meeting's link on every
  occurrence, not `eventIdentifier` alone.
- A calendar deleted/removed mid-session (its `calendarIdentifier` still
  present in `calendarHiddenCalendarIDs`) is simply inert — no cleanup
  pass needed, matching how other identifier-set preferences in this
  codebase (e.g. `windowPreviewExcludedApps`) tolerate stale entries.

## Testing

Pure `CalendarSupport` functions get real tests, injected with synthetic
`CalendarEvent` fixtures — no live EventKit access needed:

- Month-grid day math (correct days shown for a given month, including
  leading/trailing days from adjacent months).
- `dotColors(on:events:)`: nil for no events; correct set for 1-3+ distinct
  calendar colors on one day; **two events sharing one calendar's color
  produce a single dot, not two** (the concrete case the `CalendarColor`
  value-type fix in Components exists to make testable — `NSColor`
  equality would have made this assertion unreliable).
- `upcomingGroups(events:from:)`: correct day-grouping and ordering,
  all-day events included, canceled/declined events already filtered
  upstream so not re-tested here.
- A recurring fixture: two `CalendarEvent`s built from the same
  `eventIdentifier` at different `start` dates must produce two distinct
  `id`s and both must survive `upcomingGroups`' grouping without
  collapsing to one.

The target is a new `Tests/CalendarFeatureTests.swift`, registered as a
new suite entry in `MetricsTests.swift`'s `groups` array (`:12`) — this
repo's test file was a single `MARK`-sectioned file as recently as the
bookmarks spec, but the 2026-09-21 sync's
`refactor(tests): split independent feature suites` change split it into
per-feature files (`Tests/ClipboardFeatureTests.swift`,
`Tests/CommandBarFeatureTests.swift`, etc.); this feature follows that
current convention.

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
- **System-facing usage string, not just markdown docs.** As noted under
  "Why a new, independent module," `Resources/Info.plist`'s
  `NSCalendarsFullAccessUsageDescription` (and all 13 localized
  `InfoPlist.strings` copies) currently says "in the notch" — this is what
  macOS itself shows in the permission dialog, so it has to be reworded
  for this feature, in every language, not just noted as a doc to update.
- **Docs drift.** `docs/PERMISSIONS.md`'s "Calendars" row (`:14, 86-88`)
  currently reads "Upcoming appointments in the notch" — gains a second
  consumer (this panel tile). `docs/PRIVACY.md`'s "Optional notch
  features" section (`:30-32`) describes calendar access as notch-specific
  ("Calendar access is requested only from the permission button. The
  notch reads upcoming events...") — needs a parallel paragraph, or a
  rewording that isn't notch-scoped, once this feature also reads calendar
  data outside the notch. Given `notes` is deferred to Phase 2 (Design
  decision #4), `PRIVACY.md` doesn't yet need to disclose reading it —
  Phase 2's spec picks that up when the field is actually added.
- **Settings page shape.** `CalendarSettings.swift` follows
  `NotchSettings.swift`'s established shape: `@AppStorage` per toggle,
  `@ObservedObject` on the new `CalendarService`, one section for
  visibility toggles plus a per-calendar checklist section.

## Open items for the implementation plan

- Agenda lookahead window (30 days suggested above) and month-grid fetch
  range are implementation-plan-level tuning, not fixed by this spec.
- `SettingsPage.calendar` (`FeatureVisibilitySupport.swift:9-13`) is a flat
  case, confirmed above — no "Panel" grouping exists to nest under, so
  `CalendarSettings.swift` is a peer of `NotchSettings.swift`, not nested
  inside it.
- PR/commit split: (1) service + data model + `FeatureRuntime` binding +
  tests, (2) grid view, (3) agenda view + day-selection + open-in-Calendar
  wiring, (4) settings page + registration + docs. Unlike a typical
  additive PR, PR 1 here can't ship alone without either dead code or a
  minimal tile — fold at least a bare `PanelCalendarView` stub into PR 1
  so the `FeatureRuntime` binding has something to gate, or accept PR 1
  and PR 2 landing together.
