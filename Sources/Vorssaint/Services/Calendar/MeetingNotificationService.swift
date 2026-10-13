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
    /// Single timer armed at the earliest auto-dismiss deadline. CalendarService's
    /// own refresh only fires at event start/end boundaries (or every 15 min),
    /// which would make a "5 minutes" setting land late. Touched only on `reconcileQueue`.
    private var dismissTimer: DispatchSourceTimer?

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
                self.reconcileQueue.async {
                    self.sweepShownAlerts()
                    self.reconcile(events: events, offset: offset)
                }
            }
    }

    /// Cancels the subscription so no further events are observed; a
    /// reconcile already dispatched onto `reconcileQueue` may still complete.
    /// Deliberately
    /// does NOT walk scheduledEventIDs and cancel each pending system
    /// notification — a meeting notification already queued for the next
    /// few minutes should still fire even if the feature is switched off
    /// moments before. Re-enabling naturally cleans up anything genuinely
    /// stale on the first reconcile after resubscribing.
    func stop() {
        subscription = nil
        reconcileQueue.async { self.dismissTimer?.cancel(); self.dismissTimer = nil }
    }

    /// Clears delivered alerts whose meeting started more than the configured
    /// window ago and re-arms the timer for the next deadline. Runs before
    /// `reconcile`'s empty-diff early return, since the ticks that matter
    /// mid-meeting usually have nothing to add or remove. Deliberately keyed
    /// off the start time frozen into each notification rather than
    /// `CalendarService.events`, which drops cancelled, rescheduled and
    /// yesterday's events while their alerts may still be on screen.
    /// Must run on `reconcileQueue`.
    private func sweepShownAlerts() {
        dismissTimer?.cancel(); dismissTimer = nil
        let dismissAfter = MeetingJoinDismissAfter(rawValue: UserDefaults.standard.string(
            forKey: DefaultsKey.meetingJoinDismissAfter) ?? "") ?? .off
        guard dismissAfter != .off else { return }
        Notifier.shownMeetingJoins { [weak self] delivered, pending in
            guard let self else { return }
            self.reconcileQueue.async {
                let now = Date()
                Notifier.dismissDeliveredMeetingJoins(
                    ids: MeetingLinkSupport.expiredAlertIDs(delivered, dismissAfter: dismissAfter, now: now))
                self.armDismissTimer(after: MeetingLinkSupport.nextDismissDeadline(
                    delivered + pending, dismissAfter: dismissAfter, now: now))
            }
        }
    }

    private func armDismissTimer(after deadline: Date?) {
        dismissTimer?.cancel(); dismissTimer = nil
        guard subscription != nil, let deadline else { return }
        let timer = DispatchSource.makeTimerSource(queue: reconcileQueue)
        // Small slack so the deadline has certainly passed when the sweep re-evaluates it.
        timer.schedule(deadline: .now() + max(0, deadline.timeIntervalSinceNow) + 0.5)
        timer.setEventHandler { [weak self] in self?.sweepShownAlerts() }
        dismissTimer = timer
        timer.resume()
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
                                     body: link.provider.rawValue) { [weak self] accepted in
                guard accepted else { return }
                self?.reconcileQueue.async { self?.scheduledEventIDs.insert(eventID) }
            }
        }
    }
}
