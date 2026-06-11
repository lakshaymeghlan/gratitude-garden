import Foundation

/// How far the garden has grown.
///
/// Growth reflects *accumulated* practice and is driven by the total number of entries ever
/// made — a value that never decreases. This is a deliberate forgiving-design choice:
/// **progress is never permanently lost.** Missing days can change how the garden *looks*
/// (its `Vitality`), but never how far it has *grown*.
enum GrowthStage: Int, Codable, CaseIterable, Comparable {
    case seed
    case sprout
    case seedling
    case budding
    case blooming
    case flourishing

    static func < (lhs: GrowthStage, rhs: GrowthStage) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Maps cumulative entries to a growth stage. Thresholds are intentionally gentle and
    /// are easy to tune later without touching the forgiving logic.
    static func stage(forTotalEntries total: Int) -> GrowthStage {
        switch total {
        case ..<1:    return .seed
        case 1..<4:   return .sprout
        case 4..<8:   return .seedling
        case 8..<15:  return .budding
        case 15..<25: return .blooming
        default:      return .flourishing
        }
    }
}
