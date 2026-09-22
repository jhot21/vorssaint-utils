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
