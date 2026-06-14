import CoreGraphics

/// One placed flower in the Garden zone.
struct GardenFlower {
    let x: CGFloat
    let y: CGFloat
    let color: Int
}

/// Lifetime flower layout: **one flower per gratitude entry, ever** (`totalEntries`). Flowers are
/// permanent — they're a function of lifetime count only, so missing days never removes them.
///
/// They grow as a *place*, not a counter:
///  • Flowers cluster into **patches** (stable, hand-placed anchors in the Garden zone).
///  • New entries fill the least-full open patch → existing patches **densify** evenly…
///  • …and new patches **open** at thresholds → the garden **spreads**.
///  • Color **variety widens** as the lifetime count grows.
/// Every flower's position is derived purely from its index, so flower *i* never moves — growth only
/// ever *adds*. (Deterministic ⇒ identical in app and widget.)
enum GardenFlowers {
    static let maxDrawn = 280   // visual cap (≈9 months daily); entries beyond still count, just not drawn

    // Patch anchors across the Garden zone (x ∈ [100,240]); earlier ones open first.
    private static let anchors: [(CGFloat, CGFloat)] = [
        (112, 150), (150, 158), (128, 128), (178, 150), (150, 178), (198, 134), (118, 172),
        (210, 158), (168, 124), (226, 146), (140, 140), (192, 174), (218, 122), (234, 166),
    ]
    // Flower index at which each successive patch opens.
    private static let openAt: [Int] = [0, 4, 9, 16, 26, 40, 58, 80, 108, 140, 178, 220, 264, 300]

    static func layout(totalEntries: Int) -> [GardenFlower] {
        let count = min(totalEntries, maxDrawn)
        guard count > 0 else { return [] }
        let varieties = max(1, GardenPalette.flowerVarieties.count)
        let radiusX: CGFloat = 26, radiusY: CGFloat = 15

        var perPatch = [Int](repeating: 0, count: anchors.count)
        var rngs = (0..<anchors.count).map { SeededGenerator(seed: gardenCellSeed(0xF10E, $0, 0xBED)) }
        var result: [GardenFlower] = []
        result.reserveCapacity(count)

        for i in 0..<count {
            // How many patches are open at this point.
            var open = 0
            for t in openAt where t <= i { open += 1 }
            open = max(1, min(open, anchors.count))

            // Add to the least-full open patch → even densification + spread.
            var pj = 0
            for j in 1..<open where perPatch[j] < perPatch[pj] { pj = j }
            perPatch[pj] += 1

            // Centre-biased offset within the patch (stable: the i-th draw of this patch's RNG).
            let b1 = (rngs[pj].double(in: -1, 1) + rngs[pj].double(in: -1, 1)) / 2
            let b2 = (rngs[pj].double(in: -1, 1) + rngs[pj].double(in: -1, 1)) / 2
            let x = anchors[pj].0 + CGFloat(b1) * radiusX
            let y = anchors[pj].1 + CGFloat(b2) * radiusY

            // Variety widens over a lifetime; each patch has a dominant colour with occasional accents.
            let variety = max(1, min(varieties, 1 + i / 16))
            let dominant = pj % varieties
            let pick = rngs[pj].double(in: 0, 1)
            let color = pick < 0.82 ? min(dominant, variety - 1) : Int(rngs[pj].next() % UInt64(variety))

            result.append(GardenFlower(x: x, y: y, color: color))
        }
        return result
    }
}
