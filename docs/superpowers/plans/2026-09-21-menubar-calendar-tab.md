# Menu Bar Calendar Tab (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Calendar" tile to Vorssaint's menu bar panel — a month grid with per-day event dots and a day-filterable upcoming-events agenda, reading EventKit directly — as a full replacement for Itsycal, independent of the existing (actively-developed) Dynamic Island calendar feature.

**Architecture:** A new, self-contained `Calendar` module (own EventKit reader, own event/color types, own SwiftUI views) registered into the app's existing feature-catalog/panel-tile/settings-page machinery the same way Port Manager and Command Bar already are. No code is shared with or extracted from `NotchCalendarService`/`NotchCalendarSupport`/`NotchCalendarView` — see the spec's "Why a new, independent module" section for why.

**Tech Stack:** Swift, SwiftUI, EventKit, Combine (for `AnyCancellable`), the repo's own hand-rolled test harness (`TestSuite`/`suite.expect`), built via `swiftc` through `build.sh` (no SwiftPM test target).

**Spec:** `docs/superpowers/specs/2026-09-21-menubar-calendar-view-design.md` (as revised after the DeepSeek v4.1 review — read it alongside this plan; this plan does not repeat its rationale, only its decisions).

## Global Constraints

- **Localization is compiler-enforced.** Every new user-facing string is a field on a `*FeatureStrings` struct with a value in all 13 shipped languages (`enUS, ptBR, tr, ru, es, de, fr, it, ja, ko, zhHans, zhTW, zhHK`) before the project compiles.
- **No code is shared with the Notch calendar files** (`NotchCalendarService.swift`, `NotchCalendarSupport.swift`, `NotchCalendarView.swift`) — this feature's own files may be *structured* the same way, but never import from or edit those files (Design decision #1 in the spec).
- **`id` on `CalendarEvent` must incorporate the occurrence start** (`eventIdentifier + ":" + start.timeIntervalSinceReferenceDate`), never `eventIdentifier` alone — a recurring series shares one identifier across occurrences.
- **`color` on `CalendarEvent` is a `Sendable` value type** (`CalendarColor`, sRGB components), never `NSColor` — it crosses the `CalendarReader` actor boundary into `@Published` state and must have reliable equality for the ≤3-dot dedup.
- **`notes` and `url` are NOT captured in this phase** (Design decision #4) — do not add these fields to `CalendarEvent` in this plan; Phase 2 adds them when it needs them.
- **Every registered feature change is additive** to the shared catalog files (`FeatureCatalog.swift`, `Defaults.swift`, etc.) — never reorder or rename an existing `AppFeature` case, `DefaultsKey`, or `SettingsPage` case.
- Build/verify commands: `swift build` (debug compile check) and `./build.sh --test` (full compile + the hand-written test suite + `PreferenceCleanupTests.sh`) from the repo root.

---

### Task 1: Calendar feature strings (13 languages)

**Files:**
- Create: `Sources/Vorssaint/Core/CalendarStrings.swift`

**Interfaces:**
- Produces: `struct CalendarFeatureStrings` with fields `title, panelCaption, calendarsListTitle, hideCalendarHint, hubDescription, permission, allow, denied, settings, requestFailed, empty, today, allDay, untitled, openCalendar, previousMonth, nextMonth` (all `String`); `FeatureStrings.calendar(_ language: AppLanguage) -> CalendarFeatureStrings`. Every later task that shows UI text calls `FeatureStrings.calendar(l10n.language)`.

No test step — this file is data, not logic (matches how `PortManagerStrings.swift` and every other `*Strings.swift` file in this repo has no dedicated test; correctness here is "it compiles with all 13 cases handled," which the exhaustive `switch` enforces).

- [ ] **Step 1: Write the strings file**

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

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
}

