# Browser bookmarks in the Command Bar

Status: draft, awaiting implementation plan.

## Problem

Vorssaint's Command Bar unifies apps, files, links, snippets and system
actions into one fuzzy-searched list, but has no way to reach a bookmark
saved in a browser. Raycast's `browser-bookmarks` extension is the reference
point the person asking for this uses today.

## Scope

Three browsers: **Chrome, Firefox, Safari**. No other Chromium forks (Edge,
Brave, Arc, …) and no bookmark *editing* — read-only search and open, same
as every other Command Bar source.

Prior art check: searched open PRs/issues on `vorssaintapp/vorssaint-utils`
(including the enhancement and command-bar-coverage summary issues, #838 and
#977) for "bookmark" — no open, closed, or ruled-out proposal exists. This is
unclaimed territory, not a re-proposal.

## Why this fits the project

- **No sandbox, no new permission for two of three browsers.** Vorssaint is
  not sandboxed (see `Resources/Vorssaint.entitlements`). Chrome's and
  Firefox's bookmark stores live under `~/Library/Application Support/`,
  which is not TCC-protected, so those two sources need nothing beyond
  ordinary file reads.
- **Safari needs Full Disk Access, but that machinery already exists.**
  `~/Library/Safari/Bookmarks.plist` is TCC-protected, and `Library/Safari`
  is already one of `Permissions.fdaGatedDirectories`
  (`Core/Permissions.swift:207-214`). The check itself
  (`probeFullDiskAccess()`) is `private static`; the usable surface is the
  published `Permissions.shared.fullDiskAccess`, which only refreshes at
  launch and on `didBecomeActiveNotification` (`Permissions.swift:57-60`) —
  it is never polled mid-session, deliberately (granting FDA takes effect
  only after a relaunch). `UI/SharedUI.swift`'s `FullDiskAccessNote`
  already carries a Relaunch button for exactly this reason and is reused
  as-is, with its reason string changed from the uninstaller-specific
  default (`Core/Localization.swift:2368`) to a bookmarks-specific one.
  Safari support is a new *consumer* of this existing permission path, not
  a new permission subsystem.
- **No new runtime dependency.** SQLite access goes through the system
  `libsqlite3`, already linkable with a plain `swiftc`/SwiftPM build — no
  Homebrew tool, no package added to `Package.swift`.
- **Fits the existing catalog shape exactly.** The Command Bar has no
  prefix/trigger scheme; every source contributes rows to one fuzzy-matched
  list (`CommandBarCatalog.swift`). Bookmarks are just more rows.

## Non-goals

- Bookmarklets (`javascript:` URLs) are not offered as rows — see Edge
  cases.
- No cross-browser de-duplication.
- No per-site favicons in v1 (see Design decisions #3) — every bookmark row
  shows its browser's icon. Revisit as a fast-follow if it's worth the
  reverse-engineering cost.
- No multi-profile *merge*; one profile per browser (see Design decisions).
- No custom ranking/frecency system — bookmark rows opt into the existing
  `CommandBarEntry.countsUsage` usage-boost like every other source.

## Design decisions

These were the open questions worked through in brainstorming, with the
chosen answer and why:

1. **Profiles: auto-pick the browser's own default/last-used profile, with
   a per-browser picker in Settings for anyone with more than one.**
   Matches Raycast's own default behavior (Chrome's `Local State` records
   `profile.last_used`; Firefox's `profiles.ini` records the default under
   its `Install*` section, not a per-profile flag — see Components). Not a
   "merge all profiles" mode — that would surface profiles a person doesn't
   think of as "mine" by default.
2. **Read strategy: cache in memory, invalidate on file mtime change**, not
   a fresh read per keystroke. Bookmarks change rarely; re-parsing a
   JSON/plist/SQLite file on every keystroke would be wasted work. Mirrors
   Raycast's own path+size+mtime signature check.
3. **Icons: browser-symbol only in v1, not per-site favicons.** Reversed
   from the original brainstorm after checking Raycast's own source: it
   does *not* read local favicon databases, it fetches favicons over the
   network (`getFavicon` / Google's favicon service) with a globe fallback
   — so there is no working reference for the "read the browser's local
   favicon DB" approach, and Chrome's `Favicons` schema alone has changed
   shape across releases. Three separate, undocumented, version-fragile
   schemas (Chrome, Firefox, Safari) is real reverse-engineering risk with
   no upstream implementation to build from. The network alternative is
   worse for this app specifically: it would add a new entry to
   `docs/PRIVACY.md`'s network-connections list, which today reads "that is
   the entire list" for a small, enumerated set of network calls — a
   meaningfully bigger commitment for a local-first app than reading a
   local file. Every bookmark row shows its owning browser's icon instead;
   per-site favicons are a possible fast-follow, not part of this design.
4. **Open behavior: a bookmark opens in the browser it came from**, via
   `NSWorkspace.open(url, withApplicationAt:)` targeting that browser's
   bundle, not the system default browser. A bookmark's login state,
   extensions and cookies belong to the browser it was saved in. This is
   fixed behavior, not a per-user preference (unlike Raycast, which exposes
   it as a toggle) — nobody has asked for a choice here, and adding one
   would be a setting with no demonstrated demand. If the origin browser is
   no longer installed at the moment Return is pressed (bundle lookup via
   `NSWorkspace.urlForApplication(withBundleIdentifier:)` returns nil), the
   bookmark falls back to opening in the system default browser rather than
   failing silently.
5. **Settings: one toggle per browser**, not one combined toggle, matching
   how other Command Bar sources are already split out in
   `CommandBarSettings.swift`. Someone who only uses Chrome can leave
   Firefox and Safari off entirely, skipping those read paths completely.

## Components

New files under `Sources/Vorssaint/Services/CommandBar/`:

- `CommandBarBookmarksChrome.swift` / `CommandBarBookmarksChromeSupport.swift`
  — reads `Local State`'s `profile.info_cache` for the last-used profile
  (`profile.last_used`), validating that the profile actually has a
  bookmarks file; falls back to scanning the Chrome directory for any
  profile folder containing one (preferring `Default`) if `Local State` is
  missing or fails to parse — Chrome's own resilience path, not just the
  happy one. Within a profile, prefers `AccountBookmarks` (written when
  Google-account sync is on) over `Bookmarks` when the former exists and is
  non-empty, falling back to `Bookmarks` otherwise; both files are pure
  JSON, no SQLite. Walks `roots.bookmark_bar` / `roots.other`.
- `CommandBarBookmarksFirefox.swift` / `CommandBarBookmarksFirefoxSupport.swift`
  — reads `profiles.ini`'s `Install*` section for its `Default` key (the
  actual mechanism; there is no per-profile `Default=1` flag), filtered to
  profiles that actually contain `places.sqlite`, falling back to the first
  matching profile if no `Install*` section exists. Opens `places.sqlite`
  via SQLite's C API with `?immutable=1` (skips locking; the tradeoff is
  possibly missing a bookmark added seconds ago before Firefox checkpoints
  its WAL). Query shape starts from what Raycast's extension already ships
  and has clearly been exercised against real profiles: bookmarks are
  `moz_bookmarks.type = 1` joined to `moz_places` on `fk`, filtered to
  `title IS NOT NULL` and a non-null `moz_places.url`; folders are
  `moz_bookmarks.type = 2` with `fk IS NULL`. Root folder ids (`menu`,
  `toolbar`, `unfiled`, `mobile`, `tags`) map to friendly names the same
  way.
