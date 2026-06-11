import Foundation

/// Decides *which* notifications to schedule and *when* — the testable heart of the system.
///
/// Pure (no UserNotifications, no implicit clock): given the user's settings, the garden state, and
/// "now", it returns the concrete notifications to post. The app reschedules whenever state changes
/// (foreground, after a save, settings change), so this only needs to project a short horizon.
///
/// ── Forgiving rules baked in ───────────────────────────────────────────────────────────────────
///  • Disabled → nothing.
///  • Only **future** reminder times (never fire in the past / immediately).
///  • **Skip any day already tended** — especially today, so a user who just logged is never pinged.
///    Combined with rescheduling after a save, this guarantees "never notify right after returning."
///  • Tone is chosen from the garden's vitality at fire time: thriving→daily, drooping→gentle,
///    dormant→invitation — automatically matching `GardenRules`' grace period.
enum NotificationPlanner {
    /// How many days ahead to pre-schedule. The app refreshes often, so a week is plenty and keeps
    /// us far under iOS's 64-pending limit.
    static let horizonDays = 7

    static func plan(settings: NotificationSettings,
                     state: GardenState,
                     now: Date,
                     calendar: Calendar = .current) -> [PlannedNotification] {
        guard settings.isEnabled else { return [] }

        var result: [PlannedNotification] = []
        let startToday = calendar.startOfDay(for: now)
        var variant = 0

        for offset in 0...horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startToday),
                  let fire = calendar.date(bySettingHour: settings.hour, minute: settings.minute, second: 0, of: day)
            else { continue }

            // Future only — never fire in the past or the very moment of a save.
            if fire <= now { continue }

            // Never nudge a day the user has already tended (covers "just logged today").
            if let last = state.lastEntryDate, calendar.isDate(last, inSameDayAs: day) { continue }

            // Tone follows how the garden will look at that moment — same forgiving thresholds.
            let vitality = GardenRules.appearance(lastEntryDate: state.lastEntryDate,
                                                  now: fire, calendar: calendar).vitality
            let tier = tier(for: vitality)
            let line = NotificationCopy.line(for: tier, variant: variant)
            variant += 1

            let id = "garden.reminder.\(Int(calendar.startOfDay(for: day).timeIntervalSince1970))"
            result.append(PlannedNotification(id: id, date: fire, tier: tier, title: line.title, body: line.body))
        }

        return result
    }

    static func tier(for vitality: Vitality) -> NotificationTier {
        switch vitality {
        case .thriving: return .dailyReminder
        case .drooping: return .gentleNudge
        case .dormant:  return .dormantInvitation
        }
    }
}
