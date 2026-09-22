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
