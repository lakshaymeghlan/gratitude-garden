import Foundation

/// The garden's *current appearance* — how it looks right now based on how recently the user
/// has tended it. Unlike `GrowthStage`, vitality can ebb and flow. Crucially it is
/// **forgiving**: it never reaches a "dead" state, only `dormant`, and any return revives it.
enum Vitality: Int, Codable, Comparable {
    /// Healthy and lush. The default — and where the garden sits through the entire grace period.
    case thriving
    /// Gently drooping / losing a little color. Begins only on the 3rd consecutive missed day,
    /// and deepens slowly. Always recoverable.
    case drooping
    /// Resting deeply. Reached only after a long absence. **Not dead** — all growth is preserved
    /// and a single entry brings it back.
    case dormant

    static func < (lhs: Vitality, rhs: Vitality) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The full visual state the UI and widget render. This is the pure output of the rules engine.
struct GardenAppearance: Equatable {
    var vitality: Vitality
    /// 0 when thriving; increases step-by-step as the garden droops (1...maxWiltLevel). Lets the
    /// art droop *gradually* over days rather than snapping between states.
    var wiltLevel: Int
    /// True at the moment the user returns after the garden had drooped or gone dormant — drives
    /// the warm "welcome back" revival animation. Always false in steady-state appearance; it is
    /// produced by `GardenRules.applyingEntry` when an entry is actually logged.
    var isReviving: Bool
}
