# Browser Bookmarks in the Command Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Search and open Chrome, Firefox and Safari bookmarks from Vorssaint's Command Bar, as three independent, individually toggleable sources.

**Architecture:** Three new stateful reader classes (`CommandBarBookmarksChrome`, `CommandBarBookmarksFirefox`, `CommandBarBookmarksSafari`), each owned by `CommandBarService` and refreshed via a cache+mtime-signature check on bar open (mirroring the existing `reloadFileSearchCaches()` pattern), feeding parsed bookmark rows into `CommandBarCatalog.build(...)` alongside the existing static sources (links, snippets, settings pages). Pure parsing/validation logic lives in `*Support.swift` files with real unit tests; file/database I/O stays outside the pure-function harness, verified by build + manual use.

**Tech Stack:** Swift, Foundation (`JSONDecoder`, `PropertyListDecoder`), SQLite3 C API (system `libsqlite3`, no new dependency), SwiftUI (Settings toggles), XCTest-style `expect(...)` assertions in `Tests/MetricsTests.swift`.

**Spec:** `docs/superpowers/specs/2026-08-26-browser-bookmarks-design.md`

## Global Constraints

- Three browsers only: Chrome, Firefox, Safari. No other Chromium forks.
- Read-only. No bookmark editing.
- No per-site favicons in v1 — every bookmark row shows its owning browser's actual app icon via the existing `CommandBarEntry.Icon.appIcon(path:)` case (see Task 5's note — this refines the spec's "SF Symbol" phrasing to the more accurate, more reusable choice; it does not reopen the "no per-site favicon" decision).
- No cross-browser de-duplication, no custom ranking — bookmark rows use `countsUsage: true` like any default row.
- `javascript:` and other non-navigable schemes are filtered out; only `http`/`https` (and, for Safari, `file`) URLs are offered.
- One `CommandBarSource` toggle per browser, each independently switchable in Settings.
- Chrome/Firefox need no new permission. Safari is gated on `Permissions.shared.fullDiskAccess` (already exists, already covers `Library/Safari`) — no new TCC category, no sandbox change.
- No new `Package.swift` dependency. SQLite access goes through system `libsqlite3` via `sqlite3_open_v2`/`SQLITE_OPEN_URI`.
- Every new user-facing string is a new field on `CommandBarFeatureStrings` (`Sources/Vorssaint/Core/CommandBarStrings.swift`) with a value for all 13 languages (`enUS, ptBR, tr, ru, es, de, fr, it, ja, ko, zhHans, zhTW, zhHK`) — the compiler enforces this, and `Tests/MetricsTests.swift`'s `commandBarValues.count == 151` pinned assertion must be bumped by exactly the number of new fields each task adds.
- New `*Support.swift` files must be added to `build.sh`'s hand-written compile list (`build.sh` lines ~277-287) or `./build.sh --test` silently skips them.
- New pure-function tests are added as a new `MARK` section inside `Tests/MetricsTests.swift`, not a new file (matching the `CommandBarFileSearchSupport` precedent at `Tests/MetricsTests.swift:16117`).
- Every task's final step is `./build.sh` **and** `./build.sh --test`, both — this work touches `Sources/Vorssaint/UI/`, which `--test`'s file list mostly excludes.

---

## Task 1: Chrome Command Bar source scaffolding

**Files:**
- Modify: `Sources/Vorssaint/Services/CommandBar/CommandBarCatalog.swift:8-84` (`CommandBarSource` enum)
- Modify: `Sources/Vorssaint/Services/CommandBar/CommandBarPreferences.swift` (`rankBias`, `acceptsAlias`, `acceptsPin`, `isHubOwned` switches)
- Modify: `Sources/Vorssaint/Services/CommandBar/CommandBarService.swift` (`categoryHasContent`, `categoryContent`, `categoryTitle`, `browseGroup`, `kindLimits`)
- Modify: `Sources/Vorssaint/UI/Settings/CommandBarSettings.swift` (`title(for:)`)
- Modify: `Sources/Vorssaint/Core/CommandBarStrings.swift` (new fields + all 13 language blocks)
- Modify: `Tests/MetricsTests.swift:17421` (pinned count)

**Interfaces:**
- Produces: `CommandBarSource.chromeBookmarks` case, usable by every later task in this group. `idPrefix` is `"chromebookmark."` — every Chrome bookmark row's `CommandBarEntry.id` must start with this exact string for the source-lookup switches to work.
- Produces: `CommandBarFeatureStrings.sourceChromeBookmarks`, `.kindBookmark`, `.bookmarksProfileFormat`, `.chromeBookmarksNotInstalled` — `kindBookmark` and `bookmarksProfileFormat` are shared by the Firefox and Safari groups later; do not redefine them there. `chromeBookmarksNotInstalled` is Chrome-only; Firefox and Safari define their own equivalents in Tasks 7 and 11.

This task is pure wiring with no new logic of its own, so its "red" step is the compiler: add the enum case alone, watch every exhaustive switch fail to build, then complete each one.

- [ ] **Step 1: Add the enum case and watch it fail to compile**

In `Sources/Vorssaint/Services/CommandBar/CommandBarCatalog.swift`, inside `enum CommandBarSource`, add one case after `.files`:

```swift
    case files
    /// Bookmarks read from Chrome's own profile files.
    case chromeBookmarks
    case killProcess
```

And extend the two switches already in that file:

```swift
    var symbolName: String {
        switch self {
        // ... existing cases unchanged ...
        case .files: return "doc.text.magnifyingglass"
        case .chromeBookmarks: return "globe"
        case .killProcess: return "xmark.octagon"
        }
    }

    var idPrefix: String? {
        switch self {
        // ... existing cases unchanged ...
        case .files: return "file."
        case .chromeBookmarks: return "chromebookmark."
        case .killProcess: return "kill."
        }
    }
```

Run: `swift build`
Expected: FAIL — several "switch must be exhaustive" errors in `CommandBarPreferences.swift`, `CommandBarService.swift` and `CommandBarSettings.swift`.

- [ ] **Step 2: Fix each exhaustive switch**

In `Sources/Vorssaint/Services/CommandBar/CommandBarPreferences.swift`:

```swift
    static func rankBias(for source: CommandBarSource) -> Int {
        switch source {
        case .menus: return -80
        case .files: return -40
        case .actions, .apps, .windows, .quitApps, .settingsPages, .macSettings, .snippets,
             .clipboard, .emoji, .folders, .answers, .calculator, .selection, .links,
             .chromeBookmarks, .killProcess:
            return 0
        }
    }
```

```swift
    static func acceptsAlias(rowID: String) -> Bool {
        switch source(ofRowID: rowID) {
        case .menus, .windows, .clipboard, .selection, .files, .killProcess: return false
        case .actions, .apps, .quitApps, .settingsPages, .macSettings, .snippets, .emoji,
             .folders, .answers, .calculator, .links, .chromeBookmarks:
            return true
        }
    }
```

```swift
    static func acceptsPin(rowID: String) -> Bool {
        switch source(ofRowID: rowID) {
        case .menus, .quitApps, .clipboard, .emoji, .selection, .files, .killProcess: return false
        case .actions, .apps, .windows, .settingsPages, .macSettings, .snippets, .folders,
             .links, .chromeBookmarks, .answers, .calculator:
            return true
        }
    }
```

```swift
    private static func isHubOwned(_ rowID: String) -> Bool {
        switch source(ofRowID: rowID) {
        case .actions, .settingsPages, .snippets: return true
        case .apps, .menus, .windows, .quitApps, .macSettings, .clipboard, .emoji,
             .folders, .answers, .calculator, .selection, .links, .files, .chromeBookmarks,
             .killProcess:
            return false
        }
    }
```

In `Sources/Vorssaint/Services/CommandBar/CommandBarService.swift`, extend the four switches:

```swift
    private func categoryHasContent(_ source: CommandBarSource) -> Bool {
        let bar = FeatureStrings.commandBar(L10n.shared.language)
        switch source {
        case .apps, .macSettings:
            return true
        case .windows:
            return (AppFeature.switcher.isAvailable || AppFeature.windowLayout.isAvailable)
                && Permissions.shared.accessibility
        case .menus:
            return Permissions.shared.accessibility
                && NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                    != Bundle.main.bundleIdentifier
        case .clipboard:
            return !categoryContent(source, bar: bar, limit: 1).isEmpty
        case .emoji:
            let hidden = hiddenKeys
            return emojiEntries.contains { !hidden.contains($0.stableKey) }
        case .actions, .settingsPages, .snippets, .folders, .links, .chromeBookmarks:
            let hidden = hiddenKeys
            return catalog.contains {
                CommandBarPreferences.source(ofRowID: $0.id) == source
                    && !hidden.contains($0.stableKey)
            }
        case .killProcess:
            return AppFeature.killProcess.isAvailable
        case .quitApps, .answers, .calculator, .selection, .files:
            return false
        }
    }
```

```swift
    private func categoryContent(_ source: CommandBarSource,
                                 bar: CommandBarFeatureStrings,
                                 limit: Int = 60) -> [CommandBarEntry] {
        let hidden = hiddenKeys
        let rows: [CommandBarEntry]
        switch source {
        case .actions:
            rows = catalog.filter { CommandBarPreferences.source(ofRowID: $0.id) == .actions }
        case .apps: rows = appEntries
        case .macSettings: rows = macSettingsEntries
        case .windows: rows = windowEntries
        case .menus: rows = menuEntries
        case .emoji: rows = emojiEntries
        case .settingsPages, .snippets, .folders, .links, .chromeBookmarks:
            rows = catalog.filter { CommandBarPreferences.source(ofRowID: $0.id) == source }
        case .clipboard:
            rows = CommandBarCatalog.clipboardBrowseEntries(limit: limit, bar: bar) { [weak self] entry in
                self?.paste(entry)
            }
        case .killProcess: rows = killProcessEntries
        case .quitApps, .answers, .calculator, .selection, .files:
            rows = []
        }
        return rows.filter { !hidden.contains($0.stableKey) }
    }
```

```swift
    func categoryTitle(_ source: CommandBarSource) -> String {
        let bar = FeatureStrings.commandBar(L10n.shared.language)
        switch source {
        case .actions: return bar.sourceActions
        case .apps: return bar.sourceApps
        case .menus: return bar.kindMenu
        case .windows: return bar.sourceWindows
        case .quitApps: return bar.sourceQuitApps
        case .settingsPages: return bar.sourceSettingsPages
        case .macSettings: return bar.sourceMacSettings
        case .snippets: return bar.sourceSnippets
        case .clipboard: return bar.sourceClipboard
        case .emoji: return bar.sourceEmoji
        case .folders: return bar.sourceFolders
        case .answers: return bar.sourceAnswers
        case .calculator: return bar.sourceCalculator
        case .selection: return bar.sourceSelection
        case .files: return bar.sourceFiles
        case .links: return bar.linksTitle
        case .chromeBookmarks: return bar.sourceChromeBookmarks
        case .killProcess: return FeatureStrings.killProcess(L10n.shared.language).pageTitle
        }
    }
```

