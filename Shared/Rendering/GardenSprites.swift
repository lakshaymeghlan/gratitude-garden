import SwiftUI

/// Supplies the art for a growth stage. The renderer depends only on this protocol, so swapping in
/// commissioned bitmap art later means writing one new conformer (e.g. `ImageGardenArtProvider`)
/// and injecting it — **no change to `GardenScene` or any animation code.**
///
/// `plantFrames` returns one or more frames:
///  • 1 frame  → motion is procedural (the scene applies gentle sway/droop transforms).
///  • N frames → frame-by-frame animation (the scene cycles frames over time). Commissioned art can
///    use this for richer hand-animated sway cycles.
protocol GardenArtProvider {
    func plantFrames(for stage: GrowthStage) -> [PixelSprite]
}

/// The procedural pixel-art that ships today. All sprites share one 15-wide grid (odd width → a true
/// center column at index 7) and are anchored at the bottom-center so they sit on the soil and sway
/// from their base. Heights vary by drawing into the lower rows; the scene scales them uniformly.
struct ProceduralGardenArt: GardenArtProvider {

    func plantFrames(for stage: GrowthStage) -> [PixelSprite] {
        switch stage {
        case .seed:        return [Self.seed]
        case .sprout:      return [Self.sprout]
        case .seedling:    return [Self.seedling]
        case .budding:     return [Self.budding]
        case .blooming:    return [Self.blooming]
        case .flourishing: return [Self.flourishing]
        }
    }

    // Legend shared by every sprite. '.' (and any unlisted char) is transparent.
    private static let legend: [Character: RGB] = [
        "s": GardenPalette.stemLight, "S": GardenPalette.stemDark,
        "l": GardenPalette.leafMid,   "L": GardenPalette.leafDark, "g": GardenPalette.leafLight,
        "b": GardenPalette.bud,       "B": GardenPalette.stemDark,
        "p": GardenPalette.petalPink, "P": GardenPalette.petalPinkDark,
        "y": GardenPalette.petalYellow, "o": GardenPalette.petalCream, "c": GardenPalette.flowerCenter,
        "d": GardenPalette.soilLight, "D": GardenPalette.soilDark,
    ]

    // MARK: Sprites

    static let seed = PixelSprite([
        "...............",
        "...............",
        "...............",
        "...............",
        "...............",
        "...............",
        "...............",
        "...............",
        "...............",
        "...............",
        "...............",
        "...............",
        "...............",
        "...............",
        "...............",
        "...............",
        ".......g.......",
        ".......s.......",
        "......ddd......",
        ".....dDDDd.....",
    ], legend: legend)

    static let sprout = PixelSprite([
        "...............",
        "...............",
        "...............",
        "...............",
        "...............",
        "...............",
        "...............",
        "...............",
        "...............",
        "...............",
        "...............",
        ".......g.......",
        ".......s.......",
        ".....g.s.g.....",
        "....gl.s.lg....",
        ".....l.s.l.....",
        ".......s.......",
        ".......s.......",
        ".......S.......",
        "......LSL......",
    ], legend: legend)

    static let seedling = PixelSprite([
        "...............",
        "...............",
        "...............",
        "...............",
        "...............",
        "...............",
        "...............",
        "...............",
        ".......g.......",
        ".......s.......",
        ".....glslg.....",
        ".......s.......",
        ".......s.......",
        ".....glslg.....",
        ".......s.......",
        ".......s.......",
        ".......s.......",
        ".......S.......",
        ".......S.......",
        "......LSL......",
    ], legend: legend)

    static let budding = PixelSprite([
        "...............",
        "...............",
        "...............",
        "...............",
        "...............",
        ".......b.......",
        "......bbb......",
        "......bBb......",
        ".......s.......",
        ".......s.......",
        ".....glslg.....",
        ".......s.......",
        ".......s.......",
        ".....glslg.....",
        ".......s.......",
        ".......s.......",
        ".......s.......",
        ".......S.......",
        ".......S.......",
        "......LSL......",
    ], legend: legend)

    static let blooming = PixelSprite([
        "...............",
        "...............",
        "...............",
        "......ppp......",
        ".....poyop.....",
        ".....pycyp.....",
        ".....poyop.....",
        "......ppp......",
        ".......s.......",
        ".......s.......",
        ".....glslg.....",
        ".......s.......",
        ".......s.......",
        ".....glslg.....",
        ".......s.......",
        ".......s.......",
        ".......s.......",
        ".......S.......",
        ".......S.......",
        "......LSL......",
    ], legend: legend)

    static let flourishing = PixelSprite([
        "...............",
        "......ppp......",
        ".....poyop.....",
        ".....pycyp.....",
        ".....poyop.....",
        "......ppp......",
        ".......s.......",
        "...ppp.s.ppp...",
        "...pcp.s.pcp...",
        "...ppp.s.ppp...",
        "....l..s..l....",
        "....gl.s.lg....",
        ".....glslg.....",
        ".......s.......",
        ".....glslg.....",
        ".......s.......",
        ".......s.......",
        ".......S.......",
        ".......S.......",
        ".....LLSLL.....",
    ], legend: legend)
}
