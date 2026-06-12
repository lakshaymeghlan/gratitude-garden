import Foundation

/// How far the user's *world* has grown — derived purely from cumulative entries, never stored, and
/// never decreasing (because `totalEntries` only ever goes up). This replaces the single-plant
/// `GrowthStage` as the driver of the visual scene. `GrowthStage` stays on `GardenState` untouched
/// for storage/backward-compatibility; the landscape keys off this instead.
enum WorldStage: Int, Comparable, CaseIterable {
    case bareMeadow = 0   // 0–2 entries: mostly grass, a tiny flower patch, hopeful emptiness
    case sprouting        // 3–7: small clusters of flowers appear
    case patches          // 8–15: more color, additional varieties
    case spreading        // 16–30: flower fields begin spreading; a path appears
    case alive            // 31–60: the landscape feels alive
    case lush             // 61–100: a lush blooming valley
    case magical          // 100+: a magical flourishing world

    static func < (lhs: WorldStage, rhs: WorldStage) -> Bool { lhs.rawValue < rhs.rawValue }

    static func stage(forTotalEntries total: Int) -> WorldStage {
        switch total {
        case ..<3:     return .bareMeadow
        case 3..<8:    return .sprouting
        case 8..<16:   return .patches
        case 16..<31:  return .spreading
        case 31..<61:  return .alive
        case 61..<101: return .lush
        default:       return .magical
        }
    }
}

extension GardenSnapshot {
    /// The world's progression stage, derived from cumulative entries.
    var worldStage: WorldStage { WorldStage.stage(forTotalEntries: totalEntries) }
}