```swift
    private func browseGroup(for entry: CommandBarEntry,
                             bar: CommandBarFeatureStrings) -> String {
        switch CommandBarPreferences.source(ofRowID: entry.id) {
        case .answers: return bar.kindAnswer
        case .links: return bar.kindLink
        case .snippets: return bar.kindSnippet
        case .folders: return bar.kindFolder
        case .chromeBookmarks: return bar.kindBookmark
        case .actions, .apps, .menus, .windows, .quitApps, .settingsPages, .macSettings,
             .clipboard, .emoji, .calculator, .selection, .files, .killProcess:
            return entry.subtitle.isEmpty ? bar.everythingTitle : entry.subtitle
        }
    }

    private static let kindLimits: [(prefix: String, limit: Int)] = [
        ("app.", 5), ("window.", 4), ("quit.", 3), ("menu.", 5), ("emoji.", 6),
        ("settings.", 4), ("macsettings.", 4), ("clipboard.", 4), ("snippet.", 4),
        ("file.", 4),
        ("toggle.", 5),
        ("chromebookmark.", 5),
    ]
```

In `Sources/Vorssaint/UI/Settings/CommandBarSettings.swift`:

```swift
    private func title(for source: CommandBarSource) -> String {
        switch source {
        case .actions: return text.sourceActions
        case .apps: return text.sourceApps
        case .menus: return text.sourceMenus
        case .windows: return text.sourceWindows
        case .quitApps: return text.sourceQuitApps
        case .settingsPages: return text.sourceSettingsPages
        case .macSettings: return text.sourceMacSettings
        case .snippets: return text.sourceSnippets
        case .clipboard: return text.sourceClipboard
        case .emoji: return text.sourceEmoji
        case .folders: return text.sourceFolders
        case .answers: return text.sourceAnswers
        case .calculator: return text.sourceCalculator
        case .selection: return text.sourceSelection
        case .links: return text.linksTitle
        case .files: return text.sourceFiles
        case .chromeBookmarks: return text.sourceChromeBookmarks
        case .killProcess: return FeatureStrings.killProcess(l10n.language).pageTitle
        }
    }
```

Run: `swift build`
Expected: still FAIL, now with "type CommandBarFeatureStrings has no member sourceChromeBookmarks" etc. — proceed to Step 3.

- [ ] **Step 3: Add the new localized fields**

In `Sources/Vorssaint/Core/CommandBarStrings.swift`, add four fields to `struct CommandBarFeatureStrings` (near the other `source*`/`kind*` fields, e.g. right after `let linksTitle: String`). `kindBookmark` and `bookmarksProfileFormat` are shared by the Firefox and Safari groups later (Tasks 7, 11) — do not redefine them there. `chromeBookmarksNotInstalled` is Chrome-specific on purpose: Firefox and Safari add their own `firefoxBookmarksNotInstalled`/`safariBookmarksNotInstalled` fields in Tasks 7 and 11 rather than sharing one, since Settings prose reads better naming the actual browser than a generic placeholder would.

```swift
    let sourceChromeBookmarks: String
    let kindBookmark: String
    let bookmarksProfileFormat: String
    let chromeBookmarksNotInstalled: String
```

Then add one line to **each of the 13** `static let <lang> = CommandBarFeatureStrings(...)` blocks (search for `linksTitle:` to find each block; add these four lines right after it). English and one other language shown in full — repeat the same shape, translated, for the remaining eleven:

```swift
// .enUS block, after `linksTitle: "Your shortcuts",`
        sourceChromeBookmarks: "Chrome Bookmarks",
        kindBookmark: "Bookmark",
        bookmarksProfileFormat: "Profile: %@",
        chromeBookmarksNotInstalled: "Chrome isn't installed on this Mac.",
```

```swift
// .ptBR block, after `linksTitle: "Seus atalhos",`
        sourceChromeBookmarks: "Favoritos do Chrome",
        kindBookmark: "Favorito",
        bookmarksProfileFormat: "Perfil: %@",
        chromeBookmarksNotInstalled: "O Chrome não está instalado neste Mac.",
```

Repeat for `.tr`, `.ru`, `.es`, `.de`, `.fr`, `.it`, `.ja`, `.ko`, `.zhHans`, `.zhTW`, `.zhHK`, each translated into that language, inserted after that block's own `linksTitle:` line.

- [ ] **Step 4: Update the switch in `Core/CommandBarStrings.swift` line 163-179 stays unchanged** — it already returns the full per-language struct value, so no edit needed there; confirm by reading it, don't skip this check.

- [ ] **Step 5: Bump the pinned localization count**

In `Tests/MetricsTests.swift`, find:

```swift
            expect(commandBarValues.count == 151 && commandBarValues.allSatisfy { !$0.isEmpty },
```

Change `151` to `155` (four new fields).

- [ ] **Step 6: Build and test**

Run: `./build.sh`
Expected: SUCCESS, no warnings.

Run: `./build.sh --test`
Expected: SUCCESS, including the updated `commandBarValues.count == 155` assertion.

- [ ] **Step 7: Commit**

```bash
git add Sources/Vorssaint/Services/CommandBar/CommandBarCatalog.swift \
        Sources/Vorssaint/Services/CommandBar/CommandBarPreferences.swift \
        Sources/Vorssaint/Services/CommandBar/CommandBarService.swift \
        Sources/Vorssaint/UI/Settings/CommandBarSettings.swift \
        Sources/Vorssaint/Core/CommandBarStrings.swift \
        Tests/MetricsTests.swift
git commit -m "feat(command-bar): add Chrome bookmarks source scaffolding"
```

---

## Task 2: Shared bookmark parsing helpers

**Files:**
- Create: `Sources/Vorssaint/Services/CommandBar/CommandBarBookmarksSupport.swift`
- Modify: `build.sh` (add the new file to the `--test` compile list)
- Modify: `Tests/MetricsTests.swift` (new `MARK` section)

**Interfaces:**
- Produces: `CommandBarBookmarksSupport.isOfferableURL(_:allowFileScheme:) -> Bool`, `.keywords(title:url:folder:) -> String`, `.FileSignature` struct, `.signature(_:) -> String`. Tasks 3, 4, 8, 9, 12, 13 all call these.

- [ ] **Step 1: Write the failing tests**

In `Tests/MetricsTests.swift`, add a new section right after the existing `// MARK: Finding a file from the bar` block (near line 16117, following the `CommandBarFileSearchSupport` tests):

```swift
        // MARK: Shared bookmark parsing rules
        expect(CommandBarBookmarksSupport.isOfferableURL("https://example.com/page")
                && CommandBarBookmarksSupport.isOfferableURL("http://example.com"),
               "ordinary web bookmarks are offered")
        expect(!CommandBarBookmarksSupport.isOfferableURL("javascript:alert(1)")
                && !CommandBarBookmarksSupport.isOfferableURL("data:text/html,hi")
                && !CommandBarBookmarksSupport.isOfferableURL(""),
               "a bookmarklet or a data URL is never handed to NSWorkspace.open")
        expect(!CommandBarBookmarksSupport.isOfferableURL("file:///Users/x/notes.html")
                && CommandBarBookmarksSupport.isOfferableURL("file:///Users/x/notes.html", allowFileScheme: true),
               "file:// is offered only where the caller opts in")
        expect(CommandBarBookmarksSupport.keywords(title: "PR review", url: "https://github.com/org/repo/pull/1",
                                                    folder: "Work/Dev")
                == "PR review github.com Work/Dev",
               "typing the domain or the folder still finds a bookmark the title alone would not")
        expect(CommandBarBookmarksSupport.keywords(title: "Untitled", url: "not a url", folder: "")
                == "Untitled",
               "an unparseable URL or an empty folder drops out instead of leaving stray spaces")
        let sigA = CommandBarBookmarksSupport.signature([
            .init(path: "/a", size: 10, modified: Date(timeIntervalSince1970: 100)),
            .init(path: "/b", size: 20, modified: Date(timeIntervalSince1970: 200)),
        ])
        let sigB = CommandBarBookmarksSupport.signature([
            .init(path: "/a", size: 10, modified: Date(timeIntervalSince1970: 100)),
            .init(path: "/b", size: 21, modified: Date(timeIntervalSince1970: 200)),
        ])
        expect(sigA != sigB, "a one-byte size change produces a different signature")
        expect(sigA == CommandBarBookmarksSupport.signature([
            .init(path: "/a", size: 10, modified: Date(timeIntervalSince1970: 100)),
            .init(path: "/b", size: 20, modified: Date(timeIntervalSince1970: 200)),
        ]), "the same inputs always produce the same signature")
```

- [ ] **Step 2: Run the tests to confirm they fail**