- `CommandBarBookmarksSafari.swift` / `CommandBarBookmarksSafariSupport.swift`
  — reads `~/Library/Safari/Bookmarks.plist`, gated on
  `Permissions.shared.fullDiskAccess`. Root keys are `BookmarksBar`,
  `BookmarksMenu` and `com.apple.ReadingList`; a leaf's title comes from
  `URIDictionary.title`, falling back to the URL itself when that key is
  missing or empty rather than showing a blank row. No profile concept.
  Large bookmark sets are a real, evidenced concern here — Raycast's own
  plist parser needed its object-count ceiling raised to 250,000 to avoid
  truncating heavy Safari libraries, which is also the concrete argument
  for capping rows per source (see Data flow).

Shared, since Chrome/Firefox/Safari are three real, already-identified call
sites for the same logic — satisfying `AI-CONTRIBUTIONS.md`'s bar of "at
least two settled cases share one reason to change and one behavioural
contract," not just "looks similar":

- A pure folder-hierarchy-builder: contract is "given a node and its parent
  chain, return a titled path"; the reason to change is a bug in that
  walk, which would be the same bug in all three today if it were three
  copies. Used by all three.
- The `?immutable=1` SQLite-open logic is **not** pulled into a shared
  helper in v1. With favicons deferred, Firefox's bookmark reader is the
  only SQLite consumer — Chrome and Safari are both plain
  JSON/plist. `AI-CONTRIBUTIONS.md`'s own rule is "at least two settled
  cases"; one real call site is a reason to keep the open-and-query logic
  inline in `CommandBarBookmarksFirefox.swift`, not a reason to build a
  general-purpose SQLite wrapper for a second consumer that doesn't exist
  yet. Revisit if per-site favicons come back and Safari or Chrome end up
  needing their own locked-DB read.

