// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The "Calendar" panel section: month grid, agenda list, and a permission
/// card, matching how Mixer/Network/Power each occupy their own panel tab
/// rather than living inside the Utilities tray.
struct CalendarSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var calendar = CalendarService.shared
    @State private var month = Date()
    @State private var selectedDay: Date?
    var collapsible = true

    private var text: CalendarFeatureStrings { FeatureStrings.calendar(l10n.language) }

    var body: some View {
        PanelSection(.calendar, title: text.title, collapsible: collapsible) {
            content
        }
        .onAppear { calendar.showMonth(month) }
        .onDisappear { calendar.showMonth(nil) }
        .onChange(of: month) { _, newMonth in calendar.showMonth(newMonth) }
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
