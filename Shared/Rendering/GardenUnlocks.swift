import Foundation

/// What the world contains right now — derived purely from cumulative entries. Progression comes
/// from **unlocking new kinds of things**, not from cranking up density: a flower, then a patch,
/// then a bush, a tree, butterflies, a path, fireflies, a fence, a meadow… Each threshold adds
/// something visibly new. Monotonic (entries only grow), so the garden never loses anything.
struct GardenUnlocks: Equatable {
    var flowers: Int          // discrete flowers dotted near the home (the very first days)
    var flowerPatches: Int    // clustered beds that appear from day ~4
    var bushes: Int
    var trees: Int
    var butterflies: Int
    var fireflies: Int
    var stones: Int
    var hasPath: Bool
    var hasFence: Bool
    var hasSign: Bool
    var hasMeadow: Bool       // large flower fields
    var flourishing: Bool

    static func derive(totalEntries n: Int) -> GardenUnlocks {
        func tier(_ steps: [(Int, Int)]) -> Int {          // first threshold > n wins the previous value
            var v = 0
            for (threshold, value) in steps where n >= threshold { v = value }
            return v
        }
        return GardenUnlocks(
            // Days 0–3: one new flower each day. Then discrete flowers settle and patches take over.
            flowers:       n <= 3 ? max(1, min(4, n + 1)) : 3,
            flowerPatches: tier([(4, 1), (8, 2), (16, 3), (31, 4), (61, 6), (101, 8)]),
            bushes:        tier([(4, 1), (16, 2), (61, 3)]),
            trees:         tier([(16, 1), (31, 2), (61, 3), (101, 4)]),
            butterflies:   tier([(8, 1), (16, 2), (31, 3), (101, 4)]),
            fireflies:     tier([(31, 3), (61, 5), (101, 7)]),
            stones:        tier([(31, 1), (61, 2)]),
            hasPath:       n >= 16,
            hasFence:      n >= 31,
            hasSign:       n >= 31,
            hasMeadow:     n >= 61,
            flourishing:   n >= 101)
    }
}

extension GardenSnapshot {
    /// What's unlocked in this world right now.
    var unlocks: GardenUnlocks { .derive(totalEntries: totalEntries) }
}