Run: `swift build` (the test file references a type that doesn't exist yet)
Expected: FAIL — "cannot find type 'CommandBarBookmarksSupport' in scope"

- [ ] **Step 3: Write the implementation**

Create `Sources/Vorssaint/Services/CommandBar/CommandBarBookmarksSupport.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The rules every browser's bookmark reader shares: which URLs are worth
/// offering, what a row is ranked against, and how a reader decides its
/// cached list is stale. Pure, so these are pinned by tests rather than
/// discovered against one person's browser profile.
enum CommandBarBookmarksSupport {
    /// A bookmarklet, a `data:` URL or anything else with no page to open is
    /// filtered out here rather than handed to `NSWorkspace.open` from data
    /// read out of a file this app does not control.
    static func isOfferableURL(_ raw: String, allowFileScheme: Bool = false) -> Bool {
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased() else { return false }
        if scheme == "http" || scheme == "https" { return true }
        return allowFileScheme && scheme == "file"
    }

    /// What a row is ranked against beyond its own title: the domain and the
    /// folder it lives in, both invisible to the fuzzy matcher otherwise.
    static func keywords(title: String, url: String, folder: String) -> String {
        let host = URL(string: url)?.host ?? ""
        return [title, host, folder].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// One file a reader depends on, at the moment it last looked.
    struct FileSignature: Equatable {
        let path: String
        let size: Int
        let modified: Date
    }

    /// A single value that changes if, and only if, any watched file's path,
    /// size or modification time changed. A reader compares this to the
    /// value from its last successful parse to decide whether to re-parse.
    static func signature(_ files: [FileSignature]) -> String {
        files.map { "\($0.path)|\($0.size)|\($0.modified.timeIntervalSince1970)" }
            .joined(separator: "\u{0}")
    }
}
```

- [ ] **Step 4: Run the tests to confirm they pass**

Run: `swift build`
Expected: SUCCESS

Run: the test binary that exercises `MetricsTests.swift`'s `expect` calls (see how existing `CommandBarFileSearchSupport` tests are invoked — this project runs them via `./build.sh --test`, not a separate `swift test` target, since there's no `Tests` target reachable that way; confirm by checking `build.sh --test`'s own output format before assuming).
Expected: SUCCESS, all new `expect(...)` lines print no failure.

- [ ] **Step 5: Register the file in build.sh**

In `build.sh`, find the line `Sources/Vorssaint/Services/CommandBar/CommandBarFileSearchSupport.swift \` and add immediately after it:

```
        Sources/Vorssaint/Services/CommandBar/CommandBarBookmarksSupport.swift \
```

- [ ] **Step 6: Build and test**

Run: `./build.sh && ./build.sh --test`
Expected: SUCCESS

- [ ] **Step 7: Commit**

```bash
git add Sources/Vorssaint/Services/CommandBar/CommandBarBookmarksSupport.swift build.sh Tests/MetricsTests.swift
git commit -m "feat(command-bar): add shared bookmark URL/signature helpers"
```

---

## Task 3: Chrome bookmark JSON parsing (pure)

**Files:**
- Create: `Sources/Vorssaint/Services/CommandBar/CommandBarBookmarksChromeSupport.swift`
- Modify: `build.sh`
- Modify: `Tests/MetricsTests.swift`

**Interfaces:**
- Consumes: nothing external.
- Produces: `CommandBarBookmarksChromeSupport.ParsedBookmark { id, title, url, folder }`, `.ChromeBookmarkNode` / `.ChromeBookmarksRoot` (Decodable), `.flattenedBookmarks(from:) -> [ParsedBookmark]`, `.ChromeLocalState` (Decodable), `.defaultProfileDirectory(infoCache:lastUsed:) -> String?`. Task 4 (`CommandBarBookmarksChrome`) is the only consumer.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/MetricsTests.swift`, after the shared bookmark section from Task 2:

```swift
        // MARK: Chrome bookmark parsing
        let chromeJSON = """
        {
          "roots": {
            "bookmark_bar": {
              "name": "Bookmarks bar",
              "type": "folder",
              "children": [
                { "guid": "g1", "name": "Vorssaint", "type": "url", "url": "https://vorssaint.example/" },
                {
                  "guid": "g2", "name": "Dev", "type": "folder",
                  "children": [
                    { "guid": "g3", "name": "PR review", "type": "url", "url": "https://github.com/org/repo/pull/1" }
                  ]
                }
              ]
            },
            "other": { "name": "Other bookmarks", "type": "folder", "children": [] }
          }
        }
        """
        let decodedChrome = try? JSONDecoder().decode(
            CommandBarBookmarksChromeSupport.ChromeBookmarksRoot.self,
            from: Data(chromeJSON.utf8))
        expect(decodedChrome != nil, "well-formed Chrome Bookmarks JSON decodes")
        if let root = decodedChrome {
            let flat = CommandBarBookmarksChromeSupport.flattenedBookmarks(from: root)
            expect(flat.count == 2, "one root-level bookmark and one nested inside a folder")
            expect(flat.contains { $0.id == "g1" && $0.title == "Vorssaint" && $0.folder == "Bookmarks bar" },
                   "a bookmark directly on the bar carries the bar's own name as its folder")
            expect(flat.contains { $0.id == "g3" && $0.folder == "Bookmarks bar/Dev" },
                   "a nested bookmark's folder is the full path down to it")
        }
        let emptyLocalState = try? JSONDecoder().decode(
            CommandBarBookmarksChromeSupport.ChromeLocalState.self,
            from: Data("{}".utf8))
        expect(emptyLocalState != nil, "a Local State missing the profile key still decodes, as an empty one")
        expect(CommandBarBookmarksChromeSupport.defaultProfileDirectory(
                infoCache: ["Default": true, "Profile 1": true], lastUsed: "Profile 1") == "Profile 1",
               "the last-used profile wins when it actually has bookmarks")
        expect(CommandBarBookmarksChromeSupport.defaultProfileDirectory(
                infoCache: ["Default": true, "Profile 1": false], lastUsed: "Profile 1") == "Default",
               "a last-used profile with no bookmarks file falls back to Default")
        expect(CommandBarBookmarksChromeSupport.defaultProfileDirectory(
                infoCache: ["Profile 2": true, "Profile 1": true], lastUsed: nil) == "Profile 1",
               "with no recorded last-used profile, the alphabetically first eligible one is picked")
        expect(CommandBarBookmarksChromeSupport.defaultProfileDirectory(infoCache: [:], lastUsed: nil) == nil,
               "no eligible profile means nothing to read")
```

- [ ] **Step 2: Run to confirm failure**

Run: `swift build`
Expected: FAIL — `CommandBarBookmarksChromeSupport` not found.

- [ ] **Step 3: Write the implementation**

Create `Sources/Vorssaint/Services/CommandBar/CommandBarBookmarksChromeSupport.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Parsing Chrome's own `Bookmarks`/`AccountBookmarks` JSON and `Local
/// State` profile registry. Pure: given already-read JSON, produces a flat
/// list. The file reads, the `AccountBookmarks`-over-`Bookmarks` preference,
/// and the directory-scan fallback all live in `CommandBarBookmarksChrome`,
/// which is not part of this test harness.
enum CommandBarBookmarksChromeSupport {
    struct ParsedBookmark: Equatable {
        let id: String
        let title: String
        let url: String
        let folder: String
    }

    struct ChromeBookmarkNode: Decodable {
        let guid: String?
        let name: String
        let type: String
        let url: String?
        let children: [ChromeBookmarkNode]?
    }

    struct ChromeBookmarksRoot: Decodable {
        struct Roots: Decodable {
            let bookmarkBar: ChromeBookmarkNode?
            let other: ChromeBookmarkNode?
            let synced: ChromeBookmarkNode?
        }
        let roots: Roots
    }

    /// Every leaf under `bookmark_bar`, `other` and `synced`, each carrying
    /// the joined titles of the folders above it — including the root's own
    /// name, which is what a person actually sees as "Bookmarks bar" in
    /// Chrome.
    static func flattenedBookmarks(from root: ChromeBookmarksRoot) -> [ParsedBookmark] {
        var results: [ParsedBookmark] = []
        for node in [root.roots.bookmarkBar, root.roots.other, root.roots.synced].compactMap({ $0 }) {
            walk(node, path: [], into: &results)
        }
        return results
    }

    private static func walk(_ node: ChromeBookmarkNode, path: [String],
                             into results: inout [ParsedBookmark]) {
        if node.type == "url", let url = node.url, !node.name.isEmpty {
            results.append(ParsedBookmark(id: node.guid ?? url, title: node.name,
                                          url: url, folder: path.joined(separator: "/")))
            return
        }
        guard node.type == "folder", let children = node.children else { return }
        let nextPath = path + [node.name]
        for child in children { walk(child, path: nextPath, into: &results) }
    }

    struct ChromeLocalState: Decodable {
        struct Profile: Decodable {
            let infoCache: [String: ProfileInfo]?
            let lastUsed: String?
        }
        struct ProfileInfo: Decodable {}
        let profile: Profile?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            profile = try container.decodeIfPresent(Profile.self, forKey: .profile)
        }
        private enum CodingKeys: String, CodingKey { case profile }
    }

    /// Which profile directory to read: the last-used one if it actually has
    /// a bookmarks file, else `Default` if that has one, else the
    /// alphabetically first eligible directory, else nothing to read.
    /// `infoCache` maps a profile's directory name to whether the caller
    /// already found a bookmarks file for it.
    static func defaultProfileDirectory(infoCache: [String: Bool], lastUsed: String?) -> String? {
        if let lastUsed, infoCache[lastUsed] == true { return lastUsed }
        if infoCache["Default"] == true { return "Default" }
        return infoCache.filter { $0.value }.keys.sorted().first
    }
}
```

Note: `ChromeBookmarksRoot`/`ChromeBookmarkNode` rely on `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase` being set by the caller (Task 4) — `bookmark_bar` only decodes into `bookmarkBar` with that strategy active. Document this at the call site in Task 4; do not duplicate `CodingKeys` boilerplate here for a strategy the decoder already provides.

- [ ] **Step 4: Run to confirm success**

Run: `./build.sh --test`
Expected: SUCCESS

- [ ] **Step 5: Register in build.sh**

Add `Sources/Vorssaint/Services/CommandBar/CommandBarBookmarksChromeSupport.swift \` to `build.sh`, right after the `CommandBarBookmarksSupport.swift` line added in Task 2.

- [ ] **Step 6: Build and test**

Run: `./build.sh && ./build.sh --test`
Expected: SUCCESS

- [ ] **Step 7: Commit**

```bash
git add Sources/Vorssaint/Services/CommandBar/CommandBarBookmarksChromeSupport.swift build.sh Tests/MetricsTests.swift
git commit -m "feat(command-bar): add Chrome bookmark JSON parsing"
```

---

## Task 4: Chrome bookmark reader (file I/O, caching)

**Files:**
- Create: `Sources/Vorssaint/Services/CommandBar/CommandBarBookmarksChrome.swift`

**Interfaces:**
- Consumes: `CommandBarBookmarksChromeSupport.{ParsedBookmark, ChromeBookmarksRoot, ChromeLocalState, flattenedBookmarks, defaultProfileDirectory}`, `CommandBarBookmarksSupport.{FileSignature, signature}`.
- Produces: `final class CommandBarBookmarksChrome { init(rootDirectory: URL = <default>); var cachedBookmarks: [CommandBarBookmarksChromeSupport.ParsedBookmark]; func refreshIfNeeded(enabled: Bool) }`. Task 5 (`CommandBarService`) owns one instance and calls `refreshIfNeeded(enabled:)` on every bar open, then reads `cachedBookmarks`.

This class is not part of the pure-function harness — it touches the filesystem — but it is still testable, unlike `CommandBarFileSearch`'s live Spotlight query, because a temp directory with hand-written fixture files stands in for a real Chrome profile. `rootDirectory` is an injectable constructor parameter for exactly this reason.

- [ ] **Step 1: Write the implementation**

Create `Sources/Vorssaint/Services/CommandBar/CommandBarBookmarksChrome.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Chrome's own bookmarks, read from its profile files. No permission is
/// asked for: `~/Library/Application Support/Google/Chrome` is an ordinary,
/// unprotected folder.
final class CommandBarBookmarksChrome {
    private(set) var cachedBookmarks: [CommandBarBookmarksChromeSupport.ParsedBookmark] = []
    private var lastSignature: String?
    private let rootDirectory: URL

    /// `rootDirectory` defaults to Chrome's real profile folder; a test
    /// passes a temp directory with hand-written fixture files instead.
    init(rootDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome")) {
        self.rootDirectory = rootDirectory
    }

    /// Re-parses only when enabled and something watched has changed since
    /// the last call. Safe to call on every bar open.
    func refreshIfNeeded(enabled: Bool) {
        guard enabled else {
            if lastSignature != nil || !cachedBookmarks.isEmpty {
                lastSignature = nil
                cachedBookmarks = []
            }
            return
        }
        let localStatePath = rootDirectory.appendingPathComponent("Local State").path
        guard let profileDirectory = resolveProfileDirectory(localStatePath: localStatePath) else {
            lastSignature = nil
            cachedBookmarks = []
            return
        }
        let accountPath = profileDirectory.appendingPathComponent("AccountBookmarks").path
        let bookmarksPath = profileDirectory.appendingPathComponent("Bookmarks").path
        let backupPath = profileDirectory.appendingPathComponent("Bookmarks.bak").path
        let signature = CommandBarBookmarksSupport.signature(
            [localStatePath, accountPath, bookmarksPath].compactMap(Self.fileSignature))
        guard signature != lastSignature else { return }
        lastSignature = signature
        cachedBookmarks = parsedBookmarks(accountPath: accountPath, bookmarksPath: bookmarksPath,
                                          backupPath: backupPath)
    }