extension FeatureStrings {
    static func calendar(_ language: AppLanguage) -> CalendarFeatureStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

extension CalendarFeatureStrings {
    static let enUS = CalendarFeatureStrings(title: "Calendar", panelCaption: "Browse your calendar and upcoming events", calendarsListTitle: "Calendars", hideCalendarHint: "Calendars hidden here are removed from the grid and agenda, not from Calendar itself.", hubDescription: "Browse a month view and your upcoming appointments from the menu bar panel.", permission: "Read your calendars to show upcoming appointments. Events stay on this Mac.", allow: "Allow Calendar Access", denied: "Allow calendar access in System Settings to see your appointments.", settings: "Open System Settings", requestFailed: "Could not request calendar access. Please try again.", empty: "No upcoming appointments", today: "Today", allDay: "All day", untitled: "Untitled event", openCalendar: "Open Calendar", previousMonth: "Previous month", nextMonth: "Next month")
    static let ptBR = CalendarFeatureStrings(title: "Calendário", panelCaption: "Veja seu calendário e próximos compromissos", calendarsListTitle: "Calendários", hideCalendarHint: "Calendários ocultados aqui são removidos da grade e da agenda, não do app Calendário em si.", hubDescription: "Veja uma visão mensal e seus próximos compromissos no painel da barra de menus.", permission: "Leia seus calendários para mostrar os próximos compromissos. Os eventos ficam neste Mac.", allow: "Permitir acesso ao calendário", denied: "Permita o acesso ao calendário nos Ajustes do Sistema para ver seus compromissos.", settings: "Abrir Ajustes do Sistema", requestFailed: "Não foi possível pedir acesso ao calendário. Tente novamente.", empty: "Nenhum compromisso por enquanto", today: "Hoje", allDay: "Dia inteiro", untitled: "Evento sem título", openCalendar: "Abrir calendário", previousMonth: "Mês anterior", nextMonth: "Próximo mês")
    static let tr = CalendarFeatureStrings(title: "Takvim", panelCaption: "Takviminizi ve yaklaşan randevularınızı görüntüleyin", calendarsListTitle: "Takvimler", hideCalendarHint: "Burada gizlenen takvimler, ızgara ve gündemden kaldırılır; Takvim uygulamasından kaldırılmaz.", hubDescription: "Menü çubuğu panelinden aylık görünümü ve yaklaşan randevularınızı görüntüleyin.", permission: "Yaklaşan randevuları göstermek için takvimlerinizi okur. Etkinlikler bu Mac'te kalır.", allow: "Takvim Erişimine İzin Ver", denied: "Randevularınızı görmek için Sistem Ayarları'nda takvim erişimine izin verin.", settings: "Sistem Ayarları'nı Aç", requestFailed: "Takvim erişimi istenemedi. Tekrar deneyin.", empty: "Yaklaşan randevu yok", today: "Bugün", allDay: "Tüm gün", untitled: "Başlıksız etkinlik", openCalendar: "Takvimi Aç", previousMonth: "Önceki ay", nextMonth: "Sonraki ay")
    static let ru = CalendarFeatureStrings(title: "Календарь", panelCaption: "Просмотр календаря и предстоящих встреч", calendarsListTitle: "Календари", hideCalendarHint: "Скрытые здесь календари удаляются из сетки и повестки дня, но не из самого приложения «Календарь».", hubDescription: "Просмотр месяца и предстоящих встреч в панели строки меню.", permission: "Чтение календарей для показа предстоящих встреч. События остаются на этом Mac.", allow: "Разрешить доступ к календарю", denied: "Разрешите доступ к календарю в Системных настройках, чтобы видеть встречи.", settings: "Открыть Системные настройки", requestFailed: "Не удалось запросить доступ к календарю. Повторите попытку.", empty: "Предстоящих встреч нет", today: "Сегодня", allDay: "Весь день", untitled: "Событие без названия", openCalendar: "Открыть Календарь", previousMonth: "Предыдущий месяц", nextMonth: "Следующий месяц")
    static let es = CalendarFeatureStrings(title: "Calendario", panelCaption: "Consulta tu calendario y tus próximas citas", calendarsListTitle: "Calendarios", hideCalendarHint: "Los calendarios ocultos aquí se eliminan de la cuadrícula y la agenda, no de la app Calendario.", hubDescription: "Consulta una vista mensual y tus próximas citas desde el panel de la barra de menús.", permission: "Lee tus calendarios para mostrar las próximas citas. Los eventos se quedan en este Mac.", allow: "Permitir acceso al calendario", denied: "Permite el acceso al calendario en Ajustes del Sistema para ver tus citas.", settings: "Abrir Ajustes del Sistema", requestFailed: "No se pudo solicitar acceso al calendario. Inténtalo de nuevo.", empty: "No hay próximas citas", today: "Hoy", allDay: "Todo el día", untitled: "Evento sin título", openCalendar: "Abrir Calendario", previousMonth: "Mes anterior", nextMonth: "Mes siguiente")
    static let de = CalendarFeatureStrings(title: "Kalender", panelCaption: "Kalender und anstehende Termine durchsehen", calendarsListTitle: "Kalender", hideCalendarHint: "Hier ausgeblendete Kalender werden aus dem Raster und der Agenda entfernt, nicht aus Kalender selbst.", hubDescription: "Monatsansicht und anstehende Termine im Menüleisten-Panel durchsehen.", permission: "Liest deine Kalender, um kommende Termine anzuzeigen. Die Ereignisse bleiben auf diesem Mac.", allow: "Kalenderzugriff erlauben", denied: "Erlaube den Kalenderzugriff in den Systemeinstellungen, um deine Termine zu sehen.", settings: "Systemeinstellungen öffnen", requestFailed: "Der Kalenderzugriff konnte nicht angefordert werden. Versuche es erneut.", empty: "Keine anstehenden Termine", today: "Heute", allDay: "Ganztägig", untitled: "Ereignis ohne Titel", openCalendar: "Kalender öffnen", previousMonth: "Vorheriger Monat", nextMonth: "Nächster Monat")
    static let fr = CalendarFeatureStrings(title: "Calendrier", panelCaption: "Consultez votre calendrier et vos prochains rendez-vous", calendarsListTitle: "Calendriers", hideCalendarHint: "Les calendriers masqués ici sont retirés de la grille et de l'agenda, pas de l'app Calendrier elle-même.", hubDescription: "Consultez une vue mensuelle et vos prochains rendez-vous depuis le panneau de la barre des menus.", permission: "Lit vos calendriers pour afficher les prochains rendez-vous. Les événements restent sur ce Mac.", allow: "Autoriser l'accès au calendrier", denied: "Autorisez l'accès au calendrier dans les Réglages Système pour voir vos rendez-vous.", settings: "Ouvrir les Réglages Système", requestFailed: "Impossible de demander l'accès au calendrier. Réessayez.", empty: "Aucun rendez-vous à venir", today: "Aujourd'hui", allDay: "Toute la journée", untitled: "Événement sans titre", openCalendar: "Ouvrir Calendrier", previousMonth: "Mois précédent", nextMonth: "Mois suivant")
    static let it = CalendarFeatureStrings(title: "Calendario", panelCaption: "Consulta il calendario e i prossimi appuntamenti", calendarsListTitle: "Calendari", hideCalendarHint: "I calendari nascosti qui vengono rimossi dalla griglia e dall'agenda, non dall'app Calendario stessa.", hubDescription: "Consulta una vista mensile e i tuoi prossimi appuntamenti dal pannello della barra dei menu.", permission: "Legge i calendari per mostrare i prossimi appuntamenti. Gli eventi restano su questo Mac.", allow: "Consenti accesso al calendario", denied: "Consenti l'accesso al calendario in Impostazioni di Sistema per vedere gli appuntamenti.", settings: "Apri Impostazioni di Sistema", requestFailed: "Impossibile richiedere l'accesso al calendario. Riprova.", empty: "Nessun appuntamento in programma", today: "Oggi", allDay: "Tutto il giorno", untitled: "Evento senza titolo", openCalendar: "Apri Calendario", previousMonth: "Mese precedente", nextMonth: "Mese successivo")
    static let ja = CalendarFeatureStrings(title: "カレンダー", panelCaption: "カレンダーと今後の予定を確認", calendarsListTitle: "カレンダー", hideCalendarHint: "ここで非表示にしたカレンダーは、グリッドとアジェンダから外れるだけで、カレンダーApp自体からは削除されません。", hubDescription: "メニューバーパネルから月表示と今後の予定を確認できます。", permission: "カレンダーを読み取り、今後の予定を表示します。予定の情報はこのMacに保持されます。", allow: "カレンダーへのアクセスを許可", denied: "予定を表示するには、システム設定でカレンダーへのアクセスを許可してください。", settings: "システム設定を開く", requestFailed: "カレンダーへのアクセスを要求できませんでした。もう一度お試しください。", empty: "今後の予定はありません", today: "今日", allDay: "終日", untitled: "名称未設定の予定", openCalendar: "カレンダーを開く", previousMonth: "前の月", nextMonth: "次の月")
    static let ko = CalendarFeatureStrings(title: "캘린더", panelCaption: "캘린더와 다가오는 일정 보기", calendarsListTitle: "캘린더", hideCalendarHint: "여기서 숨긴 캘린더는 그리드와 일정 목록에서만 제외되며, 캘린더 앱 자체에서 삭제되지는 않습니다.", hubDescription: "메뉴 막대 패널에서 월별 보기와 다가오는 일정을 확인하세요.", permission: "다가오는 일정을 표시하기 위해 캘린더를 읽습니다. 일정은 이 Mac에만 보관됩니다.", allow: "캘린더 접근 허용", denied: "일정을 보려면 시스템 설정에서 캘린더 접근을 허용하세요.", settings: "시스템 설정 열기", requestFailed: "캘린더 접근을 요청할 수 없습니다. 다시 시도하세요.", empty: "예정된 일정 없음", today: "오늘", allDay: "하루 종일", untitled: "제목 없는 일정", openCalendar: "캘린더 열기", previousMonth: "이전 달", nextMonth: "다음 달")
    static let zhHans = CalendarFeatureStrings(title: "日历", panelCaption: "浏览日历和即将开始的日程", calendarsListTitle: "日历", hideCalendarHint: "在此隐藏的日历只会从网格和日程列表中移除，不会影响日历App本身。", hubDescription: "在菜单栏面板中浏览月视图和即将开始的日程。", permission: "读取日历以显示即将开始的日程。日程信息仅保留在此 Mac 上。", allow: "允许访问日历", denied: "请在系统设置中允许访问日历，以查看日程。", settings: "打开系统设置", requestFailed: "无法请求日历访问权限，请重试。", empty: "暂无即将开始的日程", today: "今天", allDay: "全天", untitled: "无标题日程", openCalendar: "打开日历", previousMonth: "上个月", nextMonth: "下个月")
    static let zhTW = CalendarFeatureStrings(title: "行事曆", panelCaption: "瀏覽行事曆與即將到來的行程", calendarsListTitle: "行事曆", hideCalendarHint: "在此隱藏的行事曆只會從方格與行程列表中移除，不會影響行事曆App本身。", hubDescription: "在選單列面板中瀏覽月檢視與即將到來的行程。", permission: "讀取行事曆以顯示即將到來的行程。行程資訊僅保留在這部 Mac 上。", allow: "允許取用行事曆", denied: "請在系統設定中允許取用行事曆，以查看行程。", settings: "打開系統設定", requestFailed: "無法要求行事曆取用權限，請再試一次。", empty: "沒有即將到來的行程", today: "今天", allDay: "整天", untitled: "未命名行程", openCalendar: "打開行事曆", previousMonth: "上個月", nextMonth: "下個月")
    static let zhHK = CalendarFeatureStrings(title: "日曆", panelCaption: "瀏覽日曆與即將到來的行程", calendarsListTitle: "日曆", hideCalendarHint: "在此隱藏的日曆只會從方格與行程列表中移除，不會影響日曆App本身。", hubDescription: "在選單列面板中瀏覽月檢視與即將到來的行程。", permission: "讀取日曆以顯示即將到來的行程。行程資料只保留在此 Mac 上。", allow: "允許取用日曆", denied: "請在系統設定中允許取用日曆，以查看行程。", settings: "開啟系統設定", requestFailed: "無法要求日曆取用權限，請重試。", empty: "沒有即將到來的行程", today: "今天", allDay: "全天", untitled: "未命名行程", openCalendar: "開啟日曆", previousMonth: "上個月", nextMonth: "下個月")
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build 2>&1 | tail -30`
Expected: no errors mentioning `CalendarStrings.swift` (unrelated pre-existing warnings, if any, are fine).

- [ ] **Step 3: Commit**

```bash
git add Sources/Vorssaint/Core/CalendarStrings.swift
git commit -m "feat(calendar): add localized strings for the menu bar calendar tab"
```

---

### Task 2: Defaults keys

**Files:**
- Modify: `Sources/Vorssaint/Core/Defaults.swift`

**Interfaces:**
- Produces: `DefaultsKey.panelUtilityCalendar` (String key, registered default `true`), `DefaultsKey.calendarHiddenCalendarIDs` (String key, registered default `[String]()`). Later tasks (`CalendarService`, `CalendarSettings`, `MenuPanelView`) read/write these via `UserDefaults.standard`.

No test step — these are plain constant declarations; their effect is verified indirectly once something reads them (Tasks 5, 8, 12).

- [ ] **Step 1: Add the key declarations**

In `Sources/Vorssaint/Core/Defaults.swift`, find this existing line (around line 504):

```swift
    static let windowPreviewExcludedApps = "windowPreviewExcludedApps" // pause thumbnail capture while these apps are in front
```

Add a new key right after it:

```swift
    static let windowPreviewExcludedApps = "windowPreviewExcludedApps" // pause thumbnail capture while these apps are in front
    static let calendarHiddenCalendarIDs = "calendarHiddenCalendarIDs" // EKCalendar.calendarIdentifier values hidden from the menu bar Calendar tile
```

Then find the existing `panelUtilityPortManager` declaration (around line 645):

```swift
    static let panelUtilityPortManager = "panelUtilityPortManager"
```

Add a new key right after it:

```swift
    static let panelUtilityPortManager = "panelUtilityPortManager"
    static let panelUtilityCalendar = "panelUtilityCalendar"
```

- [ ] **Step 2: Register the defaults**

Find the existing `DefaultsKey.windowPreviewExcludedApps: [String](),` entry in the `registeredDefaults` dictionary (around line 1436) and add a matching entry right after it:

```swift
        DefaultsKey.windowPreviewExcludedApps: [String](),
        DefaultsKey.calendarHiddenCalendarIDs: [String](),
```

Find the existing `DefaultsKey.panelUtilityPortManager: true,` entry (around line 1503) and add a matching entry right after it:

```swift
        DefaultsKey.panelUtilityPortManager: true,
        DefaultsKey.panelUtilityCalendar: true,
```

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build 2>&1 | tail -30`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add Sources/Vorssaint/Core/Defaults.swift
git commit -m "feat(calendar): add DefaultsKeys for the panel tile and hidden-calendar list"
```

---

### Task 3: Core data model, month grid, dot colors, dedup — with tests

**Files:**
- Create: `Sources/Vorssaint/Services/Calendar/CalendarSupport.swift`
- Create: `Tests/CalendarFeatureTests.swift`
- Modify: `Tests/MetricsTests.swift`

**Interfaces:**
- Produces: `struct CalendarColor: Equatable, Sendable { red, green, blue: Double }` with `static let fallback`; `struct CalendarEvent: Identifiable, Equatable, Sendable { id, calendarItemIdentifier, title, calendarID, calendarTitle: String; color: CalendarColor; start, end: Date; allDay: Bool; location: String; recurring: Bool }`; `enum CalendarSupport` with `static func monthDays(containing:calendar:) -> [Date]` and `static func dotColors(on:events:calendar:) -> [CalendarColor]?`. Task 4 adds more members to the same `CalendarSupport` enum and the same test file. Task 5 (`CalendarService`) constructs `CalendarEvent` values using this exact field list and order.
- Consumes: nothing from earlier tasks.

- [ ] **Step 1: Write the failing tests**

Create `Tests/CalendarFeatureTests.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum CalendarFeatureTests {
    static func run(_ suite: TestSuite) {
        // MARK: Month grid

        let mid = DateComponents(calendar: .current, year: 2026, month: 9, day: 15).date!
        let days = CalendarSupport.monthDays(containing: mid)
        suite.expect(days.count == 42, "the month grid always returns 6 full weeks")
        suite.expect(Calendar.current.isDate(days[Calendar.current.firstWeekday == 1 ? 1 : 0], equalTo: mid, toGranularity: .month) == false
                || days.contains(where: { Calendar.current.isDate($0, equalTo: mid, toGranularity: .month) }),
               "the grid includes the requested month's own days")

        // MARK: Dot colors

        func makeEvent(id: String, color: CalendarColor, start: Date, end: Date) -> CalendarEvent {
            CalendarEvent(id: id, calendarItemIdentifier: id, title: "Event", calendarID: "cal",
                         calendarTitle: "Cal", color: color, start: start, end: end,
                         allDay: false, location: "", recurring: false)
        }

        let day = Calendar.current.startOfDay(for: Date())
        let red = CalendarColor(red: 1, green: 0, blue: 0)
        let blue = CalendarColor(red: 0, green: 0, blue: 1)
        let sameColorEvents = [
            makeEvent(id: "a", color: red, start: day, end: day.addingTimeInterval(3600)),
            makeEvent(id: "b", color: red, start: day.addingTimeInterval(7200), end: day.addingTimeInterval(9000)),
        ]
        suite.expect(CalendarSupport.dotColors(on: day, events: sameColorEvents) == [red],
               "two events sharing one calendar's color produce a single dot, not two")
        suite.expect(CalendarSupport.dotColors(on: day, events: sameColorEvents + [
            makeEvent(id: "c", color: blue, start: day.addingTimeInterval(10000), end: day.addingTimeInterval(11000)),
        ]) == [red, blue], "distinct calendar colors each get their own dot")
        suite.expect(CalendarSupport.dotColors(on: day, events: []) == nil,
               "a day with no events has no dots")
        suite.expect(CalendarSupport.dotColors(on: day, events: [
            makeEvent(id: "out", color: red,
                     start: day.addingTimeInterval(-7200), end: day.addingTimeInterval(-3600)),
        ]) == nil, "an event entirely on a different day contributes no dot")
    }
}
```

- [ ] **Step 2: Register the new suite so it runs, and confirm it fails to compile**

In `Tests/MetricsTests.swift`, find the `groups` array (starts around line 12) and add a new entry. Insert it right after the `("clipboard", ...)` entry:

```swift
            ("clipboard", { ClipboardFeatureTests.run(suite) }),
            ("calendar", { CalendarFeatureTests.run(suite) }),
```

Run: `./build.sh --test 2>&1 | tail -30`
Expected: FAIL to compile — `CalendarSupport`, `CalendarColor`, and `CalendarEvent` do not exist yet.

- [ ] **Step 3: Write the implementation**

Create `Sources/Vorssaint/Services/Calendar/CalendarSupport.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import EventKit

struct CalendarColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    static let fallback = Self(red: 0.35, green: 0.65, blue: 1)
}

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

enum CalendarSupport {
    static func monthDays(containing date: Date, calendar: Calendar = .current) -> [Date] {
        guard let month = calendar.dateInterval(of: .month, for: date) else { return [] }
        let offset = (calendar.component(.weekday, from: month.start) - calendar.firstWeekday + 7) % 7
        guard let start = calendar.date(byAdding: .day, value: -offset, to: month.start) else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// Up to 3 distinct calendar colors for the events on `day`; nil when
    /// there are none. Events sharing one calendar's color count once.
    static func dotColors(on day: Date, events: [CalendarEvent],
                          calendar: Calendar = .current) -> [CalendarColor]? {
        guard let interval = calendar.dateInterval(of: .day, for: day) else { return nil }
        var result: [CalendarColor] = []
        for event in events where event.start < interval.end && event.end > interval.start {
            if !result.contains(event.color) { result.append(event.color) }
            if result.count == 3 { break }
        }
        return result.isEmpty ? nil : result
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./build.sh --test 2>&1 | tail -30`
Expected: `calendar: OK (N checks, ...)` among the suite output, `TESTS OK`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Vorssaint/Services/Calendar/CalendarSupport.swift Tests/CalendarFeatureTests.swift Tests/MetricsTests.swift
git commit -m "feat(calendar): add CalendarEvent model, month grid math, and dot-color dedup"
```

---

### Task 4: Agenda grouping, fetch window, Calendar.app deep link — with tests

**Files:**
- Modify: `Sources/Vorssaint/Services/Calendar/CalendarSupport.swift`
- Modify: `Tests/CalendarFeatureTests.swift`

**Interfaces:**
- Consumes: `CalendarEvent`, `CalendarColor`, `CalendarSupport.monthDays` from Task 3.
- Produces (added to `enum CalendarSupport`): `static func events(_ events: [CalendarEvent], on day: Date, calendar: Calendar = .current) -> [CalendarEvent]`; `static func ordered(_ events: [CalendarEvent]) -> [CalendarEvent]`; `static func upcomingGroups(_ events: [CalendarEvent], from: Date, days: Int = 30, calendar: Calendar = .current) -> [(day: Date, events: [CalendarEvent])]`; `static func fetchInterval(visibleMonth: Date?, now: Date, lookaheadDays: Int = 30, calendar: Calendar = .current) -> DateInterval`; `static func isEnabled(in defaults: UserDefaults = .standard) -> Bool`; `static func eventURL(_ event: CalendarEvent, calendar: Calendar = .current) -> URL?`; `static func nextRefresh(_ events: [CalendarEvent], now: Date, calendar: Calendar = .current) -> Date`. Task 5 (`CalendarService`) calls `ordered`, `fetchInterval`, `nextRefresh`, `isEnabled`. Tasks 10-11 (grid/agenda views) call `events`, `upcomingGroups`, `eventURL`.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/CalendarFeatureTests.swift`, inside `run(_:)`, after the existing dot-color assertions:

```swift
        // MARK: Recurring-occurrence identity

        let seriesStart1 = day
        let seriesStart2 = day.addingTimeInterval(86400)
        let occurrence1 = CalendarEvent(id: "series:\(seriesStart1.timeIntervalSinceReferenceDate)",
                                        calendarItemIdentifier: "series", title: "Standup",
                                        calendarID: "cal", calendarTitle: "Cal", color: .fallback,
                                        start: seriesStart1, end: seriesStart1.addingTimeInterval(1800),
                                        allDay: false, location: "", recurring: true)
        let occurrence2 = CalendarEvent(id: "series:\(seriesStart2.timeIntervalSinceReferenceDate)",
                                        calendarItemIdentifier: "series", title: "Standup",
                                        calendarID: "cal", calendarTitle: "Cal", color: .fallback,
                                        start: seriesStart2, end: seriesStart2.addingTimeInterval(1800),
                                        allDay: false, location: "", recurring: true)
        let orderedOccurrences = CalendarSupport.ordered([occurrence1, occurrence2])
        suite.expect(orderedOccurrences.count == 2 && occurrence1.id != occurrence2.id,
               "two occurrences of the same recurring series keep distinct ids and both survive dedup")
        suite.expect(CalendarSupport.ordered([occurrence1, occurrence1]).count == 1,
               "the exact same occurrence appearing twice collapses to one")

        // MARK: Agenda grouping

        let allDayEvent = CalendarEvent(id: "allday", calendarItemIdentifier: "allday", title: "Holiday",
                                        calendarID: "cal", calendarTitle: "Cal", color: .fallback,
                                        start: day, end: Calendar.current.date(byAdding: .day, value: 1, to: day)!,
                                        allDay: true, location: "", recurring: false)
        let timedEvent = CalendarEvent(id: "timed", calendarItemIdentifier: "timed", title: "Meeting",
                                       calendarID: "cal", calendarTitle: "Cal", color: .fallback,
                                       start: day.addingTimeInterval(3600 * 10),
                                       end: day.addingTimeInterval(3600 * 11),
                                       allDay: false, location: "", recurring: false)
        let groups = CalendarSupport.upcomingGroups([allDayEvent, timedEvent], from: day)
        suite.expect(groups.first?.day == day && groups.first?.events.count == 2,
               "today's group includes both the all-day and timed events")
        suite.expect(groups.allSatisfy { !$0.events.isEmpty },
               "upcomingGroups never emits an empty day")
        suite.expect(CalendarSupport.events([allDayEvent, timedEvent], on: day).first?.id == allDayEvent.id,
               "within a day, the all-day event sorts before timed events")

        // MARK: Fetch interval

        let noMonth = CalendarSupport.fetchInterval(visibleMonth: nil, now: day, lookaheadDays: 30)
        suite.expect(noMonth.start == day, "with the panel closed, the fetch starts today")
        suite.expect(Calendar.current.dateComponents([.day], from: noMonth.start, to: noMonth.end).day == 30,
               "with the panel closed, the fetch covers exactly the lookahead window")
        let withMonth = CalendarSupport.fetchInterval(visibleMonth: day, now: day, lookaheadDays: 30)
        suite.expect(withMonth.start <= day && withMonth.end >= noMonth.end,
               "a visible month's range is unioned with, never narrower than, the lookahead window")

        // MARK: Calendar.app deep link

        let nonRecurring = CalendarEvent(id: "e1", calendarItemIdentifier: "item-1", title: "One-off",
                                         calendarID: "cal", calendarTitle: "Cal", color: .fallback,
                                         start: day, end: day.addingTimeInterval(1800),
                                         allDay: false, location: "", recurring: false)
        suite.expect(CalendarSupport.eventURL(nonRecurring)?.absoluteString
                == "ical://ekevent/item-1?method=show&options=more",
               "a non-recurring event links straight to its item identifier")
        suite.expect(CalendarSupport.eventURL(occurrence1)?.absoluteString.hasPrefix("ical://ekevent/") == true
                && CalendarSupport.eventURL(occurrence1)?.absoluteString.contains("/series?method=show") == true,
               "a recurring event's link includes its occurrence start before the item identifier")
        let noIdentifier = CalendarEvent(id: "e3", calendarItemIdentifier: "", title: "",
                                         calendarID: "cal", calendarTitle: "Cal", color: .fallback,
                                         start: day, end: day, allDay: false, location: "", recurring: false)
        suite.expect(CalendarSupport.eventURL(noIdentifier) == nil,
               "an event with no calendar item identifier has no deep link")

        // MARK: Next refresh

        suite.expect(CalendarSupport.nextRefresh([timedEvent], now: day) <= timedEvent.start,
               "the next refresh fires no later than the next event's own start")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./build.sh --test 2>&1 | tail -30`
Expected: FAIL to compile — `events`, `ordered`, `upcomingGroups`, `fetchInterval`, `eventURL`, and `nextRefresh` do not exist yet.

- [ ] **Step 3: Write the implementation**

Append to `Sources/Vorssaint/Services/Calendar/CalendarSupport.swift`, inside `enum CalendarSupport`:

```swift
    /// End dates are exclusive, including all-day events and midnight boundaries.
    static func events(_ events: [CalendarEvent], on day: Date,
                       calendar: Calendar = .current) -> [CalendarEvent] {
        guard let interval = calendar.dateInterval(of: .day, for: day) else { return [] }
        return events.filter { $0.start < interval.end && $0.end > interval.start }.sorted {
            if $0.allDay != $1.allDay { return $0.allDay }
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.id < $1.id
        }
    }

    /// Drops invalid ranges and duplicate ids. Recurring occurrences share a
    /// series identifier but not a start, so this only ever collapses a
    /// genuine repeat, never two different occurrences.
    static func ordered(_ events: [CalendarEvent]) -> [CalendarEvent] {
        var seen = Set<String>()
        return events.filter {
            $0.start.timeIntervalSinceReferenceDate.isFinite
                && $0.end.timeIntervalSinceReferenceDate.isFinite
                && $0.end > $0.start && seen.insert($0.id).inserted
        }.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.end != $1.end { return $0.end < $1.end }
            return $0.id < $1.id
        }
    }

    /// Groups events into consecutive days starting at `from`, skipping
    /// empty days.
    static func upcomingGroups(_ events: [CalendarEvent], from: Date, days: Int = 30,
                               calendar: Calendar = .current) -> [(day: Date, events: [CalendarEvent])] {
        let today = calendar.startOfDay(for: from)
        let ordered = ordered(events)
        return (0..<days).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
            .map { day in (day: day, events: CalendarSupport.events(ordered, on: day, calendar: calendar)) }
            .filter { !$0.events.isEmpty }
    }

    /// The window CalendarService fetches: always the lookahead the agenda
    /// needs, unioned with whichever month the grid currently shows (if
    /// any) so panel navigation and background refresh never contradict.
    static func fetchInterval(visibleMonth: Date?, now: Date, lookaheadDays: Int = 30,
                              calendar: Calendar = .current) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        let lookaheadEnd = calendar.date(byAdding: .day, value: lookaheadDays, to: today) ?? now
        guard let month = visibleMonth else { return DateInterval(start: today, end: lookaheadEnd) }
        let days = monthDays(containing: month, calendar: calendar)
        guard let first = days.first, let last = days.last,
              let monthEnd = calendar.date(byAdding: .day, value: 1, to: last) else {
            return DateInterval(start: today, end: lookaheadEnd)
        }
        return DateInterval(start: min(first, today), end: max(monthEnd, lookaheadEnd))
    }

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        AppFeature.calendar.isAvailable(in: defaults)
    }

