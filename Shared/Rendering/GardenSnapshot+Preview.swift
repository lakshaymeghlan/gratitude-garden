import Foundation

extension GardenSnapshot {
    /// Builds a snapshot directly for previews/tests — bypasses dates entirely so every visual state
    /// is reachable without changing the device clock. Plain Foundation (no SwiftUI) so it's safe in
    /// both the app and widget targets and in headless tests.
    static func preview(growth: GrowthStage = .blooming,
                        vitality: Vitality = .thriving,
                        wiltLevel: Int = 0,
                        isReviving: Bool = false,
                        totalEntries: Int = 12,
                        consecutiveDayCount: Int = 5) -> GardenSnapshot {
        GardenSnapshot(growthStage: growth, vitality: vitality, wiltLevel: wiltLevel,
                       isReviving: isReviving, lastEntryDate: Date(),
                       totalEntries: totalEntries, consecutiveDayCount: consecutiveDayCount)
    }
}
