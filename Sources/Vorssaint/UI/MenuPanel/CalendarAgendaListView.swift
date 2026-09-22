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