Each source class follows the existing `CommandBarFileSearch` shape: a
`reset()`, an in-memory cache, pure logic split into `*Support.swift` for
the test harness, the browser-specific file/DB access kept outside it (like
`CommandBarFileSearch.search()` itself is today).

Catalog and view changes:

- `CommandBarCatalog.swift` appends bookmark rows into the existing unified
  list, the same way file search and link rows are merged today. Each
  row's `keywords` (`CommandBarEntry.keywords`, a flat string like every
  other source's) is title + domain + folder path, so typing "github"
  matches a bookmark titled "PR review" whose URL is a GitHub link — the
  domain and folder are otherwise invisible to the fuzzy matcher.
- No new `CommandBarEntry.Icon` case is needed in v1, since icons are
  browser-symbols only (Design decision #3) — bookmark rows use the
  existing `.symbol(String)` case with a per-browser SF Symbol, distinct
  from `.links`' existing "bookmark" glyph (`CommandBarPreferences.swift:56`,
  titled "Your shortcuts") to avoid confusing the two sources.
- `CommandBarSettings.swift` gets three toggle rows (Chrome / Firefox /
  Safari), each showing the detected profile name where relevant. Safari's
  row shows the existing FDA-grant affordance from `SharedUI.swift` when
  `Permissions.shared.fullDiskAccess` is false. A toggle for a browser that
  isn't installed (`NSWorkspace.urlForApplication(withBundleIdentifier:)`
  returns nil) stays visible but captioned as inert, rather than hidden —
  this state is temporary (reinstalling the browser makes it work again),
  unlike the existing hub-feature row-hiding logic which handles a
  permanent removal.
- This adds a new `CommandBarSource` case (or three — one per browser;
  exact split is an implementation-plan decision), which touches every
  exhaustive switch over that enum: `symbolName`, `rankBias`,
  `acceptsAlias`, `acceptsPin`, `isHubOwned` in `CommandBarPreferences.swift`;
  `categoryTitle`/`categoryHasContent`/`categoryContent`/`browseGroup` in
  `CommandBarService.swift`; `title(for:)` in `CommandBarSettings.swift`;
  plus a `kindLimits` entry (`CommandBarService.swift:1129`) to cap rows
  per browser, and the persisted `commandBarDisabledSources` string. None
  of these are optional — the enum is exhaustive, so the compiler forces
  all of them; listing them here is so the implementation plan doesn't
  discover the blast radius mid-change.
- `FeatureCatalog.swift`'s `commandBar.permissions` (currently
  `[.accessibility]`, line 237) gains `.fullDiskAccess`, following the
  exact precedent of `.uninstaller` already listing `.fullDiskAccess` for
  what is documented as an optional enhancement to that feature
  (`FeatureCatalog.swift:255`).

## Data flow

