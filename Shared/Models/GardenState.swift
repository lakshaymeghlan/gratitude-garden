import Foundation

/// The persisted state of the garden.
///
/// Stored in the shared App Group container so both the app and the widget read the same source
/// of truth. It holds only durable facts; the *appearance* (vitality, wilt, dormancy) is always
/// computed on demand by `GardenRules` from `lastEntryDate` and the current date — never stored —
/// so it can never drift out of sync with the clock.
struct GardenState: Codable, Equatable {
    /// Start-of-day of the most recent entry. `nil` for a brand-new garden.
    var lastEntryDate: Date?
    /// Current run of consecutive days logged. Used for gentle encouragement only — never to
    /// punish. Resetting it never reduces `growthStage`.
    var consecutiveDayCount: Int
    /// Total distinct days ever logged. Monotonic — drives growth so progress is never lost.
    var totalEntries: Int
    /// How far the garden has grown. Derived from `totalEntries`; never decreases.
    var growthStage: GrowthStage
    /// Whether the most recent log was a *return* after the garden had drooped or gone dormant.
    /// Set by `GardenRules.applyingEntry`; powers the welcome-back moment in the app and widget,
    /// and survives relaunch. Cleared automatically by the next non-revival log.
    var lastEntryWasRevival: Bool

    init(lastEntryDate: Date?,
         consecutiveDayCount: Int,
         totalEntries: Int,
         growthStage: GrowthStage,
         lastEntryWasRevival: Bool) {
        self.lastEntryDate = lastEntryDate
        self.consecutiveDayCount = consecutiveDayCount
        self.totalEntries = totalEntries
        self.growthStage = growthStage
        self.lastEntryWasRevival = lastEntryWasRevival
    }

    /// A fresh garden: a hopeful seed, never a failure.
    static let empty = GardenState(
        lastEntryDate: nil,
        consecutiveDayCount: 0,
        totalEntries: 0,
        growthStage: .seed,
        lastEntryWasRevival: false
    )

    /// Resilient decoding: every field falls back to its default if absent, so adding fields in
    /// later phases never breaks previously-saved JSON (forward migration handled for free).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lastEntryDate       = try c.decodeIfPresent(Date.self, forKey: .lastEntryDate)
        consecutiveDayCount = try c.decodeIfPresent(Int.self, forKey: .consecutiveDayCount) ?? 0
        totalEntries        = try c.decodeIfPresent(Int.self, forKey: .totalEntries) ?? 0
        growthStage         = try c.decodeIfPresent(GrowthStage.self, forKey: .growthStage) ?? .seed
        lastEntryWasRevival = try c.decodeIfPresent(Bool.self, forKey: .lastEntryWasRevival) ?? false
    }
}
