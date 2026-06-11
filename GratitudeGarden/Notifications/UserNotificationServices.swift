import Foundation
import UserNotifications

/// Real authorization, backed by `UNUserNotificationCenter`. Local notifications need **no special
/// entitlement** — only this runtime authorization, requested the first time the user enables
/// reminders.
struct UserNotificationAuthorizer: NotificationAuthorizing {
    private var center: UNUserNotificationCenter { .current() }

    func currentStatus() async -> NotificationAuthorizationStatus {
        Self.map(await center.notificationSettings().authorizationStatus)
    }

    func requestAuthorization() async -> NotificationAuthorizationStatus {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        return await currentStatus()
    }

    private static func map(_ status: UNAuthorizationStatus) -> NotificationAuthorizationStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied:        return .denied
        case .authorized:    return .authorized
        case .provisional:   return .provisional
        case .ephemeral:     return .ephemeral
        @unknown default:    return .denied
        }
    }
}

/// Real scheduling, backed by `UNUserNotificationCenter`, using one non-repeating calendar trigger
/// per planned reminder. `replaceAll` clears our reminders first so we never accumulate duplicates.
struct UserNotificationScheduler: NotificationScheduling {
    private var center: UNUserNotificationCenter { .current() }

    func replaceAll(with planned: [PlannedNotification], calendar: Calendar) async {
        center.removeAllPendingNotificationRequests()
        for item in planned {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default

            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: item.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: item.id, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    func cancelAll() async {
        center.removeAllPendingNotificationRequests()
    }

    func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }
}
