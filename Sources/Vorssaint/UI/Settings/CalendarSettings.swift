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
            ForEach(groupedCalendars, id: \.source) { group in
                Section(group.source) {
                    ForEach(group.calendars, id: \.calendarIdentifier) { calendar in
                        Toggle(calendar.title, isOn: Binding(
                            get: { !hiddenIDs.contains(calendar.calendarIdentifier) },
                            set: { shown in
                                if shown { hiddenIDs.remove(calendar.calendarIdentifier) }
                                else { hiddenIDs.insert(calendar.calendarIdentifier) }
                                save()
                            }))
                    }
                }
            }
            Section {
                Text(text.hideCalendarHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadCalendars)
    }

    /// Grouped by account (e.g. "iCloud", "you@gmail.com") so calendars that
    /// share a name across accounts are never ambiguous in the list.
    private var groupedCalendars: [(source: String, calendars: [EKCalendar])] {
        Dictionary(grouping: calendars, by: { $0.source.title })
            .sorted { $0.key < $1.key }
            .map { (source: $0.key, calendars: $0.value.sorted { $0.title < $1.title }) }
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