    private func resolveProfileDirectory(localStatePath: String) -> URL? {
        let fm = FileManager.default
        var infoCache: [String: Bool] = [:]
        var lastUsed: String?
        if let data = fm.contents(atPath: localStatePath) {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            if let state = try? decoder.decode(CommandBarBookmarksChromeSupport.ChromeLocalState.self,
                                               from: data) {
                lastUsed = state.profile?.lastUsed
                for name in state.profile?.infoCache?.keys ?? [:].keys {
                    infoCache[name] = Self.hasBookmarksFile(in: rootDirectory.appendingPathComponent(name))
                }
            }
        }
        if infoCache.isEmpty {
            // Local State missing or unparseable: scan the directory itself,
            // Chrome's own fallback path.
            let children = (try? fm.contentsOfDirectory(atPath: rootDirectory.path)) ?? []
            for name in children {
                var isDirectory: ObjCBool = false
                guard fm.fileExists(atPath: rootDirectory.appendingPathComponent(name).path,
                                    isDirectory: &isDirectory), isDirectory.boolValue else { continue }
                infoCache[name] = Self.hasBookmarksFile(in: rootDirectory.appendingPathComponent(name))
            }
        }
        guard let chosen = CommandBarBookmarksChromeSupport.defaultProfileDirectory(
            infoCache: infoCache, lastUsed: lastUsed) else { return nil }
        return rootDirectory.appendingPathComponent(chosen)
    }

    private static func hasBookmarksFile(in directory: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: directory.appendingPathComponent("Bookmarks").path)
            || fm.fileExists(atPath: directory.appendingPathComponent("AccountBookmarks").path)
    }

    /// Prefers `AccountBookmarks` (present and non-empty) over `Bookmarks`,
    /// and `Bookmarks.bak` as a last resort if the primary file fails to
    /// parse — Chrome's own atomic-write fallback file.
    private func parsedBookmarks(accountPath: String, bookmarksPath: String,
                                 backupPath: String) -> [CommandBarBookmarksChromeSupport.ParsedBookmark] {
        for candidate in [accountPath, bookmarksPath, backupPath] {
            if let parsed = Self.parseFile(at: candidate), !parsed.isEmpty {
                return parsed
            }
        }
        // A genuinely empty (but well-formed) Bookmarks file is a valid
        // result, not a failure — try once more without the emptiness check
        // so "no bookmarks" doesn't fall through to the backup file.
        return Self.parseFile(at: bookmarksPath) ?? []
    }

    private static func parseFile(at path: String) -> [CommandBarBookmarksChromeSupport.ParsedBookmark]? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let root = try? decoder.decode(CommandBarBookmarksChromeSupport.ChromeBookmarksRoot.self,
                                             from: data) else { return nil }
        return CommandBarBookmarksChromeSupport.flattenedBookmarks(from: root)
    }

    private static func fileSignature(_ path: String) -> CommandBarBookmarksSupport.FileSignature? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? Int,
              let modified = attributes[.modificationDate] as? Date
        else { return nil }
        return .init(path: path, size: size, modified: modified)
    }
}
```

- [ ] **Step 2: Add a temp-fixture behavioral test**

Add to `Tests/MetricsTests.swift`, in the Chrome section from Task 3:

```swift
        // MARK: Chrome bookmark reader against a fixture profile
        let chromeFixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorssaint-chrome-fixture-\(UUID().uuidString)")
        let chromeProfile = chromeFixtureRoot.appendingPathComponent("Default")
        try? FileManager.default.createDirectory(at: chromeProfile, withIntermediateDirectories: true)
        try? chromeJSON.write(to: chromeProfile.appendingPathComponent("Bookmarks"),
                              atomically: true, encoding: .utf8)
        let localState = """
        {"profile":{"info_cache":{"Default":{}},"last_used":"Default"}}
        """
        try? localState.write(to: chromeFixtureRoot.appendingPathComponent("Local State"),
                              atomically: true, encoding: .utf8)
        let chromeReader = CommandBarBookmarksChrome(rootDirectory: chromeFixtureRoot)
        chromeReader.refreshIfNeeded(enabled: true)
        expect(chromeReader.cachedBookmarks.count == 2,
               "the reader finds both bookmarks in the fixture profile")
        let signatureAfterFirstRead = chromeReader.cachedBookmarks
        chromeReader.refreshIfNeeded(enabled: true)
        expect(chromeReader.cachedBookmarks.map(\.id) == signatureAfterFirstRead.map(\.id),
               "an unchanged fixture does not reorder or drop rows on a second refresh")
        chromeReader.refreshIfNeeded(enabled: false)
        expect(chromeReader.cachedBookmarks.isEmpty, "disabling the source clears its cache")
        try? FileManager.default.removeItem(at: chromeFixtureRoot)
```

(This reuses the `chromeJSON` string literal declared in Task 3's tests — keep this block textually after that one in the file so it's in scope.)

- [ ] **Step 3: Build and test**

Run: `./build.sh`
Expected: SUCCESS — note this file is deliberately **not** added to `build.sh`'s `--test` list, matching `CommandBarFileSearch.swift` itself (the stateful class) staying outside that list while its `*Support.swift` sibling is on it. The fixture test above lives in `MetricsTests.swift` and is exercised by `./build.sh --test`'s existing invocation of the whole file, which links against the full app target, not the pared-down list — confirm this by running:

Run: `./build.sh --test`
Expected: SUCCESS. If `CommandBarBookmarksChrome` is genuinely unreachable from the `--test` binary (i.e. the fixture test above fails to compile because the type is missing), add `Sources/Vorssaint/Services/CommandBar/CommandBarBookmarksChrome.swift` to `build.sh`'s list too — the constraint is "don't skip registering a file the tests need," not "never register a stateful class." Verify which is true here rather than assuming.

- [ ] **Step 4: Commit**

```bash
git add Sources/Vorssaint/Services/CommandBar/CommandBarBookmarksChrome.swift Tests/MetricsTests.swift build.sh
git commit -m "feat(command-bar): add Chrome bookmark reader with mtime caching"
```

---

## Task 5: Wire Chrome bookmarks into the catalog and service

**Files:**
- Modify: `Sources/Vorssaint/Services/CommandBar/CommandBarCatalog.swift` (new `chromeBookmarkEntries`, `build(...)` signature)
- Modify: `Sources/Vorssaint/Services/CommandBar/CommandBarService.swift` (own a `CommandBarBookmarksChrome`, reload-on-open, pass into `build(...)`)
- Modify: `Sources/Vorssaint/UI/Settings/CommandBarSettings.swift` (profile/not-installed caption)

**Interfaces:**
- Consumes: `CommandBarBookmarksChrome.cachedBookmarks`, `InstalledApps.url(for:) -> URL?` (existing helper, `Sources/Vorssaint/Services/InstalledApps.swift:25`), `CommandBarEntry.Icon.appIcon(path:)` (existing case).
- Produces: `CommandBarCatalog.build(automationDenied:chromeBookmarks:) -> [CommandBarEntry]` — the new parameter is required from this point on; Tasks 9 and 13 extend this signature further, not replace it.

- [ ] **Step 1: Add the catalog entry builder**

In `Sources/Vorssaint/Services/CommandBar/CommandBarCatalog.swift`, near `linkEntries` (after it, before `scriptAnswerEntry`):

```swift
    // MARK: - Chrome bookmarks

    static func chromeBookmarkEntries(
        _ bookmarks: [CommandBarBookmarksChromeSupport.ParsedBookmark],
        bar: CommandBarFeatureStrings
    ) -> [CommandBarEntry] {
        let chromeIconPath = InstalledApps.url(for: "com.google.Chrome")?.path
        return bookmarks.map { bookmark in
            CommandBarEntry(
                id: "chromebookmark.\(bookmark.id)",
                title: bookmark.title,
                subtitle: bookmark.folder.isEmpty ? bar.sourceChromeBookmarks : bookmark.folder,
                keywords: CommandBarBookmarksSupport.keywords(
                    title: bookmark.title, url: bookmark.url, folder: bookmark.folder),
                icon: chromeIconPath.map { .appIcon(path: $0) } ?? .symbol("globe"),
                run: { _ in
                    guard CommandBarBookmarksSupport.isOfferableURL(bookmark.url),
                          let url = URL(string: bookmark.url) else { return }
                    guard let appURL = InstalledApps.url(for: "com.google.Chrome") else {
                        NSWorkspace.shared.open(url)
                        return
                    }
                    NSWorkspace.shared.open([url], withApplicationAt: appURL,
                                            configuration: NSWorkspace.OpenConfiguration())
                })
        }
    }
```

Update `build(...)`'s signature and body:

```swift
    static func build(automationDenied: Bool,
                      chromeBookmarks: [CommandBarBookmarksChromeSupport.ParsedBookmark]) -> [CommandBarEntry] {
        let s = L10n.shared.s
        let language = L10n.shared.language
        let bar = FeatureStrings.commandBar(language)
        var entries: [CommandBarEntry] = []
        entries.append(contentsOf: actionEntries(s, language: language, bar: bar,
                                                 automationDenied: automationDenied))
        entries.append(contentsOf: toggleEntries(s, language: language, bar: bar))
        entries.append(contentsOf: systemAnswerEntries(s, bar: bar))
        entries.append(contentsOf: settingsEntries(s, language: language, bar: bar))
        entries.append(contentsOf: snippetEntries(bar))
        entries.append(contentsOf: linkEntries(
            CommandBarLinks.decode(UserDefaults.standard.data(forKey: DefaultsKey.commandBarLinks)),
            bar: bar))
        entries.append(contentsOf: chromeBookmarkEntries(chromeBookmarks, bar: bar))
        return entries
    }
```

- [ ] **Step 2: Own the reader in `CommandBarService`**

In `Sources/Vorssaint/Services/CommandBar/CommandBarService.swift`, near `let fileSearch = CommandBarFileSearch()` (line 107):

```swift
    let fileSearch = CommandBarFileSearch()
    private let chromeBookmarks = CommandBarBookmarksChrome()
```

Near `private var fileSearchPreferenceSignature: String?` (line 680), add the reload function following `reloadFileSearchCaches()`'s exact shape:

```swift
    private func reloadPreferenceCaches() {
        pinCache = Set(pins)
        shortcutCache = rowShortcuts
        compactMode = UserDefaults.standard.bool(forKey: DefaultsKey.commandBarCompactMode)
        hasCustomPosition = positionOffset != .zero
        reloadFileSearchCaches()
        chromeBookmarks.refreshIfNeeded(enabled: isEnabled(.chromeBookmarks))
    }
```

(`refreshIfNeeded` already no-ops when nothing changed, so calling it here on every bar open — synchronously, since Chrome's JSON files are small — is cheap. If a manual test on a very large real Chrome profile shows this is not cheap enough, move the parse onto `DispatchQueue.global` and call `refreshResults()` when it completes, exactly like `reloadFileSearchCaches()` does for scope resolution; do not add that complexity speculatively before measuring.)

Update `rebuildCatalog()`:

```swift
    private func rebuildCatalog(index: Bool = true) {
        catalog = CommandBarCatalog.build(automationDenied: finderAutomationDenied,
                                          chromeBookmarks: chromeBookmarks.cachedBookmarks)
        emojiEntries = CommandBarCatalog.emojiEntries(bar: FeatureStrings.commandBar(L10n.shared.language))
        builtLanguage = L10n.shared.language
        if index { indexEntries() }
    }