    /// The link Calendar resolves to one appointment. A series shares one
    /// identifier across its occurrences, so the clicked start (UTC, or the
    /// local day for all-day events) picks the right one.
    static func eventURL(_ event: CalendarEvent, calendar: Calendar = .current) -> URL? {
        guard !event.calendarItemIdentifier.isEmpty,
              let identifier = event.calendarItemIdentifier
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        var path = "ical://ekevent/"
        if event.recurring {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = event.allDay ? calendar.timeZone : TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            path += formatter.string(from: event.start) + "/"
        }
        return URL(string: path + identifier + "?method=show&options=more")
    }

    static func nextRefresh(_ events: [CalendarEvent], now: Date,
                            calendar: Calendar = .current) -> Date {
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(900)
        let upcoming = ordered(events).filter { $0.end > now }
        return (upcoming.flatMap { [$0.start, $0.end] } + [midnight, now.addingTimeInterval(900)])
            .filter { $0 > now }.min() ?? now.addingTimeInterval(900)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./build.sh --test 2>&1 | tail -30`
Expected: `calendar: OK (N checks, ...)`, `TESTS OK`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Vorssaint/Services/Calendar/CalendarSupport.swift Tests/CalendarFeatureTests.swift
git commit -m "feat(calendar): add agenda grouping, fetch window union, and Calendar.app deep link"
```

---

### Task 5: CalendarService (EventKit actor + background lifecycle)

**Files:**
- Create: `Sources/Vorssaint/Services/Calendar/CalendarService.swift`

**Interfaces:**
- Consumes: `CalendarEvent`, `CalendarColor`, `CalendarSupport.ordered/fetchInterval/nextRefresh/isEnabled` (Tasks 3-4); `Permissions.shared.$calendarAccess` (existing, `Sources/Vorssaint/Core/Permissions.swift:30`); `DefaultsKey.calendarHiddenCalendarIDs` (Task 2) — read fresh on every `refresh()` (not cached in a property), so Task 9's settings toggle takes effect the moment it calls `refresh()` again, per Design decision #6.
- Produces: `final class CalendarService: NSObject, ObservableObject` with `static let shared`, `@Published private(set) var events: [CalendarEvent]`, `@Published private(set) var loading: Bool`, `func showMonth(_ month: Date?)`, `func syncWithPreferences()`, `func refresh()`, `func stop()`. Task 6 wires `syncWithPreferences()`/`stop()` into `FeatureRuntime.bindings`. Tasks 9 and 12 read `.events`/`.loading` and call `.showMonth(_:)`.

No unit test for this task — it wraps `EKEventStore`, `Timer`, and `NotificationCenter`, which the existing `NotchCalendarService` (its structural twin) also leaves untested directly; only its pure `CalendarSupport` logic is unit tested (Tasks 3-4). Verified by build + Task 16's manual check.

- [ ] **Step 1: Write the implementation**

Create `Sources/Vorssaint/Services/Calendar/CalendarService.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import EventKit

/// EventKit objects stay on one actor; only immutable display values reach UI.
private actor CalendarReader {
    private lazy var store = EKEventStore()

    func read(interval: DateInterval) -> [CalendarEvent] {
        guard !Task.isCancelled, EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)
        return store.events(matching: predicate).compactMap { event in
            guard event.status != .canceled,
                  event.attendees?.contains(where: { $0.isCurrentUser && $0.participantStatus == .declined }) != true,
                  let identifier = event.eventIdentifier,
                  let start = event.startDate, let end = event.endDate else { return nil }
            let color = event.calendar.cgColor.flatMap { NSColor(cgColor: $0)?.usingColorSpace(.sRGB) }
            let tint = color.map { CalendarColor(red: $0.redComponent, green: $0.greenComponent,
                                                 blue: $0.blueComponent) } ?? .fallback
            return CalendarEvent(id: identifier + ":" + String(start.timeIntervalSinceReferenceDate),
                                 calendarItemIdentifier: event.calendarItemIdentifier,
                                 title: event.title ?? "", calendarID: event.calendar.calendarIdentifier,
                                 calendarTitle: event.calendar.title, color: tint,
                                 start: start, end: end, allDay: event.isAllDay,
                                 location: event.location ?? "",
                                 recurring: event.hasRecurrenceRules || event.isDetached)
        }
    }
}

/// Started and stopped by FeatureRuntime.bindings[.calendar] — independent
/// of the Notch calendar's lifecycle, which is tied to notch visibility
/// instead. No calendar data is persisted.
final class CalendarService: NSObject, ObservableObject {
    static let shared = CalendarService()
    @Published private(set) var events: [CalendarEvent] = []
    @Published private(set) var loading = false
    private var reader: CalendarReader?
    private var task: Task<Void, Never>?
    private var refreshTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var permissionSubscription: AnyCancellable?
    private var generation = UUID()
    private var visibleMonth: Date?

    private override init() { super.init() }

    /// nil while the panel is closed; a concrete month while it's open, so
    /// prev/next/today navigation re-fetches that range. The always-on
    /// lookahead window keeps covering the agenda either way.
    func showMonth(_ month: Date?) {
        visibleMonth = month
        refresh()
    }

    func syncWithPreferences() {
        guard CalendarSupport.isEnabled() else { stop(); return }
        guard reader == nil else { return }
        reader = CalendarReader()
        for name in [Notification.Name.EKEventStoreChanged, NSApplication.didBecomeActiveNotification,
                     .NSSystemClockDidChange, .NSSystemTimeZoneDidChange, .NSCalendarDayChanged] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in self?.refresh()
            })
        }
        permissionSubscription = Permissions.shared.$calendarAccess.removeDuplicates().dropFirst()
            .sink { [weak self] _ in self?.refresh() }
        refresh()
    }

    func refresh() {
        task?.cancel()
        refreshTimer?.invalidate(); refreshTimer = nil
        generation = UUID()
        guard CalendarSupport.isEnabled(), let reader else { stop(); return }
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            events = []; loading = false
            return
        }
        let requested = generation
        let interval = CalendarSupport.fetchInterval(visibleMonth: visibleMonth, now: Date())
        loading = events.isEmpty
        task = Task { @MainActor [weak self] in
            let result = await reader.read(interval: interval)
            guard !Task.isCancelled, let self, self.generation == requested,
                  CalendarSupport.isEnabled() else { return }
            let now = Date()
            guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
                self.events = []; self.loading = false; self.task = nil
                return
            }
            let hiddenIDs = Set(UserDefaults.standard.stringArray(forKey: DefaultsKey.calendarHiddenCalendarIDs) ?? [])
            self.events = CalendarSupport.ordered(result).filter { !hiddenIDs.contains($0.calendarID) }
            self.loading = false
            self.task = nil
            let timer = Timer(fireAt: CalendarSupport.nextRefresh(self.events, now: now),
                              interval: 0, target: self, selector: #selector(self.timedRefresh),
                              userInfo: nil, repeats: false)
            timer.tolerance = 1
            RunLoop.main.add(timer, forMode: .common)
            self.refreshTimer = timer
        }
    }

    @objc private func timedRefresh() { refresh() }

    func stop() {
        generation = UUID()
        task?.cancel(); task = nil
        refreshTimer?.invalidate(); refreshTimer = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        permissionSubscription = nil
        reader = nil
        visibleMonth = nil
        events = []; loading = false
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build 2>&1 | tail -30`
Expected: no errors. (`AppFeature.calendar` doesn't exist until Task 6 — this file references it only indirectly through `CalendarSupport.isEnabled()`, which was written in Task 4 calling `AppFeature.calendar.isAvailable(in:)`, so this step will actually fail to compile until Task 6 lands. That's expected and fine: commit Tasks 5 and 6 together if your workflow requires green-build-per-commit, or note the transient red build here and proceed straight to Task 6.)

- [ ] **Step 3: Commit**

```bash
git add Sources/Vorssaint/Services/Calendar/CalendarService.swift
git commit -m "feat(calendar): add CalendarService (EventKit actor + background refresh lifecycle)"
```

---

### Task 6: Register AppFeature.calendar in the feature catalog

**Files:**
- Modify: `Sources/Vorssaint/Core/FeatureCatalog.swift`
- Modify: `Sources/Vorssaint/Core/FeaturePresets.swift`
- Modify: `Tests/FeatureCatalogTests.swift`

**Interfaces:**
- Consumes: nothing new (this task is what makes `AppFeature.calendar`, referenced by Task 5's `CalendarSupport.isEnabled()`, actually exist).
- Produces: `AppFeature.calendar` case, fully wired into every exhaustive switch on `AppFeature` that `FeatureCatalog.swift` and `FeaturePresets.swift` own. Task 7 (`FeatureRuntime.bindings`) and Task 8 (`FeatureVisibilitySupport`/`FeatureHubSettings`) depend on this case existing.

- [ ] **Step 1: Update the failing tests first**

In `Tests/FeatureCatalogTests.swift`, change the count assertion (around line 290):

```swift
        suite.expect(AppFeature.allCases.count == 69, "feature catalog has 69 features")
```
to:
```swift
        suite.expect(AppFeature.allCases.count == 70, "feature catalog has 70 features")
```

And the raw-value array (around lines 293-306) — find this line:

```swift
            "radialMenu", "scratchpad", "commandBar", "screenRecorder", "killProcess", "portManager", "notch", "notchCalendar", "notchNotifications", "notchGestures", "notchTimer", "notchAccessories", "notchLyrics", "notchQueue", "notchLiveEqualizer", "notchDownloads",
```
and change it to:
```swift
            "radialMenu", "scratchpad", "commandBar", "screenRecorder", "killProcess", "portManager", "calendar", "notch", "notchCalendar", "notchNotifications", "notchGestures", "notchTimer", "notchAccessories", "notchLyrics", "notchQueue", "notchLiveEqualizer", "notchDownloads",
```

Run: `./build.sh --test 2>&1 | tail -30`
Expected: FAIL to compile — `AppFeature.calendar` does not exist yet (referenced nowhere here directly, but `AppFeature.allCases.count` will be 69, not 70, once `.calendar` is added below, so this ordering matters: the test file above expects 70 and the exact array with `"calendar"` in it BEFORE the enum case exists, so the count assertion fails first).

- [ ] **Step 2: Add the `AppFeature.calendar` case**

In `Sources/Vorssaint/Core/FeatureCatalog.swift`, find the `Tools` group case list (around line 29-31):

```swift
    case quickLauncher, quickToggles, colorPicker, screenOCR, cleaningMode, mediaTools,
         cleaner, uninstaller, homebrew, appUpdates, screenshot, cameraPreview, radialMenu, scratchpad,
         commandBar, screenRecorder, killProcess, portManager
```
Change to:
```swift
    case quickLauncher, quickToggles, colorPicker, screenOCR, cleaningMode, mediaTools,
         cleaner, uninstaller, homebrew, appUpdates, screenshot, cameraPreview, radialMenu, scratchpad,
         commandBar, screenRecorder, killProcess, portManager, calendar
```

- [ ] **Step 3: Add `.calendar` to `group`**

Find (around line 113-116):
```swift
        case .quickLauncher, .quickToggles, .colorPicker, .screenOCR, .cleaningMode, .mediaTools,
             .cleaner, .uninstaller, .homebrew, .appUpdates, .screenshot, .cameraPreview, .radialMenu,
             .scratchpad, .commandBar, .screenRecorder, .killProcess, .portManager:
            return .tools
```
Change to:
```swift
        case .quickLauncher, .quickToggles, .colorPicker, .screenOCR, .cleaningMode, .mediaTools,
             .cleaner, .uninstaller, .homebrew, .appUpdates, .screenshot, .cameraPreview, .radialMenu,
             .scratchpad, .commandBar, .screenRecorder, .killProcess, .portManager, .calendar:
            return .tools
```

- [ ] **Step 4: Add `.calendar` to `symbolName`**

Find (around line 192):
```swift
        case .portManager: return "network"
```
Add right after:
```swift
        case .portManager: return "network"
        case .calendar: return "calendar"
```

- [ ] **Step 5: Add `.calendar` to `enabledKeys`**

Find (around lines 269-275):
```swift
        case .windowLayout, .diskImageInstaller, .mixer, .micMute, .keepAwake,
             .quickLauncher, .quickToggles, .colorPicker, .screenOCR, .cleaningMode, .mediaTools,
             .cleaner, .uninstaller, .homebrew, .appUpdates, .screenshot, .cameraPreview, .scratchpad,
             .commandBar, .screenRecorder, .killProcess, .portManager,
             .monitorCPU, .monitorGPU, .monitorMemory, .monitorNetwork, .monitorDisk, .monitorPower,
             .fanControl:
            return []
```
Change to:
```swift
        case .windowLayout, .diskImageInstaller, .mixer, .micMute, .keepAwake,
             .quickLauncher, .quickToggles, .colorPicker, .screenOCR, .cleaningMode, .mediaTools,
             .cleaner, .uninstaller, .homebrew, .appUpdates, .screenshot, .cameraPreview, .scratchpad,
             .commandBar, .screenRecorder, .killProcess, .portManager, .calendar,
             .monitorCPU, .monitorGPU, .monitorMemory, .monitorNetwork, .monitorDisk, .monitorPower,
             .fanControl:
            return []
```

(No separate "on/off" toggle — like Port Manager and Command Bar, being available already counts as engaged; the background service simply follows availability.)

- [ ] **Step 6: Add `.calendar` to `permissions`**

Find (around lines 332-336):
```swift
        case .clipboardHistory, .shelf, .urlCleaner,
             .soundOutputSwitcher,
             .extraBrightness, .bluetoothSleep, .quickLauncher, .colorPicker, .micMute, .mediaTools,
             .scratchpad, .monitorGPU, .monitorNetwork, .fanControl, .killProcess, .portManager:
            return []
```
Add a new case right before it:
```swift
        case .calendar: return [.calendar]
        case .clipboardHistory, .shelf, .urlCleaner,
             .soundOutputSwitcher,
             .extraBrightness, .bluetoothSleep, .quickLauncher, .colorPicker, .micMute, .mediaTools,
             .scratchpad, .monitorGPU, .monitorNetwork, .fanControl, .killProcess, .portManager:
            return []
```

- [ ] **Step 7: Add `.calendar` to `availabilityDefaults`'s exception list**

Find (around lines 367-373):
```swift
    static var availabilityDefaults: [String: Any] {
        Dictionary(uniqueKeysWithValues: allCases.map {
            ($0.availabilityKey,
             $0 != .focusFollowsMouse && $0 != .fanControl && $0 != .diskImageInstaller
                && $0 != .killProcess && $0 != .scrollHorizontal && $0 != .portManager)
        })
    }
```
Change to:
```swift
    static var availabilityDefaults: [String: Any] {
        Dictionary(uniqueKeysWithValues: allCases.map {
            ($0.availabilityKey,
             $0 != .focusFollowsMouse && $0 != .fanControl && $0 != .diskImageInstaller
                && $0 != .killProcess && $0 != .scrollHorizontal && $0 != .portManager
                && $0 != .calendar)
        })
    }
```

(A fresh install gets Calendar available immediately; an existing install only gets it after opting in via the hub, since it requests a new OS permission — Design decision #8 in the spec.)

- [ ] **Step 8: Add `.calendar` to `FeaturePresets.energyProfile`**

In `Sources/Vorssaint/Core/FeaturePresets.swift`, find (around line 117):
```swift
        case .notch, .notchCalendar, .notchLyrics, .notchLiveEqualizer: return .periodic
```
Add a new case right after it:
```swift
        case .notch, .notchCalendar, .notchLyrics, .notchLiveEqualizer: return .periodic
        case .calendar: return .periodic
```

(A background-refreshing read, same profile as `notchCalendar` and `clipboardHistory`.)

- [ ] **Step 9: Run tests to verify they pass**

Run: `./build.sh --test 2>&1 | tail -30`
Expected: no compile errors, `TESTS OK`, and no `FeatureCatalogTests`-related failures (the `AppFeature.allCases.allSatisfy { $0.settingsDestination.hasValidSectionAnchor }` and anchor-uniqueness checks will still fail at this point, because Task 8 hasn't added `.calendar`'s `settingsDestination` arm yet — if that test group fails here, that's expected; it's fixed in Task 8. If your test runner reports it, proceed to Task 8 before re-verifying.)

- [ ] **Step 10: Commit**

```bash
git add Sources/Vorssaint/Core/FeatureCatalog.swift Sources/Vorssaint/Core/FeaturePresets.swift Tests/FeatureCatalogTests.swift
git commit -m "feat(calendar): register AppFeature.calendar in the feature catalog"
```

---

### Task 7: FeatureRuntime binding (the lifecycle owner)

**Files:**
- Modify: `Sources/Vorssaint/App/FeatureRuntime.swift`

**Interfaces:**
- Consumes: `AppFeature.calendar` (Task 6), `CalendarService.shared.syncWithPreferences()` (Task 5).
- Produces: a `.calendar` entry in the `FeatureRuntime.bindings` dictionary — the thing that actually starts/stops `CalendarService` when the feature's availability changes. Without this entry, `CalendarService` compiles but never runs (the exact silent-failure trap flagged in spec Design decision #3).

No test step — `bindings` is a private static dictionary with no direct test coverage anywhere in this codebase (confirmed: no other `.xxx: { ... }` binding entry has its own unit test either); verified by Task 16's manual check that the panel tile actually shows live data.

- [ ] **Step 1: Add the binding**

In `Sources/Vorssaint/App/FeatureRuntime.swift`, find the `.commandBar` entry inside the `bindings` dictionary (around line 290):

```swift
        .commandBar: { CommandBarService.shared.syncWithPreferences() },
```
Add a new entry right after it:
```swift
        .commandBar: { CommandBarService.shared.syncWithPreferences() },
        .calendar: { CalendarService.shared.syncWithPreferences() },
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build 2>&1 | tail -30`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/Vorssaint/App/FeatureRuntime.swift
git commit -m "feat(calendar): wire CalendarService into FeatureRuntime's start/stop lifecycle"
```

---

### Task 8: Settings routing (SettingsPage, hub title/description)

**Files:**
- Modify: `Sources/Vorssaint/UI/Settings/FeatureVisibilitySupport.swift`
- Modify: `Sources/Vorssaint/UI/Settings/FeatureHubSettings.swift`

**Interfaces:**
- Consumes: `AppFeature.calendar` (Task 6), `FeatureStrings.calendar` (Task 1).
- Produces: `SettingsPage.calendar` case; `AppFeature.calendar.settingsDestination`; `FeatureVisibilitySupport.features(for: .calendar)`; `AppFeature.calendar.hubTitle`/`hubDescription`. Task 9 (`SettingsView.swift`'s destination switch, `CalendarSettings.swift`) and Task 13 (`MenuPanelView`'s gear button routing to `.calendar`) depend on `SettingsPage.calendar` existing.

- [ ] **Step 1: Add `SettingsPage.calendar`**

In `Sources/Vorssaint/UI/Settings/FeatureVisibilitySupport.swift`, find the `SettingsPage` enum (around line 11):

```swift
    case mouse, switcher, keyDebounce, superKey, cutPaste, autoQuit, quitProtection, cleaner, uninstaller, urlCleaner, homebrew, appUpdates, media, clipboard, windowLayout, shelf, quickTools, textSnippets, screenshot, radialMenu, commandBar, killProcess, portManager, notch
```
Change to:
```swift
    case mouse, switcher, keyDebounce, superKey, cutPaste, autoQuit, quitProtection, cleaner, uninstaller, urlCleaner, homebrew, appUpdates, media, clipboard, windowLayout, shelf, quickTools, textSnippets, screenshot, radialMenu, commandBar, killProcess, portManager, calendar, notch
```

- [ ] **Step 2: Add `.calendar` to `AppFeature.settingsDestination`**

Find (around line 287):
```swift
        case .portManager: return FeatureSettingsDestination(.portManager)
```
Add right after:
```swift
        case .portManager: return FeatureSettingsDestination(.portManager)
        case .calendar: return FeatureSettingsDestination(.calendar)
```

(No `sectionAnchor` — a single-purpose settings page, same shape as Port Manager's.)

- [ ] **Step 3: Add `.calendar` to `FeatureVisibilitySupport.features(for:)`**

Find (around line 342):
```swift
        case .portManager: return [.portManager]
```
Add right after:
```swift
        case .portManager: return [.portManager]
        case .calendar: return [.calendar]
```

- [ ] **Step 4: Add `.calendar` to `AppFeature.hubTitle`**

In `Sources/Vorssaint/UI/Settings/FeatureHubSettings.swift`, find (around line 880):
```swift
        case .portManager: return FeatureStrings.portManager(L10n.shared.language).title
```
Add right after:
```swift
        case .portManager: return FeatureStrings.portManager(L10n.shared.language).title
        case .calendar: return FeatureStrings.calendar(L10n.shared.language).title
```

- [ ] **Step 5: Add `.calendar` to `AppFeature.hubDescription`**

Find (around line 961):
```swift
        case .portManager: return FeatureStrings.portManager(L10n.shared.language).hubDescription
```
Add right after:
```swift
        case .portManager: return FeatureStrings.portManager(L10n.shared.language).hubDescription
        case .calendar: return FeatureStrings.calendar(L10n.shared.language).hubDescription
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `./build.sh --test 2>&1 | tail -30`
Expected: no compile errors (Task 9 still needs `SettingsView.swift`'s destination switch and `CalendarSettings.swift` before `swift build` succeeds end-to-end — `SettingsPage.calendar` existing without a `case .calendar:` arm in `SettingsView.swift`'s exhaustive switch will fail to compile at that call site. If `swift build` fails here specifically on `SettingsView.swift`, proceed straight to Task 9 before re-verifying.), and `TESTS OK`.

- [ ] **Step 7: Commit**

```bash
git add Sources/Vorssaint/UI/Settings/FeatureVisibilitySupport.swift Sources/Vorssaint/UI/Settings/FeatureHubSettings.swift
git commit -m "feat(calendar): add SettingsPage.calendar and hub title/description"
```

---

### Task 9: Calendar settings page

**Files:**
- Create: `Sources/Vorssaint/UI/Settings/CalendarSettings.swift`
- Modify: `Sources/Vorssaint/UI/Settings/SettingsView.swift`
- Modify: `Sources/Vorssaint/UI/Settings/SettingsDirectory.swift`

**Interfaces:**
- Consumes: `DefaultsKey.calendarHiddenCalendarIDs` (Task 2), `FeatureStrings.calendar` (Task 1), `SettingsPage.calendar` (Task 8), `CalendarService.shared.refresh()` (Task 5).
- Produces: `struct CalendarSettings: View` — the per-calendar show/hide checklist. Task 12 (`PanelCalendarView`'s gear button) navigates to this via `SettingsRouter.shared.page = .calendar`.

- [ ] **Step 1: Write the settings page**

Create `Sources/Vorssaint/UI/Settings/CalendarSettings.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import EventKit
import SwiftUI

struct CalendarSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var hiddenIDs: Set<String> = Self.savedHiddenIDs
    @State private var calendars: [EKCalendar] = []

    private var text: CalendarFeatureStrings { FeatureStrings.calendar(l10n.language) }

    var body: some View {
        Form {
            Section(text.calendarsListTitle) {
                ForEach(calendars, id: \.calendarIdentifier) { calendar in
                    Toggle(calendar.title, isOn: Binding(
                        get: { !hiddenIDs.contains(calendar.calendarIdentifier) },
                        set: { shown in
                            if shown { hiddenIDs.remove(calendar.calendarIdentifier) }
                            else { hiddenIDs.insert(calendar.calendarIdentifier) }
                            save()
                        }))
                }
                Text(text.hideCalendarHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadCalendars)
    }

    private func loadCalendars() {
        calendars = EKEventStore().calendars(for: .event).sorted { $0.title < $1.title }
    }

    private static var savedHiddenIDs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: DefaultsKey.calendarHiddenCalendarIDs) ?? [])
    }

    private func save() {
        UserDefaults.standard.set(Array(hiddenIDs), forKey: DefaultsKey.calendarHiddenCalendarIDs)
        // CalendarService reads this key fresh on every refresh() rather than
        // caching it, so telling it to refresh now is enough to make a hidden
        // calendar's events disappear immediately, without reopening the panel.
        CalendarService.shared.refresh()
    }
}
```

- [ ] **Step 2: Wire the Settings window's destination switch**

In `Sources/Vorssaint/UI/Settings/SettingsView.swift`, find (around line 374):
```swift
        case .portManager: PortManagerView()
```
Add right after:
```swift
        case .portManager: PortManagerView()
        case .calendar: CalendarSettings()
```

- [ ] **Step 3: Add a Settings search directory entry**

In `Sources/Vorssaint/UI/Settings/SettingsDirectory.swift`, find the `SettingsDirectoryItem(page: .portManager, ...)` entry (around line 215-218):
```swift
                SettingsDirectoryItem(page: .portManager,
                                      title: FeatureStrings.portManager(language).title,
                                      icon: "network",
                                      keywords: ["port", "ports", "listening", "socket", "PID", "kill port"]),
```
Add a new item right after it, staying inside the same enclosing array:
```swift
                SettingsDirectoryItem(page: .portManager,
                                      title: FeatureStrings.portManager(language).title,
                                      icon: "network",
                                      keywords: ["port", "ports", "listening", "socket", "PID", "kill port"]),
                SettingsDirectoryItem(page: .calendar,
                                      title: FeatureStrings.calendar(language).title,
                                      icon: "calendar",
                                      keywords: ["calendar", "agenda", "month", "appointments", "events", "itsycal"]),
```

- [ ] **Step 4: Build to verify it compiles**

Run: `swift build 2>&1 | tail -30`
Expected: no errors.

- [ ] **Step 5: Run the full test suite**

Run: `./build.sh --test 2>&1 | tail -30`
Expected: `TESTS OK` — this is the point where `FeatureCatalogTests.swift`'s `settingsDestination.hasValidSectionAnchor`/anchor-uniqueness checks (Task 6, deferred) should now pass, since `.calendar`'s `settingsDestination` has no anchor to collide with anything.

- [ ] **Step 6: Commit**

```bash
git add Sources/Vorssaint/UI/Settings/CalendarSettings.swift Sources/Vorssaint/UI/Settings/SettingsView.swift Sources/Vorssaint/UI/Settings/SettingsDirectory.swift
git commit -m "feat(calendar): add the Calendar settings page (per-calendar show/hide)"
```

---

### Task 10: Month grid view

**Files:**
- Create: `Sources/Vorssaint/UI/MenuPanel/CalendarMonthGridView.swift`

**Interfaces:**
- Consumes: `CalendarEvent`, `CalendarSupport.monthDays/dotColors` (Tasks 3-4), `CalendarFeatureStrings` (Task 1).
- Produces: `struct CalendarMonthGridView: View` with `init(events: [CalendarEvent], month: Binding<Date>, selectedDay: Binding<Date?>, text: CalendarFeatureStrings)`. Task 12 (`PanelCalendarView`) embeds this.

No test step — SwiftUI views have no unit tests anywhere in this codebase (confirmed: `Tests/` contains only pure-logic and service tests, never a `View` test); verified by build + Task 16's manual check.

- [ ] **Step 1: Write the view**

Create `Sources/Vorssaint/UI/MenuPanel/CalendarMonthGridView.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct CalendarMonthGridView: View {
    let events: [CalendarEvent]
    @Binding var month: Date
    @Binding var selectedDay: Date?
    let text: CalendarFeatureStrings

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 6) {
            header
            weekdayRow
            grid
        }
    }

    private var header: some View {
        HStack {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain)
                .accessibilityLabel(text.previousMonth)
            Spacer()
            Text(month, format: .dateTime.month(.wide).year())
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain)
                .accessibilityLabel(text.nextMonth)
        }
    }

    private var weekdayRow: some View {
        HStack {
            ForEach(orderedWeekdaySymbols(), id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        let days = CalendarSupport.monthDays(containing: month, calendar: calendar)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
            ForEach(days, id: \.self) { day in
                dayCell(day)
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        let isToday = calendar.isDateInToday(day)
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let dots = CalendarSupport.dotColors(on: day, events: events, calendar: calendar) ?? []
        return Button {
            selectedDay = isSelected ? nil : day
        } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 11, weight: isToday ? .bold : .regular))
                    .foregroundStyle(inMonth ? .primary : .tertiary)
                    .frame(width: 22, height: 22)
                    .background(isToday ? Color.accentColor.opacity(0.2) : .clear, in: Circle())
                    .overlay(isSelected ? Circle().stroke(Color.accentColor, lineWidth: 1.5) : nil)
                HStack(spacing: 2) {
                    ForEach(Array(dots.enumerated()), id: \.offset) { _, color in
                        Circle()
                            .fill(Color(red: color.red, green: color.green, blue: color.blue))
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
        .buttonStyle(.plain)
    }

    private func shiftMonth(_ delta: Int) {
        guard let next = calendar.date(byAdding: .month, value: delta, to: month) else { return }
        month = next
    }

    private func orderedWeekdaySymbols() -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build 2>&1 | tail -30`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/Vorssaint/UI/MenuPanel/CalendarMonthGridView.swift
git commit -m "feat(calendar): add the month grid view"
```

---

### Task 11: Agenda list view

**Files:**
- Create: `Sources/Vorssaint/UI/MenuPanel/CalendarAgendaListView.swift`

**Interfaces:**
- Consumes: `CalendarEvent`, `CalendarSupport.events/upcomingGroups/eventURL` (Tasks 3-4), `CalendarFeatureStrings` (Task 1).
- Produces: `struct CalendarAgendaListView: View` with `init(events: [CalendarEvent], selectedDay: Date?, text: CalendarFeatureStrings)`. Task 12 (`PanelCalendarView`) embeds this below the grid.

No test step — same reasoning as Task 10.

- [ ] **Step 1: Write the view**

Create `Sources/Vorssaint/UI/MenuPanel/CalendarAgendaListView.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct CalendarAgendaListView: View {
    let events: [CalendarEvent]
    let selectedDay: Date?
    let text: CalendarFeatureStrings

    var body: some View {
        let groups = displayedGroups()
        if groups.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(groups, id: \.day) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            if selectedDay == nil {
                                Text(group.day, format: .dateTime.weekday(.wide).month().day())
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(group.events) { event in
                                eventRow(event)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 220)
        }
    }

    private func displayedGroups() -> [(day: Date, events: [CalendarEvent])] {
        if let selectedDay {
            let dayEvents = CalendarSupport.events(events, on: selectedDay)
            return dayEvents.isEmpty ? [] : [(day: selectedDay, events: dayEvents)]
        }
        return CalendarSupport.upcomingGroups(events, from: Date())
    }

    private func eventRow(_ event: CalendarEvent) -> some View {
        Button { openInCalendar(event) } label: {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(Color(red: event.color.red, green: event.color.green, blue: event.color.blue))
                    .frame(width: 7, height: 7)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title.isEmpty ? text.untitled : event.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                    Text(event.allDay ? text.allDay : timeRange(event))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private func timeRange(_ event: CalendarEvent) -> String {
        "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))"
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 16))
                .foregroundStyle(.tertiary)
            Text(text.empty)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 72)
        .panelCard()
    }

    /// Calendar itself gets the link: another app claiming the `ical` scheme
    /// would not know EventKit's identifiers. Own implementation, independent
    /// of NotchCalendarView.openCalendar per the module-independence decision.
    private func openInCalendar(_ event: CalendarEvent) {
        guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal"),
              let url = CalendarSupport.eventURL(event) else { return }
        NSWorkspace.shared.open([url], withApplicationAt: application,
                                configuration: NSWorkspace.OpenConfiguration())
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build 2>&1 | tail -30`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/Vorssaint/UI/MenuPanel/CalendarAgendaListView.swift
git commit -m "feat(calendar): add the agenda list view with open-in-Calendar"
```

---

### Task 12: Panel tile root view (three-state: loading / permission / content)

**Files:**
- Create: `Sources/Vorssaint/UI/MenuPanel/PanelCalendarView.swift`

**Interfaces:**
- Consumes: `CalendarService.shared` (Task 5), `CalendarMonthGridView`/`CalendarAgendaListView` (Tasks 10-11), `Permissions.shared.calendarAccess/requestCalendar()/openCalendarSettings()/calendarRequestFailed/requestingCalendar` (existing, `Sources/Vorssaint/Core/Permissions.swift`), `FeatureStrings.calendar` (Task 1), `SettingsPage.calendar` (Task 8).
- Produces: `struct PanelCalendarView: View` with `init(onClose: @escaping () -> Void)`. Task 13 (`MenuPanelView`'s `UtilitiesSection`) hosts this exactly the way it hosts `PanelPortManagerView`.

No test step — same reasoning as Task 10.

- [ ] **Step 1: Write the view**

Create `Sources/Vorssaint/UI/MenuPanel/PanelCalendarView.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct PanelCalendarView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var calendar = CalendarService.shared
    @State private var month = Date()
    @State private var selectedDay: Date?

    var onClose: () -> Void

    private var text: CalendarFeatureStrings { FeatureStrings.calendar(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
        }
        .onAppear {
            PanelInteractionState.shared.viewKeepsPopoverOpen = true
            calendar.showMonth(month)
        }
        .onDisappear {
            PanelInteractionState.shared.viewKeepsPopoverOpen = false
            calendar.showMonth(nil)
        }
        .onChange(of: month) { _, newMonth in calendar.showMonth(newMonth) }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(text.title, systemImage: "calendar")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Button {
                SettingsRouter.shared.page = .calendar
                appDelegate()?.openSettingsWindow()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(l10n.s.menuSettings)
            .accessibilityLabel(l10n.s.menuSettings)
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(l10n.s.uninstallerCancel)
        }
    }

    @ViewBuilder
    private var content: some View {
        if permissions.calendarAccess != .fullAccess {
            permissionCard
        } else if calendar.loading && calendar.events.isEmpty {
            loadingState
        } else {
            CalendarMonthGridView(events: calendar.events, month: $month, selectedDay: $selectedDay, text: text)
            CalendarAgendaListView(events: calendar.events, selectedDay: selectedDay, text: text)
        }
    }

    private var loadingState: some View {
        VStack {
            Spacer()
            ProgressView().controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .panelCard()
    }

    private var permissionCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock").font(.system(size: 24))
            Text(permissions.calendarAccess == .denied || permissions.calendarAccess == .restricted
                 ? text.denied : text.permission)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if permissions.calendarAccess == .denied || permissions.calendarAccess == .restricted {
                    Button(text.settings) { permissions.openCalendarSettings() }
                } else {
                    Button(text.allow) { permissions.requestCalendar() }
                        .disabled(permissions.requestingCalendar)
                }
                if permissions.requestingCalendar { ProgressView().controlSize(.small) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            if permissions.calendarRequestFailed {
                Text(text.requestFailed)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .panelCard()
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build 2>&1 | tail -30`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/Vorssaint/UI/MenuPanel/PanelCalendarView.swift
git commit -m "feat(calendar): add PanelCalendarView (loading/permission/content states)"
```

---

### Task 13: Wire the tile into the menu bar panel

**Files:**
- Modify: `Sources/Vorssaint/UI/MenuPanel/MenuPanelView.swift`

**Interfaces:**
- Consumes: `PanelCalendarView` (Task 12), `AppFeature.calendar` (Task 6), `DefaultsKey.panelUtilityCalendar` (Task 2), `FeatureStrings.calendar` (Task 1).
- Produces: the actual "Calendar" tile the user sees and clicks in the menu bar panel's utility tray.

- [ ] **Step 1: Add `calendar` to `UtilityPanelItem`**

In `Sources/Vorssaint/UI/MenuPanel/MenuPanelView.swift`, find the `UtilityPanelItem` case list (around line 519-521):
```swift
    case screenshot, quickLauncher, appUpdates, cleaner, homebrew, media, clipboard, windowLayout,
         uninstaller, cleanURL, cleaning, screenOCR, colorPicker, cameraPreview, scratchpad,
         commandBar, screenRecorder, portManager
```
Change to:
```swift
    case screenshot, quickLauncher, appUpdates, cleaner, homebrew, media, clipboard, windowLayout,
         uninstaller, cleanURL, cleaning, screenOCR, colorPicker, cameraPreview, scratchpad,
         commandBar, screenRecorder, portManager, calendar
```

- [ ] **Step 2: Add `.calendar` to the `feature` switch**

Find (around line 546):
```swift
        case .portManager: return .portManager
        }
```
Change to:
```swift
        case .portManager: return .portManager
        case .calendar: return .calendar
        }
```

- [ ] **Step 3: Add panel state to `UtilitiesSection`**

Find the existing state/storage declarations (around lines 564, 582):
```swift
    @State private var showPortManagerPanel = false
```
Add right after:
```swift
    @State private var showPortManagerPanel = false
    @State private var showCalendarPanel = false
```

And:
```swift
    @AppStorage(DefaultsKey.panelUtilityPortManager) private var showPortManager = true
```
Add right after:
```swift
    @AppStorage(DefaultsKey.panelUtilityPortManager) private var showPortManager = true
    @AppStorage(DefaultsKey.panelUtilityCalendar) private var showCalendar = true
```

- [ ] **Step 4: Host `PanelCalendarView` in the section body**

Find (around lines 636-640):
```swift
            } else if showPortManagerPanel {
                PanelPortManagerView {
                    PanelInteractionState.shared.viewKeepsPopoverOpen = false
                    showPortManagerPanel = false
                }
            } else {
```
Change to:
```swift
            } else if showPortManagerPanel {
                PanelPortManagerView {
                    PanelInteractionState.shared.viewKeepsPopoverOpen = false
                    showPortManagerPanel = false
                }
            } else if showCalendarPanel {
                PanelCalendarView {
                    PanelInteractionState.shared.viewKeepsPopoverOpen = false
                    showCalendarPanel = false
                }
            } else {
```

- [ ] **Step 5: Add to `hostedSettingsPage` and `isHostingUtility`**

Find (around line 682):
```swift
        if showPortManagerPanel { return .portManager }
        return nil
```
Change to:
```swift
        if showPortManagerPanel { return .portManager }
        if showCalendarPanel { return .calendar }
        return nil
```

Find (around lines 690-692):
```swift
        showUninstaller || showCleanerPanel || showURLCleaner || showHomebrewPanel
            || showMediaPanel || showClipboardPanel || showRecentCapturesPanel
            || showWindowLayoutPanel || showAppUpdatesPanel || showPortManagerPanel
```
Change to:
```swift
        showUninstaller || showCleanerPanel || showURLCleaner || showHomebrewPanel
            || showMediaPanel || showClipboardPanel || showRecentCapturesPanel
            || showWindowLayoutPanel || showAppUpdatesPanel || showPortManagerPanel
            || showCalendarPanel
```

- [ ] **Step 6: Add `.calendar` to `isVisible`**

Find (around line 747):
```swift
        case .portManager: return showPortManager
        }
```
Change to:
```swift
        case .portManager: return showPortManager
        case .calendar: return showCalendar
        }
```

- [ ] **Step 7: Add the tile button to `itemView`**

Find the `.portManager` case (around lines 982-989):
```swift
        case .portManager:
            UtilityActionButton(title: FeatureStrings.portManager(l10n.language).title,
                                caption: FeatureStrings.portManager(l10n.language).listeningCaption,
                                systemImage: "network",
                                isEditing: editing,
                                showsDragHandle: true,
                                visibility: $showPortManager,
                                action: { showPortManagerPanel = true })
        }
```
Change to:
```swift
        case .portManager:
            UtilityActionButton(title: FeatureStrings.portManager(l10n.language).title,
                                caption: FeatureStrings.portManager(l10n.language).listeningCaption,
                                systemImage: "network",
                                isEditing: editing,
                                showsDragHandle: true,
                                visibility: $showPortManager,
                                action: { showPortManagerPanel = true })
        case .calendar:
            UtilityActionButton(title: FeatureStrings.calendar(l10n.language).title,
                                caption: FeatureStrings.calendar(l10n.language).panelCaption,
                                systemImage: "calendar",
                                isEditing: editing,
                                showsDragHandle: true,
                                visibility: $showCalendar,
                                action: { showCalendarPanel = true })
        }
```

- [ ] **Step 8: Add to `resetPanelDefaults`**

Find (around line 1066):
```swift
        showPortManager = true
    }
