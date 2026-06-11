import Foundation

/// A complete, pure description of what the garden looks like *right now*.
///
/// This is the single render descriptor the UI and the widget consume. It fuses durable progress
/// (`growthStage`, counts) with time-derived appearance (`vitality`, `wiltLevel`, `isReviving`)
/// so the visual layer never has to reach into `GardenState` or call the rules engine itself.
///
/// Phase 3 (pixel art) maps `(growthStage, vitality, wiltLevel, isReviving)` → sprites; Phase 4
/// (widget) reuses the very same descriptor. Keeping everything the art needs in one value type
/// is what lets those phases avoid touching domain logic.
struct GardenSnapshot: Equatable {
    let growthStage: GrowthStage
    let vitality: Vitality
    /// 0 when thriving; 1...maxWiltLevel as the garden gradually droops.
    let wiltLevel: Int
    /// True only on the day the user returned after a droop/dormancy — the welcome-back moment.
    let isReviving: Bool
    let lastEntryDate: Date?
    let totalEntries: Int
    let consecutiveDayCount: Int
}
