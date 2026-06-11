import Foundation

/// Abstraction over the system's notification authorization. Faked in tests; the real one wraps
/// `UNUserNotificationCenter`. No UserNotifications import here, so `NotificationManager` is testable
/// without the framework.
protocol NotificationAuthorizing {
    func currentStatus() async -> NotificationAuthorizationStatus
    /// Prompts the user (only meaningful when status is `.notDetermined`), returning the new status.
    func requestAuthorization() async -> NotificationAuthorizationStatus
}

/// Abstraction over posting/cancelling scheduled notifications.
protocol NotificationScheduling {
    /// Atomically replaces all pending garden reminders with `planned`.
    func replaceAll(with planned: [PlannedNotification], calendar: Calendar) async
    func cancelAll() async
    /// Identifiers currently pending — used by tests (and useful for debugging).
    func pendingIdentifiers() async -> [String]
}