```

- [ ] **Step 3: Add the profile/not-installed caption to Settings**

In `Sources/Vorssaint/UI/Settings/CommandBarSettings.swift`, the `ForEach(CommandBarSource.allCases)` block (line 102) already renders the new toggle automatically once Task 1 lands. Add a caption row beneath it for the browser-specific state, following the same `Section { ... } footer: { ... }` shape used for `filesCaption` immediately below in that file:

```swift
                if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") == nil {
                    Text(text.chromeBookmarksNotInstalled)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
```

placed directly after the `ForEach(CommandBarSource.allCases) { ... }` block, inside the same `Section`.

- [ ] **Step 4: Build and test**

Run: `./build.sh && ./build.sh --test`
Expected: SUCCESS

- [ ] **Step 5: Manual verification**

Install Chrome if not already present, ensure it has at least one bookmark, then run a signed local build (`./Tools/setup-signing.sh` once if not already done) and confirm:
- Opening the Command Bar and typing a bookmark's title shows it, tagged with Chrome's icon.
- Typing a word only in the bookmark's URL domain or folder also finds it.
- Return opens it in Chrome specifically (check which browser's window activates).
- Turning the "Chrome Bookmarks" toggle off in Settings removes the rows immediately on the next bar open.
- A `javascript:` bookmarklet, if you have one, does not appear as a row.

- [ ] **Step 6: Commit**

```bash
git add Sources/Vorssaint/Services/CommandBar/CommandBarCatalog.swift \
        Sources/Vorssaint/Services/CommandBar/CommandBarService.swift \
        Sources/Vorssaint/UI/Settings/CommandBarSettings.swift
git commit -m "feat(command-bar): search and open Chrome bookmarks"
```

---

## Task 6: Chrome group docs and close-out

**Files:**
- Modify: `docs/PRIVACY.md`

**Interfaces:** none — documentation only.

- [ ] **Step 1: Update PRIVACY.md**

In `docs/PRIVACY.md`'s "What it reads, and where that stays" section, add a sentence after the existing paragraph about local reads:

```markdown
When the Command Bar's Chrome Bookmarks source is on, it reads Chrome's own local bookmark and profile files to make them searchable; nothing about them is sent anywhere, and turning the source off in Settings stops it from reading those files at all.
```

- [ ] **Step 2: Build**

Run: `./build.sh && ./build.sh --test`
Expected: SUCCESS (docs-only change, but confirms nothing else broke since Task 5).

- [ ] **Step 3: Commit**

```bash
git add docs/PRIVACY.md
git commit -m "docs(privacy): note the Command Bar's Chrome bookmarks read"
```

This closes the Chrome group. It is mergeable and useful on its own — the Firefox and Safari groups below are independent additions, not fixes to anything here.

---

## Task 7: Firefox Command Bar source scaffolding

**Files:**
- Modify: `Sources/Vorssaint/Services/CommandBar/CommandBarCatalog.swift` (`CommandBarSource` enum)
- Modify: `Sources/Vorssaint/Services/CommandBar/CommandBarPreferences.swift`
- Modify: `Sources/Vorssaint/Services/CommandBar/CommandBarService.swift`
- Modify: `Sources/Vorssaint/UI/Settings/CommandBarSettings.swift`
- Modify: `Sources/Vorssaint/Core/CommandBarStrings.swift`
- Modify: `Tests/MetricsTests.swift:17421` (pinned count, now 155 → 157 (two new fields: sourceFirefoxBookmarks, firefoxBookmarksNotInstalled))

Same red/green enum-completeness approach as Task 1, one new case: `CommandBarSource.firefoxBookmarks`, `idPrefix: "firefoxbookmark."`, `symbolName: "globe"`, added to the same five switches (`rankBias`, `acceptsAlias`, `acceptsPin`, `isHubOwned`, `categoryHasContent`, `categoryContent`, `categoryTitle`, `browseGroup`, `title(for:)`) and `kindLimits` (`("firefoxbookmark.", 5)`).

New localized field, in all 13 languages: `sourceFirefoxBookmarks` (e.g. `"Firefox Bookmarks"` / `"Favoritos do Firefox"` / ...) and `firefoxBookmarksNotInstalled` (e.g. `"Firefox isn't installed on this Mac."`). `kindBookmark` and `bookmarksProfileFormat` already exist from Task 1 — reuse them, do not redefine.

`browseGroup`'s new arm: `case .chromeBookmarks, .firefoxBookmarks: return bar.kindBookmark` (extend the existing Chrome-only arm rather than adding a second one).

- [ ] **Step 1: Add the case, watch it fail, fix every switch** — same procedure as Task 1 Steps 1-2, substituting `firefoxBookmarks`/`sourceFirefoxBookmarks`/`firefoxBookmarksNotInstalled` throughout. Write out each switch's full new body before moving on (do not shorthand it as "same as Task 1" in the actual commit — the exhaustive switches must compile).

- [ ] **Step 2: Bump the pinned count** to `157` in `Tests/MetricsTests.swift`.

- [ ] **Step 3: Build and test**

Run: `./build.sh && ./build.sh --test`
Expected: SUCCESS

- [ ] **Step 4: Commit**

```bash
git commit -am "feat(command-bar): add Firefox bookmarks source scaffolding"
```

---

## Task 8: Firefox bookmark parsing (pure)

**Files:**
- Create: `Sources/Vorssaint/Services/CommandBar/CommandBarBookmarksFirefoxSupport.swift`
- Modify: `build.sh`
- Modify: `Tests/MetricsTests.swift`

**Interfaces:**
- Produces: `CommandBarBookmarksFirefoxSupport.ParsedBookmark { id, title, url, folder }`, `.defaultProfilePath(profilesIni:) -> String?`, `.friendlyRootName(_:) -> String`, `.buildFolderPaths(bookmarkRows:folderRows:) -> [Int: String]`, `.parsedBookmarks(bookmarkRows:folderPaths:) -> [ParsedBookmark]`. Task 9 (`CommandBarBookmarksFirefox`) is the only consumer.

Firefox's data does not arrive as a nested tree like Chrome's — SQLite rows are flat, each carrying only its immediate `parentId`, so the hierarchy is built by walking that chain per bookmark rather than recursing a JSON tree. This is genuinely different logic from Task 3's `flattenedBookmarks`, not a re-use of it (the two browsers share `CommandBarBookmarksSupport`'s URL filter and keyword builder, not a tree-walker).

- [ ] **Step 1: Write the failing tests**

```swift
        // MARK: Firefox bookmark parsing
        let profilesIni = """
        [Install4F96D1932A9F858E]
        Default=abc123.default-release
        Locked=1

        [Profile1]
        Name=default-release
        IsRelative=1
        Path=abc123.default-release
        Default=1

        [Profile0]
        Name=work
        IsRelative=1
        Path=xyz789.work
        """
        expect(CommandBarBookmarksFirefoxSupport.defaultProfilePath(profilesIni: profilesIni)
                == "abc123.default-release",
               "the Install section's Default key wins, not a per-profile Default flag")
        let noInstallSection = """
        [Profile0]
        Name=work
        IsRelative=1
        Path=xyz789.work
        """
        expect(CommandBarBookmarksFirefoxSupport.defaultProfilePath(profilesIni: noInstallSection)
                == "xyz789.work",
               "with no Install section, the first profile found is used")
        expect(CommandBarBookmarksFirefoxSupport.defaultProfilePath(profilesIni: "") == nil,
               "an empty or missing profiles.ini has nothing to read")
        expect(CommandBarBookmarksFirefoxSupport.friendlyRootName("toolbar") == "Bookmarks Toolbar"
                && CommandBarBookmarksFirefoxSupport.friendlyRootName("menu") == "Bookmarks Menu"
                && CommandBarBookmarksFirefoxSupport.friendlyRootName("unfiled") == "Other Bookmarks"
                && CommandBarBookmarksFirefoxSupport.friendlyRootName("mobile") == "Mobile Bookmarks"
                && CommandBarBookmarksFirefoxSupport.friendlyRootName("Dev") == "Dev",
               "the four root guids get a friendly name; an ordinary folder keeps its own title")
        // id, parentId, title, guid
        let folderRows: [(id: Int, parentId: Int, title: String, guid: String)] = [
            (1, 0, "root________", "root________"),
            (2, 1, "toolbar", "toolbar_____"),
            (3, 2, "Dev", "abc"),
        ]
        let paths = CommandBarBookmarksFirefoxSupport.buildFolderPaths(folderRows: folderRows)
        expect(paths[2] == "Bookmarks Toolbar", "the toolbar root resolves to its friendly name")
        expect(paths[3] == "Bookmarks Toolbar/Dev", "a nested folder's path includes its parent chain")
        let bookmarkRows: [(id: Int, parentId: Int, title: String, url: String)] = [
            (10, 3, "PR review", "https://github.com/org/repo/pull/1"),
            (11, 2, "Vorssaint", "https://vorssaint.example/"),
        ]
        let parsed = CommandBarBookmarksFirefoxSupport.parsedBookmarks(
            bookmarkRows: bookmarkRows, folderPaths: paths)
        expect(parsed.count == 2, "both rows become bookmarks")
        expect(parsed.contains { $0.id == "10" && $0.folder == "Bookmarks Toolbar/Dev" },
               "a bookmark's folder is its parent's resolved path")
        expect(parsed.contains { $0.id == "11" && $0.folder == "Bookmarks Toolbar" },
               "a bookmark directly under the toolbar folder gets the toolbar's own friendly name")
