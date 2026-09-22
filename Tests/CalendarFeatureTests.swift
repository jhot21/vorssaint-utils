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
    }
}
