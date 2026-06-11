import Foundation

/// One moment on the widget's timeline: a date and the snapshot to show at that date.
struct GardenTimelineMoment: Equatable {
    let date: Date
    let snapshot: GardenSnapshot
}

/// A planned widget timeline.
struct GardenTimelinePlan: Equatable {
    let moments: [GardenTimelineMoment]
}

/// Builds the widget's timeline so the garden **ages naturally over time without the app opening**.
///
/// This is the fix for the limitation flagged since Phase 2. It is pure (no WidgetKit, no implicit
/// clock) so it's fully unit-testable; the `TimelineProvider` is then a thin adapter.
///
/// ── Strategy & why ──────────────────────────────────────────────────────────────────────────────
/// Vitality is a pure function of *whole days* since the last entry, so the garden's appearance only
/// ever changes at a **day boundary** — never mid-day. So instead of polling hourly (battery-hungry
/// and pointless), we pre-compute one entry at "now" plus one at the start of each upcoming day, and
/// keep only the days where the look actually changes (deduping the identical thriving days). The
/// result is a tiny timeline (≤ ~6 entries) whose transitions land exactly on day boundaries:
///   thriving → drooping (level 1…) → dormant, after which nothing changes and we stop.
/// A reviving "welcome back" moment also clears on the next day boundary, which falls out naturally.
enum GardenTimelinePlanner {
    /// How far ahead to project. Dormancy is reached within `graceMissedDays + maxWiltLevel + 1`
    /// days, so 8 always covers the full thriving→dormant arc with headroom.
    static let lookaheadDays = 8

    static func plan(state: GardenState, now: Date, calendar: Calendar = .current) -> GardenTimelinePlan {
        let first = GardenTimelineMoment(date: now,
                                         snapshot: GardenRules.snapshot(state: state, now: now, calendar: calendar))
        var moments = [first]

        // A garden that's never been tended stays thriving forever — nothing to schedule.
        guard state.lastEntryDate != nil else {
            return GardenTimelinePlan(moments: moments)
        }

        let startToday = calendar.startOfDay(for: now)
        for k in 1...lookaheadDays {
            guard let date = calendar.date(byAdding: .day, value: k, to: startToday) else { break }
            let snapshot = GardenRules.snapshot(state: state, now: date, calendar: calendar)
            // Only add a moment when the appearance actually changes (collapse identical days).
            if snapshot != moments[moments.count - 1].snapshot {
                moments.append(GardenTimelineMoment(date: date, snapshot: snapshot))
            }
            // Once dormant, the garden no longer changes with time — stop projecting.
            if snapshot.vitality == .dormant { break }
        }

        return GardenTimelinePlan(moments: moments)
    }
}
