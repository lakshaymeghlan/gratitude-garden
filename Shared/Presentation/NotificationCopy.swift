import Foundation

/// Every word a notification can say, grouped by tier.
///
/// **The forgiving voice is enforced here.** There is intentionally nothing about missed days,
/// broken streaks, falling behind, forgetting, or a dying garden. Every line is a warm, optional
/// invitation — the kind of thing a kind friend would say, never a scolding. Variants exist purely
/// so repeated reminders don't feel robotic.
enum NotificationCopy {
    struct Line: Equatable {
        let title: String
        let body: String
    }

    /// Day 0–2 (thriving). Light touch — the garden is fine; this is just a friendly window.
    static let dailyReminders: [Line] = [
        Line(title: "A tiny moment is enough", body: "What's one small thing from today?"),
        Line(title: "Your garden would love a visit", body: "What helped you get through today?"),
        Line(title: "Whenever you're ready", body: "Anything you're looking forward to?"),
    ]

    /// Day 3+ (drooping). Still gentle and unhurried — an open door, not a deadline.
    static let gentleNudges: [Line] = [
        Line(title: "Your garden is waiting for you", body: "No rush — a tiny moment is enough."),
        Line(title: "Your garden would love a visit", body: "What's one small thing from today?"),
        Line(title: "Still here for you", body: "What helped you get through today?"),
    ]

    /// Dormant. The most spacious tone of all — resting, patient, never urgent.
    static let dormantInvitations: [Line] = [
        Line(title: "Your garden is resting", body: "It'll bloom again the moment you return."),
        Line(title: "Whenever you're ready", body: "One small thing is all it takes to begin again."),
        Line(title: "Your garden remembers you", body: "Anything you're looking forward to?"),
    ]

    static func lines(for tier: NotificationTier) -> [Line] {
        switch tier {
        case .dailyReminder:     return dailyReminders
        case .gentleNudge:       return gentleNudges
        case .dormantInvitation: return dormantInvitations
        }
    }

    /// Picks a variant deterministically (so scheduling is testable and reminders rotate gently).
    static func line(for tier: NotificationTier, variant: Int) -> Line {
        let options = lines(for: tier)
        let index = ((variant % options.count) + options.count) % options.count
        return options[index]
    }
}