There is no "preferences changed" event to hook in the Command Bar today —
`disabledSourcesRaw` is read fresh from `UserDefaults` on every ranking
pass (`CommandBarService.swift:407, 1020, 1294`), pull-based rather than
push-based. So the re-parse trigger is not an event handler; each bookmark
source instead hooks the same per-open lifecycle `CommandBarFileSearch`
already uses (its `reset()`, called when the bar opens/closes — see
`CommandBarService.swift:275, 339`):

1. When the bar opens, each enabled bookmark source checks a
   path+size+mtime signature of the files it depends on (Chrome:
   `Local State` + `Bookmarks`/`AccountBookmarks`; Firefox: `places.sqlite`;
   Safari: `Bookmarks.plist`) — the same signature shape Raycast itself
   computes before deciding whether to re-read. Only a changed signature triggers a
   re-parse; an unchanged one reuses the existing in-memory list. This is a
   `stat()`-cost check on every open, not a parse-cost one.
2. Firefox's `places.sqlite` doubles as the history store, so its mtime
   changes on ordinary browsing, not just on bookmark edits — the
   signature check will report "changed" far more often for Firefox than
   for Chrome or Safari. The check itself stays cheap (a `stat()`), but the
   *re-parse* it triggers is real work, so the Firefox source additionally
   enforces a minimum re-check interval (skip re-parsing if the last one
   was under some small threshold ago, e.g. a few seconds) to bound the
   worst case of opening the bar repeatedly during active browsing, without
   adding staleness beyond what a search feature already tolerates.
3. Rows are capped per source (a `kindLimits` entry, matching the existing
   pattern) rather than left unbounded — Safari's own extension needed its
   plist parser's object-count ceiling raised to handle large libraries,
   which is concrete evidence that "assume it's small" is wrong for real
   bookmark collections.
4. Every keystroke hands the cached lists to the same fuzzy matcher every
   other catalog source uses (`CommandBarSearch`) — no extra I/O per
   keystroke, and no per-keystroke re-parse.
5. Selecting a row and pressing Return resolves that row's browser bundle
   ID to an installed app URL and opens the bookmark's URL there, falling
   back to the system default browser if that bundle can no longer be
   resolved (Design decision #4).
6. Bookmark rows participate in the existing `CommandBarEntry.countsUsage`
   ranking boost like any other source — no separate frecency system.

## Error handling & edge cases

- Missing file, corrupt JSON/plist, unreadable SQLite, or a permission
  revoked mid-session → zero rows from that source, silently. No error UI;
  matches the guard-and-return style `CommandBarFileSearch` already uses.
  Whether a browser has no bookmarks or failed to parse looks the same to
  the user — there's nothing actionable to tell them either way.
- A refresh that fails mid-parse keeps the last good cache rather than
  blanking results out from under someone mid-keystroke.
- `javascript:` bookmarklets are filtered out at parse time. They are not
  navigable URLs, and handing one straight from an external file to
  `NSWorkspace.open` crosses the "external input is untrusted by default"
  line in `docs/AI-CONTRIBUTIONS.md` for no benefit. Only `http(s)://` (and,
  for Safari, `file://`) entries are offered.
- No cross-browser de-duplication — the same site bookmarked in two
  browsers shows as two rows, each tagged with its own browser icon.
  Matches Raycast's own behavior.

## Testing

Pure functions get real tests, following the `CommandBarFileSearchSupport`
precedent exactly — including *where* they live: that precedent is a new
`MARK` section inside `Tests/MetricsTests.swift`
(`Tests/MetricsTests.swift:16117-16195`), not a separate test file, since
the repo's test target is a hand-written file list (see Repo conventions
below) rather than auto-discovered:

- The shared folder-hierarchy builder.
- The mtime/signature staleness check, including the Firefox
  minimum-re-check-interval behavior.
- The `http(s)://`-only URL filter (including a `javascript:` bookmarklet
  input, which must be rejected).

