import Foundation

/// Which tone a notification uses. The tier is chosen from the garden's *vitality* at fire time, so
/// it always matches the forgiving thresholds in `GardenRules`.
enum NotificationTier: String, Codable, Equatable {
    case dailyReminder       // day 0–2 (thriving): a light, optional invitation
    case gentleNudge         // day 3+ (drooping): still warm, never urgent
    case dormantInvitation   // dormant: a peaceful "whenever you're ready"
}

/// A fully-resolved notification the scheduler can post. Pure data — no UserNotifications types — so
/// the planner stays testable and platform-independent.
struct PlannedNotification: Equatable, Identifiable {
    let id: String
    let date: Date
    let tier: NotificationTier
    let title: String
    let body: String
}

/// App-agnostic mirror of `UNAuthorizationStatus`, so business logic never imports UserNotifications.
enum NotificationAuthorizationStatus: Equatable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral

    /// Whether we're allowed to actually post notifications.
    var allowsScheduling: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral: return true
        case .notDetermined, .denied:               return false
        }
    }
}

/// The user's reminder preferences. **Default is OFF** — reminders are opt-in and gentle.
struct NotificationSettings: Codable, Equatable {
    var isEnabled: Bool
    var hour: Int
    var minute: Int

    static let `default` = NotificationSettings(isEnabled: false, hour: 20, minute: 0)
}