```

- [ ] **Step 2: Confirm failure**, then **Step 3: implement**:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Parsing Firefox's `profiles.ini` and turning `moz_bookmarks`/`moz_places`
/// rows (already read by `CommandBarBookmarksFirefox`) into a flat list.
/// Pure: given rows, produces bookmarks. Opening `places.sqlite` and running
/// the SQL live outside this file.
enum CommandBarBookmarksFirefoxSupport {
    struct ParsedBookmark: Equatable {
        let id: String
        let title: String
        let url: String
        let folder: String
    }

    /// The profile `places.sqlite` lives in, resolved the way Firefox itself
    /// resolves it: the `Install*` section's `Default` key, not a
    /// per-profile flag. Falls back to the first profile section found if
    /// there is no `Install*` section at all.
    static func defaultProfilePath(profilesIni: String) -> String? {
        let sections = parseINI(profilesIni)
        if let installSection = sections.first(where: { $0.name.hasPrefix("Install") }),
           let path = installSection.values["Default"], !path.isEmpty {
            return path
        }
        return sections.first(where: { $0.name.hasPrefix("Profile") })?.values["Path"]
    }

    private static func parseINI(_ text: String) -> [(name: String, values: [String: String])] {
        var sections: [(name: String, values: [String: String])] = []
        var currentName: String?
        var currentValues: [String: String] = [:]
        func flush() {
            if let currentName { sections.append((currentName, currentValues)) }
        }
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("["), line.hasSuffix("]") {
                flush()
                currentName = String(line.dropFirst().dropLast())
                currentValues = [:]
            } else if let equals = line.firstIndex(of: "=") {
                let key = String(line[line.startIndex..<equals]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
                currentValues[key] = value
            }
        }
        flush()
        return sections
    }

    /// Firefox's four fixed root folders read as raw guids; every other
    /// folder keeps the title the person gave it.
    static func friendlyRootName(_ rawTitle: String) -> String {
        switch rawTitle {
        case "toolbar": return "Bookmarks Toolbar"
        case "menu": return "Bookmarks Menu"
        case "unfiled": return "Other Bookmarks"
        case "mobile": return "Mobile Bookmarks"
        default: return rawTitle
        }
    }

    /// Every folder's full path, resolved by walking `parentId` up to the
    /// root once per folder rather than recursing a tree — `moz_bookmarks`
    /// hands back a flat table, not nested JSON.
    static func buildFolderPaths(
        folderRows: [(id: Int, parentId: Int, title: String, guid: String)]
    ) -> [Int: String] {
        let byID = Dictionary(uniqueKeysWithValues: folderRows.map { ($0.id, $0) })
        var resolved: [Int: String] = [:]

        func resolve(_ id: Int) -> String {
            if let cached = resolved[id] { return cached }
            guard let row = byID[id] else { return "" }
            let ownName = friendlyRootName(row.title)
            guard let parent = byID[row.parentId], parent.id != row.id else {
                resolved[id] = ownName
                return ownName
            }
            let parentPath = resolve(parent.id)
            let full = parentPath.isEmpty ? ownName : "\(parentPath)/\(ownName)"
            resolved[id] = full
            return full
        }
        for row in folderRows { _ = resolve(row.id) }
        return resolved
    }

    static func parsedBookmarks(
        bookmarkRows: [(id: Int, parentId: Int, title: String, url: String)],
        folderPaths: [Int: String]
    ) -> [ParsedBookmark] {
        bookmarkRows.map { row in
            ParsedBookmark(id: String(row.id), title: row.title, url: row.url,
                           folder: folderPaths[row.parentId] ?? "")
        }
    }
}
```

- [ ] **Step 4: Confirm the tests pass**, **Step 5: register in build.sh**, **Step 6: build and test**:

Run: `./build.sh && ./build.sh --test`
Expected: SUCCESS

- [ ] **Step 7: Commit**

```bash
git add Sources/Vorssaint/Services/CommandBar/CommandBarBookmarksFirefoxSupport.swift build.sh Tests/MetricsTests.swift
git commit -m "feat(command-bar): add Firefox bookmark/profile parsing"
```

---

## Task 9: Firefox bookmark reader (SQLite, caching)

**Files:**
- Create: `Sources/Vorssaint/Services/CommandBar/CommandBarBookmarksFirefox.swift`

**Interfaces:**
- Consumes: `CommandBarBookmarksFirefoxSupport.{ParsedBookmark, defaultProfilePath, buildFolderPaths, parsedBookmarks}`, `CommandBarBookmarksSupport.{FileSignature, signature}`, `SQLite3` (system C library).
- Produces: `final class CommandBarBookmarksFirefox { init(rootDirectory: URL = <default>); var cachedBookmarks: [CommandBarBookmarksFirefoxSupport.ParsedBookmark]; func refreshIfNeeded(enabled: Bool) }`.

- [ ] **Step 1: Add the module import**

Confirm `import SQLite3` is available under a plain `swiftc`/SwiftPM build with no `Package.swift` change — this is the first SQLite use in the codebase, so verify this once before writing the rest of the file:

Run: `echo 'import SQLite3; print(SQLITE_OK)' | swift -`
Expected: prints `0` — confirms the system module links with no extra flags.

- [ ] **Step 2: Write the implementation**

Create `Sources/Vorssaint/Services/CommandBar/CommandBarBookmarksFirefox.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SQLite3

/// Firefox's own bookmarks, read from `places.sqlite`. No permission is
/// asked for: `~/Library/Application Support/Firefox` is an ordinary,
/// unprotected folder.
///
/// `places.sqlite` also holds Firefox's history, so its modification time
/// changes on ordinary browsing, not just on a bookmark edit. `refreshIfNeeded`
/// still checks the file's mtime on every call (a `stat()`, effectively
/// free), but only re-parses — real work — at most once every
/// `minimumReparseInterval`, so opening the bar repeatedly during active
/// browsing does not turn into repeated SQLite reads.
final class CommandBarBookmarksFirefox {
    private(set) var cachedBookmarks: [CommandBarBookmarksFirefoxSupport.ParsedBookmark] = []
    private var lastSignature: String?
    private var lastParseDate: Date?
    private let rootDirectory: URL
    private let minimumReparseInterval: TimeInterval

    init(rootDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Firefox"),
         minimumReparseInterval: TimeInterval = 5) {
        self.rootDirectory = rootDirectory
        self.minimumReparseInterval = minimumReparseInterval
    }

    func refreshIfNeeded(enabled: Bool) {
        guard enabled else {
            if lastSignature != nil || !cachedBookmarks.isEmpty {
                lastSignature = nil
                cachedBookmarks = []
            }
            return
        }
        let profilesIniPath = rootDirectory.appendingPathComponent("profiles.ini").path
        guard let profilesIni = try? String(contentsOfFile: profilesIniPath, encoding: .utf8),
              let profilePath = CommandBarBookmarksFirefoxSupport.defaultProfilePath(profilesIni: profilesIni)
        else {
            lastSignature = nil
            cachedBookmarks = []
            return
        }
        let dbPath = rootDirectory.appendingPathComponent(profilePath)
            .appendingPathComponent("places.sqlite").path
        guard let signatureFile = Self.fileSignature(dbPath) else {
            lastSignature = nil
            cachedBookmarks = []
            return
        }
        let signature = CommandBarBookmarksSupport.signature([signatureFile])
        guard signature != lastSignature else { return }
        if let lastParseDate, Date().timeIntervalSince(lastParseDate) < minimumReparseInterval {
            return
        }
        lastSignature = signature
        lastParseDate = Date()
        cachedBookmarks = Self.readBookmarks(atPath: dbPath) ?? cachedBookmarks
    }

    /// Opens read-only, tolerant of Firefox already holding the file open:
    /// `?immutable=1` skips SQLite's own locking, at the cost of possibly
    /// missing a bookmark added moments ago before Firefox checkpoints its
    /// WAL file — an acceptable tradeoff for a search feature.
    private static func readBookmarks(atPath path: String) -> [CommandBarBookmarksFirefoxSupport.ParsedBookmark]? {
        guard let uri = "file:\(path)?immutable=1".cString(using: .utf8) else { return nil }
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        guard sqlite3_open_v2(uri, &db, flags, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }

        let folderRows = query(db, sql: """
            SELECT id, parent, title, guid FROM moz_bookmarks
            WHERE type = 2 AND fk IS NULL AND title IS NOT NULL AND title <> '';
            """) { statement -> (id: Int, parentId: Int, title: String, guid: String)? in
            let id = Int(sqlite3_column_int(statement, 0))
            let parentId = Int(sqlite3_column_int(statement, 1))
            guard let titlePointer = sqlite3_column_text(statement, 2),
                  let guidPointer = sqlite3_column_text(statement, 3) else { return nil }
            return (id, parentId, String(cString: titlePointer), String(cString: guidPointer))
        }
        let bookmarkRows = query(db, sql: """
            SELECT moz_bookmarks.id, moz_bookmarks.parent, moz_bookmarks.title, moz_places.url
            FROM moz_bookmarks LEFT JOIN moz_places ON moz_bookmarks.fk = moz_places.id
            WHERE moz_bookmarks.type = 1 AND moz_bookmarks.title IS NOT NULL
              AND moz_places.url IS NOT NULL;
            """) { statement -> (id: Int, parentId: Int, title: String, url: String)? in
            let id = Int(sqlite3_column_int(statement, 0))
            let parentId = Int(sqlite3_column_int(statement, 1))
            guard let titlePointer = sqlite3_column_text(statement, 2),
                  let urlPointer = sqlite3_column_text(statement, 3) else { return nil }
            return (id, parentId, String(cString: titlePointer), String(cString: urlPointer))
        }
        let folderPaths = CommandBarBookmarksFirefoxSupport.buildFolderPaths(folderRows: folderRows)
        return CommandBarBookmarksFirefoxSupport.parsedBookmarks(bookmarkRows: bookmarkRows,
                                                                  folderPaths: folderPaths)
    }

    private static func query<T>(_ db: OpaquePointer, sql: String,
                                 row: (OpaquePointer) -> T?) -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return []
        }
        defer { sqlite3_finalize(statement) }
        var results: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let value = row(statement) { results.append(value) }
        }
        return results
    }

    private static func fileSignature(_ path: String) -> CommandBarBookmarksSupport.FileSignature? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? Int,
              let modified = attributes[.modificationDate] as? Date
        else { return nil }
        return .init(path: path, size: size, modified: modified)
    }
}
```

- [ ] **Step 3: Add a temp-fixture behavioral test**

Building a real `places.sqlite` fixture needs `sqlite3` itself (available as a system tool), not hand-written bytes. Add to `Tests/MetricsTests.swift`:

```swift
        // MARK: Firefox bookmark reader against a fixture profile
        let firefoxFixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorssaint-firefox-fixture-\(UUID().uuidString)")
        let firefoxProfile = firefoxFixtureRoot.appendingPathComponent("abc123.default-release")
        try? FileManager.default.createDirectory(at: firefoxProfile, withIntermediateDirectories: true)
        try? """
        [Install4F96D1932A9F858E]
        Default=abc123.default-release
        """.write(to: firefoxFixtureRoot.appendingPathComponent("profiles.ini"),
                 atomically: true, encoding: .utf8)
        let dbPath = firefoxProfile.appendingPathComponent("places.sqlite").path
        let setupSQL = """
        CREATE TABLE moz_bookmarks (id INTEGER PRIMARY KEY, type INTEGER, fk INTEGER, parent INTEGER, title TEXT, guid TEXT);
        CREATE TABLE moz_places (id INTEGER PRIMARY KEY, url TEXT);
        INSERT INTO moz_bookmarks VALUES (1, 2, NULL, 0, 'root________', 'root________');
        INSERT INTO moz_bookmarks VALUES (2, 2, NULL, 1, 'toolbar', 'toolbar_____');
        INSERT INTO moz_places VALUES (100, 'https://vorssaint.example/');
        INSERT INTO moz_bookmarks VALUES (10, 1, 100, 2, 'Vorssaint', 'bk1');
        """
        let setupProcess = Process()
        setupProcess.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        setupProcess.arguments = [dbPath, setupSQL]
        try? setupProcess.run()
        setupProcess.waitUntilExit()
        let firefoxReader = CommandBarBookmarksFirefox(rootDirectory: firefoxFixtureRoot,
                                                        minimumReparseInterval: 0)
        firefoxReader.refreshIfNeeded(enabled: true)
        expect(firefoxReader.cachedBookmarks.count == 1, "the reader finds the one bookmark in the fixture")
        expect(firefoxReader.cachedBookmarks.first?.folder == "Bookmarks Toolbar",
               "its folder resolves to the toolbar's friendly name")
        try? FileManager.default.removeItem(at: firefoxFixtureRoot)
```

- [ ] **Step 4: Build and test**

Run: `./build.sh && ./build.sh --test`
Expected: SUCCESS

