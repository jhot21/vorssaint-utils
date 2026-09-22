// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// Turns CalendarService's published events into scheduled meeting-join
/// notifications. Started and stopped by FeatureRuntime.bindings[.meetingJoin],
/// always after CalendarService's own binding in that dictionary entry, so
/// this service never subscribes before there is anything to subscribe to.
///
/// CalendarService.$events has no equality gate (it republishes on every
/// refresh, not only on real content changes — EKEventStoreChanged, app
/// activation, day change and the self-scheduled refresh timer all trigger
/// one), so every emission is routed onto a private serial queue and
/// reconciled against `scheduledEventIDs`, an in-memory set that is this
/// service's own single source of truth for "what I believe is scheduled" —
/// never UNUserNotificationCenter's own pendingNotificationRequests(),
/// which is itself async and can race two overlapping reconciles.
final class MeetingNotificationService: NSObject, ObservableObject {
    static let shared = MeetingNotificationService()

    private var subscription: AnyCancellable?
    private var scheduledEventIDs: Set<String> = []
    private let reconcileQueue = DispatchQueue(label: "com.vorssaint.meeting-join.reconcile")

    private override init() { super.init() }

    func syncWithPreferences() {
        guard AppFeature.meetingJoin.isAvailable else { stop(); return }
        guard subscription == nil else { return }
        subscription = CalendarService.shared.$events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] events in
                guard let self else { return }
                let offset = MeetingJoinNotifyOffset(rawValue: UserDefaults.standard.string(
                    forKey: DefaultsKey.meetingJoinNotifyOffset) ?? "") ?? .atStart
                self.reconcileQueue.async { self.reconcile(events: events, offset: offset) }
            }
    }

    /// Cancels the subscription so no further reconciles run. Deliberately
    /// does NOT walk scheduledEventIDs and cancel each pending system
    /// notification — a meeting notification already queued for the next
    /// few minutes should still fire even if the feature is switched off
    /// moments before. Re-enabling naturally cleans up anything genuinely
    /// stale on the first reconcile after resubscribing.
    func stop() {
        subscription = nil
    }

    private func reconcile(events: [CalendarEvent], offset: MeetingJoinNotifyOffset) {
        let now = Date()
        let desired = MeetingLinkSupport.desiredNotificationIDs(events: events, offset: offset, now: now)
        let diff = MeetingLinkSupport.reconcileDiff(desired: desired, scheduled: scheduledEventIDs)
        guard !diff.toAdd.isEmpty || !diff.toRemove.isEmpty else { return }

        for eventID in diff.toRemove {
            Notifier.removeMeetingJoin(eventID: eventID)
            scheduledEventIDs.remove(eventID)
        }
        for eventID in diff.toAdd {
            guard let event = events.first(where: { $0.id == eventID }),
                  let link = MeetingLinkSupport.detect(for: event),
                  let triggerDate = MeetingLinkSupport.triggerDate(for: event, offset: offset, now: now)
            else { continue }
            Notifier.postMeetingJoin(event: event, link: link, triggerDate: triggerDate,
                                     title: event.title.isEmpty
                                        ? FeatureStrings.calendar(L10n.shared.language).untitled : event.title,
                                     body: link.provider.rawValue)
            scheduledEventIDs.insert(eventID)
        }
    }
}
