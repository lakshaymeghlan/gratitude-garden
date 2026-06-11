import Foundation

/// The forgiving rules engine.
///
/// Pure, deterministic functions that map *time + state* to the garden's appearance. There is
/// no I/O and no implicit `Date()` call inside — callers always pass `now` — so every rule is
/// fully unit-testable and behaves identically in the app, the widget, and the test bundle.
///
/// ── The forgiving contract (do not weaken without a very good reason) ──────────────────────
///  • Missing one or two days does **nothing** — the garden stays thriving.
///  • Drooping begins only on the 3rd consecutive missed day, and deepens *slowly*, one step
///    per day.
///  • The garden never dies — the worst it ever gets is `dormant`, with all growth preserved.
///  • Any return revives it, with a warm welcome-back moment.
///  • A clock that moves backwards (timezone change / manual date change) never penalizes the
///    user.
///
/// ── What counts as a "missed day" ──────────────────────────────────────────────────────────
/// Today is *always still open* — the user can log at any point during the current day — so the
/// current day is never counted as missed. A missed day is a full calendar day that elapsed
/// after the last entry's day without a new entry. Concretely, if the last entry was on day D:
///
///   evaluated on D    → 0 missed   (logged today)
///   evaluated on D+1  → 0 missed   (yesterday's entry; today still open)
///   evaluated on D+2  → 1 missed   ← "missed one day": nothing happens
///   evaluated on D+3  → 2 missed   ← "missed two days": nothing happens
///   evaluated on D+4  → 3 missed   ← drooping begins, gently
///
enum GardenRules {

    // MARK: - Tunable constants

    /// Missing up to this many days changes nothing. Days 1 and 2 are "free."
    static let graceMissedDays = 2

    /// Number of drooping steps the garden passes through before it settles into dormancy.
    /// Higher = the garden droops more slowly before resting.
    static let maxWiltLevel = 4

    // MARK: - Appearance (steady state)

    /// The garden's appearance given when the user last logged and what "now" is.
    ///
    /// `isReviving` is always `false` here: revival is an *event* (the user returning), produced
    /// by `applyingEntry(on:to:)`, not a steady state.
    static func appearance(lastEntryDate: Date?,
                           now: Date,
                           calendar: Calendar = .current) -> GardenAppearance {
        // A garden that has never been tended is a hopeful fresh seed, not a failure.
        guard let last = lastEntryDate else {
            return GardenAppearance(vitality: .thriving, wiltLevel: 0, isReviving: false)
        }

        let missed = missedDays(lastEntryDate: last, now: now, calendar: calendar)

        // Inside the grace window (0, 1, or 2 missed days) → fully thriving.
        if missed <= graceMissedDays {
            return GardenAppearance(vitality: .thriving, wiltLevel: 0, isReviving: false)
        }

        // Past the grace window: droop one step per extra missed day.
        // missed == graceMissedDays + 1  →  wilt 1 (the 3rd missed day).
        let wilt = missed - graceMissedDays
        if wilt >= maxWiltLevel {
            // Deeply at rest — but never dead, and all growth is preserved.
            return GardenAppearance(vitality: .dormant, wiltLevel: maxWiltLevel, isReviving: false)
        }
        return GardenAppearance(vitality: .drooping, wiltLevel: wilt, isReviving: false)
    }

    // MARK: - Logging an entry

    /// Applies a new entry made on `date`, returning the updated state and whether this entry
    /// counts as a **revival** (the user returning after the garden had drooped or gone dormant).
    ///
    /// Growth only ever moves forward; a gap restarts the *streak* but never reduces the
    /// `growthStage`. Logging twice in one day is idempotent — it never double-counts.
    static func applyingEntry(on date: Date,
                              to state: GardenState,
                              calendar: Calendar = .current) -> (state: GardenState, didRevive: Bool) {
        // Determine, before mutating, whether the garden needed reviving.
        let priorVitality = appearance(lastEntryDate: state.lastEntryDate,
                                       now: date, calendar: calendar).vitality
        let didRevive = priorVitality != .thriving

        var new = state

        if let last = state.lastEntryDate {
            let days = daysBetween(last, date, calendar: calendar)
            if days == 0 {
                // Already logged today — keep it idempotent, don't double-count or change anything.
                return (new, false)
            } else if days == 1 {
                new.consecutiveDayCount += 1   // a true consecutive day → streak continues
            } else {
                new.consecutiveDayCount = 1    // streak gently restarts; growth is untouched
            }
        } else {
            new.consecutiveDayCount = 1
        }

        new.totalEntries += 1
        new.lastEntryDate = calendar.startOfDay(for: date)
        // Growth only ever moves forward — never let it slip backwards.
        new.growthStage = max(new.growthStage, GrowthStage.stage(forTotalEntries: new.totalEntries))
        // Record whether this log was a return-from-droop/dormancy so the welcome-back moment can
        // survive relaunch and be shown by the widget.
        new.lastEntryWasRevival = didRevive

        return (new, didRevive)
    }

    // MARK: - Snapshot (the single render descriptor)

    /// Fuses durable state with time-derived appearance into the one value the UI and widget draw.
    /// Pure: pass `now` (and optionally a `calendar`) so it's deterministic everywhere.
    static func snapshot(state: GardenState,
                         now: Date,
                         calendar: Calendar = .current) -> GardenSnapshot {
        let appearance = appearance(lastEntryDate: state.lastEntryDate, now: now, calendar: calendar)
        // The welcome-back moment shows only on the day of the returning entry.
        let loggedToday = state.lastEntryDate.map { daysBetween($0, now, calendar: calendar) == 0 } ?? false
        let isReviving = state.lastEntryWasRevival && loggedToday

        return GardenSnapshot(
            growthStage: state.growthStage,
            vitality: appearance.vitality,
            wiltLevel: appearance.wiltLevel,
            isReviving: isReviving,
            lastEntryDate: state.lastEntryDate,
            totalEntries: state.totalEntries,
            consecutiveDayCount: state.consecutiveDayCount
        )
    }

    // MARK: - Helpers

    /// Full calendar days elapsed after the last entry's day, excluding the still-open current
    /// day. See the type doc for the day-by-day table. Never negative.
    static func missedDays(lastEntryDate: Date,
                           now: Date,
                           calendar: Calendar = .current) -> Int {
        max(0, daysBetween(lastEntryDate, now, calendar: calendar) - 1)
    }

    /// Whole calendar days between two dates, measured start-of-day to start-of-day.
    ///
    /// Never negative: a clock that jumps backwards is treated as "no time passed," so the user
    /// is never penalized for a timezone or manual date change.
    static func daysBetween(_ from: Date, _ to: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: to)
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return max(0, days)
    }
}
