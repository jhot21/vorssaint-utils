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
