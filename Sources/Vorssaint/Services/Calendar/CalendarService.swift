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
