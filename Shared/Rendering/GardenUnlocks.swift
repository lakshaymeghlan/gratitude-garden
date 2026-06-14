import Foundation

/// What the world contains right now — derived purely from cumulative entries. Progression is a set
/// of **discrete, obvious milestones**, not density: a single flower, then a patch, a second patch, a
/// tree, the lake, a bridge, butterflies, fireflies. Each step makes the user think "something new
/// appeared." Monotonic (entries only grow), so nothing is ever lost.
///
/// Milestones:
///   1 → 1 flower · 5 → 1st patch · 10 → 2nd patch · 20 → 1st tree · 30 → lake · 45 → garden decoration
///   50 → bridge · 65 → 2nd tree · 75 → butterflies · 100 → fireflies · (more patches/trees beyond)
struct GardenUnlocks: Equatable {
    var singleFlowers: Int    // individual flowers, only before the first patch (entries 1–4)
    var flowerPatches: Int    // big, obvious flower beds
    var trees: Int
    var butterflies: Int
    var fireflies: Int
    var hasLake: Bool
    var hasBridge: Bool
    var hasGardenDecor: Bool  // a birdbath in the garden

    static func derive(totalEntries n: Int) -> GardenUnlocks {
        func tier(_ steps: [(Int, Int)]) -> Int {
            var v = 0
            for (threshold, value) in steps where n >= threshold { v = value }
            return v
        }
        return GardenUnlocks(
            singleFlowers: n < 5 ? max(0, n) : 0,
            flowerPatches: tier([(5, 1), (10, 2), (40, 3), (70, 4), (120, 5), (200, 6)]),
            trees:         tier([(20, 1), (65, 2), (120, 3)]),
            butterflies:   tier([(75, 2), (150, 3)]),
            fireflies:     tier([(100, 4), (200, 6)]),
            hasLake:       n >= 30,
            hasBridge:     n >= 50,
            hasGardenDecor: n >= 45)
    }
}

extension GardenSnapshot {
    var unlocks: GardenUnlocks { .derive(totalEntries: totalEntries) }
}
