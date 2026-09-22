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
}
