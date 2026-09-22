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
