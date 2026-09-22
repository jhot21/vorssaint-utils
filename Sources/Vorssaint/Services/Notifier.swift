// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import os.log
import UserNotifications

enum Notifier {
    static let whatsAppOrganizerUndoActionIdentifier =
        "com.vorssaint.notification.whatsapp-organizer.undo"
    private static let whatsAppOrganizerTransactionKey =
        "com.vorssaint.notification.whatsapp-organizer.transaction"
    private static let whatsAppOrganizerCategoryIdentifier =
        "com.vorssaint.notification.whatsapp-organizer"
    static let meetingJoinCategoryIdentifier = "com.vorssaint.notification.meeting-join"
    private static let meetingJoinEventIDKey = "com.vorssaint.notification.meeting-join.event-id"
    private static let meetingJoinProviderKey = "com.vorssaint.notification.meeting-join.provider"
    private static let meetingJoinBrowserURLKey = "com.vorssaint.notification.meeting-join.browser-url"
    private static let meetingJoinNativeURLKey = "com.vorssaint.notification.meeting-join.native-url"
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "notifications")

    /// The single call site for `setNotificationCategories`, which REPLACES
    /// the entire registered set rather than merging into it — every
    /// category-posting method in this file relies on this having run once
    /// at launch instead of registering its own category. Called from
    /// `AppDelegate.applicationDidFinishLaunching`.
    static func registerCategories() {
        // The WhatsApp undo button's real, localized title is only known
        // once postWhatsAppOrganization actually runs (it re-registers both
        // categories with the correct title then — see Step 2 below); a
        // placeholder title here is harmless because no WhatsApp
        // notification exists yet for this category to be attached to.
        let undo = UNNotificationAction(
            identifier: whatsAppOrganizerUndoActionIdentifier,
            title: "",
            options: [.foreground])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: whatsAppOrganizerCategoryIdentifier,
                                   actions: [undo], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: meetingJoinCategoryIdentifier,
                                   actions: [], intentIdentifiers: [], options: []),
        ])
    }

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            // A denied prompt is the user's call; a request that ERRORS means
            // notifications silently cannot work at all — leave a trace so
            // that state is diagnosable instead of invisible.
            if let error {
                log.error("notification authorization failed: \(error.localizedDescription, privacy: .public)")
            } else if !granted {
                log.notice("notification authorization not granted")
            }
        }
    }

    static func post(title: String, body: String) {
        post(title: title, body: body, categoryIdentifier: nil, userInfo: [:])
    }

    static func postWhatsAppOrganization(title: String,
                                         body: String,
                                         undoTitle: String,
                                         transactionID: UUID) {
        // Category registration (including this action's real title) happens
        // once, in registerCategories(), not here — see that method's doc.
        let undo = UNNotificationAction(
            identifier: whatsAppOrganizerUndoActionIdentifier,
            title: undoTitle,
            options: [.foreground])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: whatsAppOrganizerCategoryIdentifier,
                                   actions: [undo], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: meetingJoinCategoryIdentifier,
                                   actions: [], intentIdentifiers: [], options: []),
        ])
        post(title: title, body: body,
             categoryIdentifier: whatsAppOrganizerCategoryIdentifier,
             userInfo: [whatsAppOrganizerTransactionKey: transactionID.uuidString])
    }

    /// Schedules a meeting-join notification. `link` is frozen into
    /// `userInfo` as a fallback for the cold-launch case where the tap
    /// handler runs before CalendarService has repopulated `events` — see
    /// AppDelegate's meeting-join branch.
    static func postMeetingJoin(event: CalendarEvent, link: MeetingLink, triggerDate: Date,
                                title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else {
                log.notice("meeting-join notification dropped: authorization status \(settings.authorizationStatus.rawValue)")
                return
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.categoryIdentifier = meetingJoinCategoryIdentifier
            var userInfo: [AnyHashable: Any] = [
                meetingJoinEventIDKey: event.id,
                meetingJoinProviderKey: link.provider.rawValue,
                meetingJoinBrowserURLKey: link.browserURL.absoluteString,
            ]
            if let nativeAppURL = link.nativeAppURL {
                userInfo[meetingJoinNativeURLKey] = nativeAppURL.absoluteString
            }
            content.userInfo = userInfo
            let interval = max(1, triggerDate.timeIntervalSinceNow)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            let request = UNNotificationRequest(identifier: event.id, content: content, trigger: trigger)
            center.add(request) { error in
                if let error {
                    log.error("meeting-join notification delivery failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// Removes a previously scheduled (not yet fired) meeting-join
    /// notification for this event id, if one exists. A no-op if it
    /// already fired or was never scheduled.
    static func removeMeetingJoin(eventID: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [eventID])
    }

    /// The event id a tapped meeting-join notification was scheduled for,
    /// or nil if this response is not a meeting-join notification.
    static func meetingJoinEventID(from response: UNNotificationResponse) -> String? {
        guard response.notification.request.content.categoryIdentifier == meetingJoinCategoryIdentifier else {
            return nil
        }
        return response.notification.request.content.userInfo[meetingJoinEventIDKey] as? String
    }

    /// The MeetingLink frozen into a meeting-join notification's userInfo
    /// at schedule time — the fallback used only when a live lookup by
    /// event id fails (e.g. a cold launch racing CalendarService's first
    /// refresh). nil if this response is not a meeting-join notification or
    /// its userInfo is malformed.
    static func meetingJoinFrozenLink(from response: UNNotificationResponse) -> MeetingLink? {
        let userInfo = response.notification.request.content.userInfo
        guard response.notification.request.content.categoryIdentifier == meetingJoinCategoryIdentifier,
              let providerRaw = userInfo[meetingJoinProviderKey] as? String,
              let provider = MeetingProvider(rawValue: providerRaw),
              let browserURLString = userInfo[meetingJoinBrowserURLKey] as? String,
              let browserURL = URL(string: browserURLString) else { return nil }
        let nativeAppURL = (userInfo[meetingJoinNativeURLKey] as? String).flatMap(URL.init(string:))
        return MeetingLink(provider: provider, browserURL: browserURL, nativeAppURL: nativeAppURL)
    }

    static func whatsAppOrganizerTransactionID(from response: UNNotificationResponse) -> UUID? {
        guard response.actionIdentifier == whatsAppOrganizerUndoActionIdentifier,
              let raw = response.notification.request.content.userInfo[
                whatsAppOrganizerTransactionKey] as? String else { return nil }
        return UUID(uuidString: raw)
    }

    private static func post(title: String,
                             body: String,
                             categoryIdentifier: String?,
                             userInfo: [AnyHashable: Any]) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else {
                log.notice("notification dropped: authorization status \(settings.authorizationStatus.rawValue)")
                return
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            if let categoryIdentifier { content.categoryIdentifier = categoryIdentifier }
            content.userInfo = userInfo
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(request) { error in
                if let error {
                    log.error("notification delivery failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}