- [ ] **Step 5: Commit**

```bash
git add Sources/Vorssaint/Services/CommandBar/CommandBarBookmarksFirefox.swift Tests/MetricsTests.swift
git commit -m "feat(command-bar): add Firefox bookmark reader with mtime caching"
```

---

## Task 10: Wire Firefox bookmarks in, docs, close-out

**Files:**
- Modify: `Sources/Vorssaint/Services/CommandBar/CommandBarCatalog.swift`
- Modify: `Sources/Vorssaint/Services/CommandBar/CommandBarService.swift`
- Modify: `Sources/Vorssaint/UI/Settings/CommandBarSettings.swift`
- Modify: `docs/PRIVACY.md`

Follow Task 5's exact shape, substituted for Firefox:

- `CommandBarCatalog.firefoxBookmarkEntries(_:bar:)`, same construction as `chromeBookmarkEntries` but with `id: "firefoxbookmark.\(bookmark.id)"`, icon resolved via `InstalledApps.url(for: "org.mozilla.firefox")`, and bundle id `"org.mozilla.firefox"` in both the icon lookup and the `run` closure's `NSWorkspace.shared.open([url], withApplicationAt:...)` call.
- `build(...)`'s signature grows to `build(automationDenied:chromeBookmarks:firefoxBookmarks:)`, appending `firefoxBookmarkEntries(firefoxBookmarks, bar: bar)` after the Chrome line. Update Task 5's `rebuildCatalog()` call site to pass `firefoxBookmarks: firefoxBookmarks.cachedBookmarks` too.
- `CommandBarService` gains `private let firefoxBookmarks = CommandBarBookmarksFirefox()` beside the Chrome instance, and `reloadPreferenceCaches()` gains `firefoxBookmarks.refreshIfNeeded(enabled: isEnabled(.firefoxBookmarks))`.
- `CommandBarSettings.swift` gains the same not-installed caption pattern, checking `NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.mozilla.firefox") == nil` against `text.firefoxBookmarksNotInstalled`.
- `docs/PRIVACY.md` gains the same sentence shape as Task 6, naming Firefox and its own local profile files instead of Chrome's.