```
Change to:
```swift
        showPortManager = true
        showCalendar = true
    }
```

- [ ] **Step 9: Build and run the full test suite**

Run: `swift build 2>&1 | tail -30 && ./build.sh --test 2>&1 | tail -40`
Expected: no errors, `TESTS OK`.

- [ ] **Step 10: Commit**

```bash
git add Sources/Vorssaint/UI/MenuPanel/MenuPanelView.swift
git commit -m "feat(calendar): add the Calendar tile to the menu bar panel"
```

---

### Task 14: Reword the system Calendar usage string (all languages)

**Files:**
- Modify: `Resources/Info.plist`
- Modify: `Resources/de.lproj/InfoPlist.strings`
- Modify: `Resources/es.lproj/InfoPlist.strings`
- Modify: `Resources/fr.lproj/InfoPlist.strings`
- Modify: `Resources/it.lproj/InfoPlist.strings`
- Modify: `Resources/ja.lproj/InfoPlist.strings`
- Modify: `Resources/ko.lproj/InfoPlist.strings`
- Modify: `Resources/pt-BR.lproj/InfoPlist.strings`
- Modify: `Resources/ru.lproj/InfoPlist.strings`
- Modify: `Resources/tr.lproj/InfoPlist.strings`
- Modify: `Resources/zh-HK.lproj/InfoPlist.strings`
- Modify: `Resources/zh-Hans.lproj/InfoPlist.strings`
- Modify: `Resources/zh-TW.lproj/InfoPlist.strings`

**Interfaces:**
- Consumes: nothing (plain text file edits).
- Produces: the literal text macOS shows in its Calendar permission dialog, now accurate for both the Notch calendar and this new panel tile — required because `NSCalendarsFullAccessUsageDescription` is one system-wide string covering any EventKit full-access request in the process, regardless of which internal feature triggers it.

No test/build step needed beyond confirming the plist/strings files remain well-formed (a malformed one fails app launch, not compile) — verified visually in Step 9 and again in Task 16's manual check.

- [ ] **Step 1: Reword `Resources/Info.plist`**

Find:
```xml
	<key>NSCalendarsFullAccessUsageDescription</key>
	<string>Show your upcoming appointments in the notch. Calendar events stay on this Mac.</string>
