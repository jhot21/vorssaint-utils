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
  `~/Library/Safari/Bookmarks.plist` is TCC-protected. `Core/Permissions.swift`
  already has `probeFullDiskAccess()`, `requestFullDiskAccess()`, and
  `openFullDiskAccessSettings()`, used today by the uninstaller's deeper
  scan, and `UI/SharedUI.swift` already has the prompt UI for it. Safari
  support is a new *consumer* of an existing permission path, not a new
  permission subsystem.
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
- No favicon persisted to disk; icons are decoded from each browser's own
  database and cached in memory only.
- No multi-profile *merge*; one profile per browser (see Design decisions).

## Design decisions

These were the open questions worked through in brainstorming, with the
chosen answer and why:

1. **Profiles: auto-pick the browser's own default/last-used profile, with
   a per-browser picker in Settings for anyone with more than one.**
   Matches Raycast's own default behavior (Chrome's `Local State` records
   `last_used`; Firefox's `profiles.ini` records a `Default` flag). Not a
   "merge all profiles" mode — that would surface profiles a person doesn't
   think of as "mine" by default.
2. **Read strategy: cache in memory, invalidate on file mtime change**, not
   a fresh read per keystroke. Bookmarks change rarely; re-parsing a
   JSON/plist/SQLite file on every keystroke would be wasted work. Mirrors
   Raycast's own path+size+mtime signature check.
3. **Icons: per-site favicon**, decoded lazily per visible row from each
   browser's own favicon database (Chrome's `Favicons`, Firefox's
   `favicons.sqlite`, Safari's `WebpageIcons.db`), cached in an
   `NSCache<NSString, NSImage>` sized like `ClipboardImageStore.thumbnails`.
   No new on-disk cache — the icon already lives in the browser's database,
   so nothing is copied into a second store.
4. **Open behavior: a bookmark opens in the browser it came from**, via
   `NSWorkspace.open(url, withApplicationAt:)` targeting that browser's
   bundle, not the system default browser. A bookmark's login state,
   extensions and cookies belong to the browser it was saved in.
5. **Settings: one toggle per browser**, not one combined toggle, matching
   how other Command Bar sources are already split out in
   `CommandBarSettings.swift`. Someone who only uses Chrome can leave
   Firefox and Safari off entirely, skipping those read paths completely.

## Components

New files under `Sources/Vorssaint/Services/CommandBar/`:

- `CommandBarBookmarksChrome.swift` / `CommandBarBookmarksChromeSupport.swift`
  — reads `Local State` for the last-used profile, then that profile's
  `Bookmarks` JSON, walking `roots.bookmark_bar` / `roots.other`.
- `CommandBarBookmarksFirefox.swift` / `CommandBarBookmarksFirefoxSupport.swift`
  — reads `profiles.ini` for the default profile, opens `places.sqlite` via
  SQLite's C API with `?immutable=1` (skips locking; the tradeoff is
  possibly missing a bookmark added seconds ago before Firefox checkpoints
  its WAL), queries `moz_bookmarks` joined to `moz_places`.
- `CommandBarBookmarksSafari.swift` / `CommandBarBookmarksSafariSupport.swift`
  — reads `~/Library/Safari/Bookmarks.plist` (nested plist: Bookmarks Bar,
  Bookmarks Menu, Reading List), gated on `Permissions.probeFullDiskAccess()`.
  No profile concept.

Shared, since Chrome/Firefox/Safari all need the same shape of logic (the
"abstract only when two+ settled cases share one contract" rule applies
here — three real call sites, one behavioral contract each):

- A pure folder-hierarchy-builder (walk a parent chain to a titled path),
  used by all three.
- A small SQLite-open helper (`?immutable=1`, read-only) shared by Firefox
  and Safari.

Each source class follows the existing `CommandBarFileSearch` shape: a
`reset()`, an in-memory cache, pure logic split into `*Support.swift` for
the test harness, the browser-specific file/DB access kept outside it (like
`CommandBarFileSearch.search()` itself is today).

Catalog and view changes:

- `CommandBarCatalog.swift` appends bookmark rows into the existing unified
  list, the same way file search and link rows are merged today.
- A new `CommandBarCatalog.Icon` case (e.g. `.bookmarkFavicon(key: String)`),
  resolved in `CommandBarView.swift`'s `iconContent(_:)` through the new
  favicon `NSCache`, falling back to the existing browser-symbol icon when a
  row has no favicon or decoding fails.
- `CommandBarSettings.swift` gets three toggle rows (Chrome / Firefox /
  Safari), each showing the detected profile name where relevant. Safari's
  row shows the existing FDA-grant affordance from `SharedUI.swift` when
  ungranted. A toggle for a browser that isn't installed
  (`NSWorkspace.urlForApplication(withBundleIdentifier:)` returns nil) stays
  visible but captioned as inert, rather than hidden — this state is
  temporary (reinstalling the browser makes it work again), unlike the
  existing hub-feature row-hiding logic which handles a permanent removal.

## Data flow

1. Command Bar preferences reload (a toggle flips) or the bar opens and a
   watched file's mtime has changed → re-parse that browser's bookmarks and
   rebuild an in-memory `[title, url, folder, browserBundleID]` list.
2. Every keystroke hands the cached lists to the same fuzzy matcher every
   other catalog source uses (`CommandBarSearch`) — no extra I/O per
   keystroke.
3. Selecting a row and pressing Return resolves that row's browser bundle
   ID to an installed app URL and opens the bookmark's URL there.
4. A visible row's favicon is looked up lazily (not all bookmarks upfront)
   from the owning browser's favicon database and cached in memory.

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

Pure functions get real tests in `Tests/`, following the
`CommandBarFileSearchSupport` split:

- The shared folder-hierarchy builder.
- The mtime/signature staleness check.
- The `http(s)://`-only URL filter (including a `javascript:` bookmarklet
  input, which must be rejected).

Outside the pure-function harness (matching `CommandBarFileSearch.search()`
today): the JSON/plist/SQLite parsing itself, and the favicon decode calls.
These are verified by `./build.sh` and `./build.sh --test` (both — this
touches `Sources/Vorssaint/UI/`, which `--test`'s hand-written file list
mostly excludes), plus manual use against real Chrome, Firefox and Safari
profiles: a bookmark opens in the browser it came from, a bookmarklet does
not appear as a row, and the Safari toggle behaves correctly with Full Disk
Access both denied and granted.

## Open items for the implementation plan

- Exact SQL for Firefox's `moz_bookmarks`/`moz_places` join and Safari's
  `WebpageIcons.db` schema should be confirmed against a real profile
  during implementation, not assumed from documentation.
- Whether to cap the total rows cached per browser (file search caps at
  `CommandBarFileSearchSupport.candidateLimit`); likely yes, for the same
  reason, but the right number depends on how large a real bookmark set
  gets in practice.