- [ ] **Step 1: Write all four edits above in full** (not abbreviated — copy Task 5's code blocks and substitute every Chrome-specific identifier, bundle id and string).

- [ ] **Step 2: Build and test**

Run: `./build.sh && ./build.sh --test`
Expected: SUCCESS

- [ ] **Step 3: Manual verification** — same checklist as Task 5 Step 5, against a real Firefox profile with at least one bookmark. Additionally: open the bar repeatedly while actively browsing in Firefox and confirm the bar stays responsive (verifying the minimum-reparse-interval guard from Task 9 actually prevents redundant SQLite reads — check via `Instruments` or simply that typing doesn't stutter).

- [ ] **Step 4: Commit**

```bash
git commit -am "feat(command-bar): search and open Firefox bookmarks"
git commit -am "docs(privacy): note the Command Bar's Firefox bookmarks read"
```

(Two commits, matching Task 5/6's split between feature and docs.)

---

## Task 11: Safari Command Bar source scaffolding + Full Disk Access wiring

**Files:**
- Modify: `Sources/Vorssaint/Services/CommandBar/CommandBarCatalog.swift`
- Modify: `Sources/Vorssaint/Services/CommandBar/CommandBarPreferences.swift`
- Modify: `Sources/Vorssaint/Services/CommandBar/CommandBarService.swift`
- Modify: `Sources/Vorssaint/UI/Settings/CommandBarSettings.swift`
- Modify: `Sources/Vorssaint/Core/CommandBarStrings.swift`
- Modify: `Sources/Vorssaint/Core/FeatureCatalog.swift:237` (`commandBar.permissions`)
- Modify: `Tests/MetricsTests.swift:17421` (pinned count, now 157 → 159)

Same procedure as Tasks 1 and 7: `CommandBarSource.safariBookmarks`, `idPrefix: "safaribookmark."`, `symbolName: "safari"` (a real SF Symbol, distinct from `.links`' `"bookmark"` and from the generic `"globe"` used for Chrome/Firefox). Extend `browseGroup`'s bookmark arm to `case .chromeBookmarks, .firefoxBookmarks, .safariBookmarks: return bar.kindBookmark`, and `kindLimits` gains `("safaribookmark.", 5)`.

Two new localized fields (all 13 languages): `sourceSafariBookmarks` and `safariBookmarksFDAReason` (e.g. `"Command Bar needs Full Disk Access to search your Safari bookmarks."` / translated). Safari has no profile concept, so it does not need a "not installed" caption in the same way — Safari ships with every Mac, so that state does not practically occur; skip it rather than adding a caption for a case that cannot happen (YAGNI).

In `Sources/Vorssaint/Core/FeatureCatalog.swift`, extend the `commandBar` case in `var permissions: [AppPermission]`:

```swift
        case .scrollInverter, .focusFollowsMouse, .smoothScroll, .mouseNavigation, .mouseButtonShortcuts, .middleClick,
             .keyboardDebounce, .textSnippets, .superKey, .dockClick, .windowMaximizer, .windowLayout,
             .autoQuit, .cleaningMode, .pastePlain, .radialMenu,
             // The bar reads other apps' menus and windows and types at the
             // caret, all of it through Accessibility. Its Safari bookmarks
             // source additionally reads a Full Disk Access-gated file when
             // that source is switched on.
             .commandBar:
            return [.accessibility, .fullDiskAccess]
```

(This follows `.uninstaller`'s own precedent at the same file, line 255, of listing `.fullDiskAccess` even though it is optional to that feature's core function.)

- [ ] **Step 1: Add the case, watch it fail, fix every switch and the FeatureCatalog permission list** — write out each one in full, same discipline as Tasks 1 and 7.

- [ ] **Step 2: Bump the pinned count** to `159`.

- [ ] **Step 3: Build and test**

Run: `./build.sh && ./build.sh --test`
Expected: SUCCESS

- [ ] **Step 4: Commit**

```bash
git commit -am "feat(command-bar): add Safari bookmarks source scaffolding"
```

---

## Task 12: Safari bookmark plist parsing (pure)

**Files:**
- Create: `Sources/Vorssaint/Services/CommandBar/CommandBarBookmarksSafariSupport.swift`
- Modify: `build.sh`
- Modify: `Tests/MetricsTests.swift`

**Interfaces:**
- Produces: `CommandBarBookmarksSafariSupport.ParsedBookmark { id, title, url, folder }`, `.SafariNode` (Decodable), `.flattenedBookmarks(from:) -> [ParsedBookmark]`. Task 13 is the only consumer.

- [ ] **Step 1: Write the failing tests**

```swift
        // MARK: Safari bookmark parsing
        let safariPlist: [String: Any] = [
            "WebBookmarkType": "WebBookmarkTypeList",
            "Title": "com.apple.ReadingList", // sibling roots would appear here too in real data;
            "Children": [
                [
                    "WebBookmarkType": "WebBookmarkTypeList",
                    "Title": "BookmarksBar",
                    "Children": [
                        [
                            "WebBookmarkType": "WebBookmarkTypeLeaf",
                            "WebBookmarkUUID": "u1",
                            "URLString": "https://vorssaint.example/",
                            "URIDictionary": ["title": "Vorssaint"],
                        ],
                        [
                            "WebBookmarkType": "WebBookmarkTypeLeaf",
                            "WebBookmarkUUID": "u2",
                            "URLString": "https://example.com/untitled",
                            "URIDictionary": [String: String](),
                        ],
                    ],
                ],
            ],
        ]
        let plistData = try? PropertyListSerialization.data(fromPropertyList: safariPlist,
                                                             format: .xml, options: 0)
        let decodedSafari = plistData.flatMap {
            try? PropertyListDecoder().decode(CommandBarBookmarksSafariSupport.SafariNode.self, from: $0)
        }
        expect(decodedSafari != nil, "well-formed Safari Bookmarks.plist decodes")
        if let root = decodedSafari {
            let flat = CommandBarBookmarksSafariSupport.flattenedBookmarks(from: root)
            expect(flat.count == 2, "both leaves are found under the nested root")
            expect(flat.contains { $0.id == "u1" && $0.title == "Vorssaint" && $0.folder == "Favourites" },
                   "BookmarksBar reads as the friendly name Safari itself shows: Favourites")
            expect(flat.contains { $0.id == "u2" && $0.title == "https://example.com/untitled" },
                   "a leaf with no URIDictionary title falls back to its own URL rather than a blank row")
        }
```

- [ ] **Step 2: Confirm failure**, then **Step 3: implement**:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Parsing Safari's own `Bookmarks.plist`. Pure: given an already-decoded
/// tree, produces a flat list. Reading the file (behind Full Disk Access)
/// lives in `CommandBarBookmarksSafari`, outside this test harness.
enum CommandBarBookmarksSafariSupport {
    struct ParsedBookmark: Equatable {
        let id: String
        let title: String
        let url: String
        let folder: String
    }

    struct SafariNode: Decodable {
        struct URIDictionary: Decodable {
            let title: String?
        }
        let webBookmarkType: String
        let webBookmarkUUID: String?
        let title: String?
        let children: [SafariNode]?
        let urlString: String?
        let uriDictionary: URIDictionary?

        private enum CodingKeys: String, CodingKey {
            case webBookmarkType = "WebBookmarkType"
            case webBookmarkUUID = "WebBookmarkUUID"
            case title = "Title"
            case children = "Children"
            case urlString = "URLString"
            case uriDictionary = "URIDictionary"
        }
    }

    /// Safari's own names for its fixed roots, matching what the app itself
    /// shows: the bookmarks bar reads as "Favourites", not its internal key.
    private static func friendlyRootName(_ rawTitle: String) -> String {
        switch rawTitle {
        case "BookmarksBar": return "Favourites"
        case "BookmarksMenu": return "Bookmarks Menu"
        case "com.apple.ReadingList": return "Reading List"
        default: return rawTitle
        }
    }

    static func flattenedBookmarks(from root: SafariNode) -> [ParsedBookmark] {
        var results: [ParsedBookmark] = []
        walk(root, path: [], into: &results)
        return results
    }

    private static func walk(_ node: SafariNode, path: [String], into results: inout [ParsedBookmark]) {
        if node.webBookmarkType == "WebBookmarkTypeLeaf" {
            guard let uuid = node.webBookmarkUUID, let url = node.urlString else { return }
            let title = node.uriDictionary?.title.flatMap { $0.isEmpty ? nil : $0 } ?? url
            results.append(ParsedBookmark(id: uuid, title: title, url: url,
                                          folder: path.joined(separator: "/")))
            return
        }
        guard node.webBookmarkType == "WebBookmarkTypeList", let children = node.children else { return }
        let ownName = node.title.map(friendlyRootName)
        let nextPath = ownName.map { path + [$0] } ?? path
        for child in children { walk(child, path: nextPath, into: &results) }
    }
}
```

- [ ] **Step 4: Confirm tests pass**, **Step 5: register in build.sh**, **Step 6: build and test**:

Run: `./build.sh && ./build.sh --test`
Expected: SUCCESS

- [ ] **Step 7: Commit**

```bash
git add Sources/Vorssaint/Services/CommandBar/CommandBarBookmarksSafariSupport.swift build.sh Tests/MetricsTests.swift
git commit -m "feat(command-bar): add Safari bookmark plist parsing"
```

---

## Task 13: Safari bookmark reader (FDA-gated, caching)

**Files:**
- Create: `Sources/Vorssaint/Services/CommandBar/CommandBarBookmarksSafari.swift`

**Interfaces:**
- Consumes: `CommandBarBookmarksSafariSupport.{ParsedBookmark, SafariNode, flattenedBookmarks}`, `CommandBarBookmarksSupport.{FileSignature, signature}`, `Permissions.shared.fullDiskAccess`.
- Produces: `final class CommandBarBookmarksSafari { init(plistPath: URL = <default>); var cachedBookmarks: [CommandBarBookmarksSafariSupport.ParsedBookmark]; func refreshIfNeeded(enabled: Bool) }`.

- [ ] **Step 1: Write the implementation**

Create `Sources/Vorssaint/Services/CommandBar/CommandBarBookmarksSafari.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Safari's own bookmarks, read from its plist. Gated on Full Disk Access,
/// same as the uninstaller's deeper scan — `Library/Safari` is already one
/// of `Permissions.fdaGatedDirectories`, so this is a new consumer of an
/// existing permission path, not a new one.
final class CommandBarBookmarksSafari {
    private(set) var cachedBookmarks: [CommandBarBookmarksSafariSupport.ParsedBookmark] = []
    private var lastSignature: String?
    private let plistPath: URL

    init(plistPath: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Safari/Bookmarks.plist")) {
        self.plistPath = plistPath
    }

    func refreshIfNeeded(enabled: Bool) {
        guard enabled, Permissions.shared.fullDiskAccess else {
            if lastSignature != nil || !cachedBookmarks.isEmpty {
                lastSignature = nil
                cachedBookmarks = []
            }
            return
        }
        guard let signatureFile = Self.fileSignature(plistPath.path) else {
            lastSignature = nil
            cachedBookmarks = []
            return
        }
        let signature = CommandBarBookmarksSupport.signature([signatureFile])
        guard signature != lastSignature else { return }
        lastSignature = signature
        cachedBookmarks = Self.parse(at: plistPath) ?? cachedBookmarks
    }

    private static func parse(at url: URL) -> [CommandBarBookmarksSafariSupport.ParsedBookmark]? {
        guard let data = try? Data(contentsOf: url),
              let root = try? PropertyListDecoder().decode(
                CommandBarBookmarksSafariSupport.SafariNode.self, from: data)
        else { return nil }
        return CommandBarBookmarksSafariSupport.flattenedBookmarks(from: root)
    }

    private static func fileSignature(_ path: String) -> CommandBarBookmarksSupport.FileSignature? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? Int,
              let modified = attributes[.modificationDate] as? Date
        else { return nil }
        return .init(path: path, size: size, modified: modified)
    }
}
```

- [ ] **Step 2: Add a temp-fixture behavioral test**

```swift
        // MARK: Safari bookmark reader against a fixture profile
        let safariFixtureDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorssaint-safari-fixture-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: safariFixtureDir, withIntermediateDirectories: true)
        let safariPlistPath = safariFixtureDir.appendingPathComponent("Bookmarks.plist")
        if let plistData {
            try? plistData.write(to: safariPlistPath)
        }
        let safariReader = CommandBarBookmarksSafari(plistPath: safariPlistPath)
        // This exercises the parsing path directly; it does not, and cannot,
        // exercise the Permissions.shared.fullDiskAccess gate itself, since
        // that reads real TCC state. Confirm the gate manually (Task 14).
        expect(Permissions.shared.fullDiskAccess == Permissions.shared.fullDiskAccess,
               "placeholder kept honest below — see the real check that follows")
```

Note: the fixture above cannot fully exercise `refreshIfNeeded` end-to-end, because it is gated on real `Permissions.shared.fullDiskAccess`, not an injectable flag. Rather than leave a fake assertion in place, restructure `refreshIfNeeded` to take the FDA state as a parameter instead of reading the singleton directly, which makes this genuinely testable and is a small, justified change:

```swift
    func refreshIfNeeded(enabled: Bool, fullDiskAccess: Bool = Permissions.shared.fullDiskAccess) {
        guard enabled, fullDiskAccess else {
```

Then replace the placeholder test above with a real one:

```swift
        safariReader.refreshIfNeeded(enabled: true, fullDiskAccess: false)
        expect(safariReader.cachedBookmarks.isEmpty, "no Full Disk Access means no bookmarks, even if enabled")
        safariReader.refreshIfNeeded(enabled: true, fullDiskAccess: true)
        expect(safariReader.cachedBookmarks.count == 2, "with access granted, the fixture's two bookmarks appear")
        try? FileManager.default.removeItem(at: safariFixtureDir)
```

(This reuses the `plistData` binding from Task 12's tests — confirm it is still in scope, or rebuild it locally in this block from `safariPlist` if the two `MARK` sections end up non-adjacent.)

Update Task 14's call site in `CommandBarService` to pass `fullDiskAccess: Permissions.shared.fullDiskAccess` explicitly, since the default parameter only covers call sites that don't specify it — being explicit there is clearer anyway.

- [ ] **Step 3: Build and test**

Run: `./build.sh && ./build.sh --test`
Expected: SUCCESS

- [ ] **Step 4: Commit**

```bash
git add Sources/Vorssaint/Services/CommandBar/CommandBarBookmarksSafari.swift Tests/MetricsTests.swift
git commit -m "feat(command-bar): add Safari bookmark reader with mtime caching"
```

---

## Task 14: Wire Safari bookmarks in, Settings FDA prompt, docs, close-out

**Files:**
- Modify: `Sources/Vorssaint/Services/CommandBar/CommandBarCatalog.swift`
- Modify: `Sources/Vorssaint/Services/CommandBar/CommandBarService.swift`
- Modify: `Sources/Vorssaint/UI/Settings/CommandBarSettings.swift`
- Modify: `docs/PERMISSIONS.md`
- Modify: `docs/PRIVACY.md`

- [ ] **Step 1: Catalog entry builder**

Same shape as `chromeBookmarkEntries`, with `id: "safaribookmark.\(bookmark.id)"`, icon via `InstalledApps.url(for: "com.apple.Safari")`, `NSWorkspace.shared.open([url], withApplicationAt:...)` targeting `"com.apple.Safari"`, and `isOfferableURL(bookmark.url, allowFileScheme: true)` in the `run` closure's guard (Safari's Reading List can carry local `file://` entries; Chrome and Firefox do not need `allowFileScheme: true`).

`build(...)`'s signature grows to its final form: `build(automationDenied:chromeBookmarks:firefoxBookmarks:safariBookmarks:)`.

- [ ] **Step 2: Service wiring**

```swift
    private let safariBookmarks = CommandBarBookmarksSafari()
```

```swift
    private func reloadPreferenceCaches() {
        pinCache = Set(pins)
        shortcutCache = rowShortcuts
        compactMode = UserDefaults.standard.bool(forKey: DefaultsKey.commandBarCompactMode)
        hasCustomPosition = positionOffset != .zero
        reloadFileSearchCaches()
        chromeBookmarks.refreshIfNeeded(enabled: isEnabled(.chromeBookmarks))
        firefoxBookmarks.refreshIfNeeded(enabled: isEnabled(.firefoxBookmarks))
        safariBookmarks.refreshIfNeeded(enabled: isEnabled(.safariBookmarks),
                                        fullDiskAccess: Permissions.shared.fullDiskAccess)
    }
```

`rebuildCatalog()`'s call to `CommandBarCatalog.build` gains `safariBookmarks: safariBookmarks.cachedBookmarks`.

- [ ] **Step 3: Settings FDA prompt**

In `CommandBarSettings.swift`, add a section below the sources `ForEach`, shown only when the Safari source is on and access is missing — following `FullDiskAccessNote`'s existing usage shape (e.g. `UninstallerView.swift:82`):

```swift
            if isEnabled(.safariBookmarks), !Permissions.shared.fullDiskAccess {
                Section {
                    FullDiskAccessNote(reason: text.safariBookmarksFDAReason)
                }
            }
```

(`isEnabled(_:)` here is `CommandBarService.shared.isEnabled(_:)` — check how the surrounding view already references the service, e.g. via `@ObservedObject var service = CommandBarService.shared`, and call it the same way rather than introducing a second way to read the same state.)

- [ ] **Step 4: Docs**

`docs/PERMISSIONS.md`'s Full Disk Access section (currently "what uses it: the uninstaller," around lines 15 and 101-103) gains a second row/sentence naming the Command Bar's Safari bookmarks source, in the same format as the existing uninstaller entry.

`docs/PRIVACY.md` gains a sentence in the same shape as Tasks 6 and 10, for Safari, additionally noting that this source only reads its file once Full Disk Access is granted.

- [ ] **Step 5: Build and test**

Run: `./build.sh && ./build.sh --test`
Expected: SUCCESS

- [ ] **Step 6: Manual verification**

- With Full Disk Access **not** granted: turn on the Safari Bookmarks toggle, confirm no rows appear and the FDA prompt shows in Settings with the bookmarks-specific reason text (not the uninstaller's default text).
- Grant Full Disk Access via the prompt's button, relaunch (the Relaunch button in `FullDiskAccessNote` does this), confirm Safari bookmarks now appear and search correctly.
- Confirm a Safari bookmark opens in Safari specifically.
- Confirm a Reading List `file://` entry, if you have one, still opens.
- Revoke Full Disk Access in System Settings, relaunch, confirm the source goes back to producing no rows without an error.

- [ ] **Step 7: Commit**

```bash
git commit -am "feat(command-bar): search and open Safari bookmarks"
git commit -am "docs: note the Command Bar's Full Disk Access use for Safari bookmarks"
```

---

## Self-Review Notes

- **Spec coverage:** every "Design decision" (1-5) in the spec has a corresponding task — profiles (Tasks 3-4, 8-9, 12-13), caching (Tasks 4, 9, 13), browser-symbol icons (corrected in Task 5 to `.appIcon(path:)`, more reusable than the spec's literal "SF Symbol" phrasing — see Global Constraints note), open-in-origin-browser with fallback (Tasks 5, 10, 14), per-browser toggles (Tasks 1, 7, 11). Every "Repo conventions" item in the spec (localization, docs, exhaustive switches, test registration, PR size/split) is addressed by name in the tasks that touch it.
- **Placeholder scan:** the one near-miss was Task 13's first draft of the fixture test, which would have shipped a test that always passes (`x == x`) — caught and replaced with a real parameterized check during writing, not left in.
- **Type consistency:** `ParsedBookmark` is a distinct type per browser (`CommandBarBookmarksChromeSupport.ParsedBookmark`, `...FirefoxSupport.ParsedBookmark`, `...SafariSupport.ParsedBookmark`) rather than one shared struct, because each reader is the only consumer of its own type and there is no cross-browser code that needs them to be interchangeable — introducing a shared `ParsedBookmark` type now would be exactly the "abstract before two settled cases actually need it" the spec itself warns against. `CommandBarCatalog.build(...)`'s signature is threaded consistently across Tasks 5, 10 and 14, each adding one parameter without renaming the ones already there.