Outside the pure-function harness (matching `CommandBarFileSearch.search()`
today): the JSON/plist/SQLite parsing itself. Verified by `./build.sh` and
`./build.sh --test` (both — this touches `Sources/Vorssaint/UI/`, which
`--test`'s hand-written file list mostly excludes), plus manual use against
real Chrome, Firefox and Safari profiles: a bookmark opens in the browser
it came from, a bookmarklet does not appear as a row, and the Safari toggle
behaves correctly with Full Disk Access both denied and granted (including
across a relaunch, since a grant doesn't take effect until then).

## Repo conventions this touches

Called out separately because each is easy to discover only after most of
the code is written, which is exactly what `AI-CONTRIBUTIONS.md` asks to
avoid:

- **Localization is compiler-enforced, not optional.** Every new
  user-facing string — three toggle titles, a profile-name caption, the
  inert-browser caption, and a bookmarks-specific reason string for
  `FullDiskAccessNote` — is a new field on `CommandBarFeatureStrings`
  (`Core/CommandBarStrings.swift`), which means a value in all 13 shipped
  languages (`Core/Localization.swift` + `Core/Localizations/`) before it
  compiles. `Tests/MetricsTests.swift:17421` pins
  `commandBarValues.count == 151`; that number moves by exactly the count
  of new fields added, and the test is the reviewer that catches a skipped
  language.
- **Docs drift is treated as a defect, not a style note**
  (`AI-CONTRIBUTIONS.md:180-183`). `docs/PERMISSIONS.md`'s Full Disk Access
  entry (currently "what uses it: the uninstaller," lines 15 and 101-103)
  gains a second consumer. `docs/PRIVACY.md`'s "What it reads" section
  gains a paragraph: three more local files read, on-device, never
  transmitted — consistent with the rest of that section, and worth being
  explicit that no favicon network fetch happens (see Design decision #3)
  so the doc doesn't need revisiting later for that reason too.
- **First SQLite use in this codebase.** `?immutable=1` requires
  `SQLITE_OPEN_URI` via `sqlite3_open_v2`, not the plain `sqlite3_open`.
  System `libsqlite3` autolinks under a plain `swiftc`/SwiftPM build with
  no `Package.swift` change — worth confirming once against both CI
  toolchains (`.github/workflows/ci.yml`: Swift 6.0.3/SDK 15.2 and macOS
  26) early in implementation rather than assuming it, since this is the
  one place the design introduces a new C API surface.
- **PR size.** The merged median here is ~110 lines
  (`AI-CONTRIBUTIONS.md:294-300`); three browsers, three settings rows, the
  shared hierarchy helper, and 13-language strings will clear that
  comfortably as one PR. Proposed split, each standing on its own: (1)
  Chrome plus the shared folder-hierarchy helper and the catalog/settings
  scaffolding every source needs, (2) Firefox, (3) Safari plus its Full
  Disk Access wiring. Chrome first because it needs no new permission and
  exercises the scaffolding every other browser reuses.

## Open items for the implementation plan

- Firefox's `moz_bookmarks`/`moz_places` join (adapted from Raycast's
  implementation, see Components) should still be run against a real,
  populated profile during implementation — a query that works on a small
  test profile can miss an edge case Raycast's own userbase already
  surfaced for them.
- **Row cap: yes, cap it**, resolved as part of this design rather than
  left open — Safari's own extension needed its plist parser's
  object-count ceiling raised to 250,000 for real-world libraries, which is
  concrete evidence "unbounded" is the wrong default. The exact number
  (matching `CommandBarFileSearchSupport.candidateLimit`'s role) is an
  implementation-plan detail.
- Chrome's `Bookmarks.bak` (its own atomic-write fallback file) is worth
  using as a last-resort fallback if `Bookmarks` fails to parse, rather
  than only `AccountBookmarks` → `Bookmarks` → nothing.
- Because the Chromium JSON reader is shared logic parameterized by a
  profile-directory path (matching Raycast's own `useChromiumBookmarks`
  shape), adding Brave, Edge or another Chromium fork later is a
  near-zero-cost new call site, not a redesign — worth noting so a future
  "add Brave" request is scoped correctly as small.