```
Change to:
```xml
	<key>NSCalendarsFullAccessUsageDescription</key>
	<string>Show your upcoming appointments in the menu bar and Dynamic Island. Calendar events stay on this Mac.</string>
```

- [ ] **Step 2: Reword `Resources/de.lproj/InfoPlist.strings`**

Find:
```
"NSCalendarsFullAccessUsageDescription" = "Zeige deine anstehenden Termine im oberen Bildschirmbereich. Kalenderereignisse bleiben auf diesem Mac.";
```
Change to:
```
"NSCalendarsFullAccessUsageDescription" = "Zeige deine anstehenden Termine in der Menüleiste und im Dynamic Island. Kalenderereignisse bleiben auf diesem Mac.";
```

- [ ] **Step 3: Reword `Resources/es.lproj/InfoPlist.strings`**

Find:
```
"NSCalendarsFullAccessUsageDescription" = "Muestra tus próximas citas en la parte superior de la pantalla. Los eventos del calendario se quedan en este Mac.";
```
Change to:
```
"NSCalendarsFullAccessUsageDescription" = "Muestra tus próximas citas en la barra de menús y en el Dynamic Island. Los eventos del calendario se quedan en este Mac.";
```

- [ ] **Step 4: Reword `Resources/fr.lproj/InfoPlist.strings`**

Find:
```
"NSCalendarsFullAccessUsageDescription" = "Affiche vos prochains rendez-vous en haut de l’écran. Les événements du calendrier restent sur ce Mac.";
```
Change to:
```
"NSCalendarsFullAccessUsageDescription" = "Affiche vos prochains rendez-vous dans la barre des menus et le Dynamic Island. Les événements du calendrier restent sur ce Mac.";
```

- [ ] **Step 5: Reword `Resources/it.lproj/InfoPlist.strings`**

Find:
```
"NSCalendarsFullAccessUsageDescription" = "Mostra i tuoi prossimi appuntamenti nella parte superiore dello schermo. Gli eventi del calendario restano su questo Mac.";
```
Change to:
```
"NSCalendarsFullAccessUsageDescription" = "Mostra i tuoi prossimi appuntamenti nella barra dei menu e nel Dynamic Island. Gli eventi del calendario restano su questo Mac.";
```

- [ ] **Step 6: Reword `Resources/ja.lproj/InfoPlist.strings`**

Find:
```
"NSCalendarsFullAccessUsageDescription" = "画面上部に今後の予定を表示します。カレンダーの予定がこのMacの外に送信されることはありません。";
```
Change to:
```
"NSCalendarsFullAccessUsageDescription" = "メニューバーとDynamic Islandに今後の予定を表示します。カレンダーの予定がこのMacの外に送信されることはありません。";
```

- [ ] **Step 7: Reword `Resources/ko.lproj/InfoPlist.strings`**

Find:
```
"NSCalendarsFullAccessUsageDescription" = "화면 상단에 예정된 일정을 표시합니다. 캘린더 일정은 이 Mac에만 보관됩니다.";
```
Change to:
```
"NSCalendarsFullAccessUsageDescription" = "메뉴 막대와 Dynamic Island에 예정된 일정을 표시합니다. 캘린더 일정은 이 Mac에만 보관됩니다.";
```

- [ ] **Step 8: Reword `Resources/pt-BR.lproj/InfoPlist.strings`**

Find:
```
"NSCalendarsFullAccessUsageDescription" = "Mostra seus próximos compromissos na parte superior da tela. Os eventos do calendário ficam neste Mac.";
```
Change to:
```
"NSCalendarsFullAccessUsageDescription" = "Mostra seus próximos compromissos na barra de menus e no Dynamic Island. Os eventos do calendário ficam neste Mac.";
```

- [ ] **Step 9: Reword `Resources/ru.lproj/InfoPlist.strings`**

Find:
```
"NSCalendarsFullAccessUsageDescription" = "Показывает предстоящие встречи в верхней части экрана. События календаря остаются на этом Mac.";
```
Change to:
```
"NSCalendarsFullAccessUsageDescription" = "Показывает предстоящие встречи в строке меню и в Dynamic Island. События календаря остаются на этом Mac.";
```

- [ ] **Step 10: Reword `Resources/tr.lproj/InfoPlist.strings`**

Find:
```
"NSCalendarsFullAccessUsageDescription" = "Yaklaşan randevularınızı ekranın üst kısmında gösterir. Takvim etkinlikleri bu Mac’te kalır.";
```
Change to:
```
"NSCalendarsFullAccessUsageDescription" = "Yaklaşan randevularınızı menü çubuğunda ve Dynamic Island'da gösterir. Takvim etkinlikleri bu Mac'te kalır.";
```

- [ ] **Step 11: Reword `Resources/zh-HK.lproj/InfoPlist.strings`**

Find:
```
"NSCalendarsFullAccessUsageDescription" = "在螢幕頂部顯示即將到來的行程。日曆行程只會保留在這部 Mac 上。";
```
Change to:
```
"NSCalendarsFullAccessUsageDescription" = "在選單列和Dynamic Island顯示即將到來的行程。日曆行程只會保留在這部 Mac 上。";
```

- [ ] **Step 12: Reword `Resources/zh-Hans.lproj/InfoPlist.strings`**

Find:
```
"NSCalendarsFullAccessUsageDescription" = "在屏幕顶部显示即将到来的日程。日历事件仅保留在这台 Mac 上。";
```
Change to:
```
"NSCalendarsFullAccessUsageDescription" = "在菜单栏和Dynamic Island显示即将到来的日程。日历事件仅保留在这台 Mac 上。";
```

- [ ] **Step 13: Reword `Resources/zh-TW.lproj/InfoPlist.strings`**

Find:
```
"NSCalendarsFullAccessUsageDescription" = "在螢幕頂部顯示即將到來的行程。行事曆行程只會保留在這部 Mac 上。";
```
Change to:
```
"NSCalendarsFullAccessUsageDescription" = "在選單列和Dynamic Island顯示即將到來的行程。行事曆行程只會保留在這部 Mac 上。";
```

- [ ] **Step 14: Build to verify the plist/strings still parse**

Run: `./build.sh 2>&1 | tail -40`
Expected: the app builds and signs successfully (a malformed `.strings`/`.plist` file fails the build step that stages the app bundle, not `swiftc` itself).

- [ ] **Step 15: Commit**

```bash
git add Resources/Info.plist Resources/*.lproj/InfoPlist.strings
git commit -m "fix(calendar): reword the Calendar permission prompt so it isn't notch-only"
```

---

### Task 15: Documentation

**Files:**
- Modify: `docs/PERMISSIONS.md`
- Modify: `docs/PRIVACY.md`

**Interfaces:**
- Consumes: nothing.
- Produces: accurate user-facing documentation of what the new feature reads and why, matching this repo's convention that docs drift is a defect (see the bookmarks spec's "Repo conventions this touches" section for the same rule applied to Command Bar's bookmark sources).

No test/build step — plain markdown.

- [ ] **Step 1: Update the Calendars permission row in `docs/PERMISSIONS.md`**

Find:
```
| Calendars | Yes | Upcoming appointments in the notch |
```
Change to:
```
| Calendars | Yes | Upcoming appointments in the notch and the menu bar panel's Calendar tile |
```

- [ ] **Step 2: Update the Calendars explainer section in `docs/PERMISSIONS.md`**

Find:
```
The optional notch calendar asks for access when you press its permission button. macOS calls this full calendar access; Vorssaint uses it only to read appointments and never modifies them. If access is denied, the calendar shows a System Settings shortcut while the rest of the notch remains available. Event content stays on this Mac.
```
Change to:
```
The optional notch calendar and the menu bar panel's Calendar tile both ask for access when you press their own permission button. macOS calls this full calendar access; Vorssaint uses it only to read appointments and never modifies them. If access is denied, each surface shows a System Settings shortcut while the rest of the app remains available. Event content stays on this Mac.
```

- [ ] **Step 3: Add a paragraph to `docs/PRIVACY.md`**

Find:
```
Calendar access is requested only from the permission button. The notch reads upcoming events through the system calendar service; it does not create, change or delete events. Event text stays in memory and is cleared when the notch stops or the Mac locks.
```
Add a new paragraph right after it:
```
Calendar access is requested only from the permission button. The notch reads upcoming events through the system calendar service; it does not create, change or delete events. Event text stays in memory and is cleared when the notch stops or the Mac locks.

The menu bar panel's Calendar tile reads upcoming events the same way, independently of the notch, to show its month grid and agenda list. It does not create, change or delete events, and it only reads calendars you have not hidden in its settings.
```

- [ ] **Step 4: Commit**

```bash
git add docs/PERMISSIONS.md docs/PRIVACY.md
git commit -m "docs: document the Calendar panel tile's permission and privacy scope"
```

---

### Task 16: Full verification

**Files:** none (verification only).

**Interfaces:** none.

- [ ] **Step 1: Full test suite**

Run: `./build.sh --test 2>&1 | tail -60`
Expected: `calendar: OK (N checks, ...)` in the suite list, `TESTS OK`, `PREFERENCE CLEANUP TESTS OK`.

- [ ] **Step 2: Release build**

Run: `./build.sh 2>&1 | tail -30`
Expected: `✓ Bundle ready: build/stage/Vorssaint.app` with no errors.

- [ ] **Step 3: Install and manually verify**

Run: `./build.sh --install`

Then, launching the installed app:
- Open Settings → Features hub, find "Calendar" in Tools, turn it on (it ships opt-in on update per Design decision #8).
- Open the menu bar panel; confirm a "Calendar" tile appears in the utility tray (add it via the panel's edit mode if it doesn't show by default the first time).
- Click the tile with Calendar permission not yet granted: confirm the permission card appears with the reworded copy (no mention of "notch"), and the Allow button requests access.
- Grant access; confirm the tile now shows a loading spinner briefly, then the month grid with dots on days that have events, and an agenda list below it.
- Click a day with events in the grid; confirm the agenda filters to just that day. Click it again; confirm it returns to the upcoming list.
- Navigate to the next/previous month; confirm the grid updates and dots reflect that month's events.
- Click an agenda event; confirm Calendar.app opens showing that event.
- Open the tile's gear icon; confirm it opens Settings on the Calendar page, showing every calendar with a toggle. Hide one; confirm its events disappear from the grid/agenda without needing to reopen the panel.
- Close the panel, then reopen it: confirm the tile still shows fresh data without a long reload (background refresh keeps it warm).

- [ ] **Step 4: Report results**

Summarize which manual checks passed and any that didn't, before considering Phase 1 complete.
