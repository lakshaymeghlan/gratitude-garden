import SwiftUI

/// A small RGB value type so palette colors can be **interpolated** (for revival fades and the
/// drooping→dormant sky shift) without needing the SwiftUI environment to resolve a `Color`.
struct RGB: Equatable {
    let r, g, b: Double   // 0...255

    var color: Color { Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: 1) }

    func lerp(to other: RGB, _ t: Double) -> RGB {
        let t = min(max(t, 0), 1)
        return RGB(r: r + (other.r - r) * t,
                   g: g + (other.g - g) * t,
                   b: b + (other.b - b) * t)
    }
}

/// The cohesive, cozy palette — warm greens, soft yellows, creams, muted browns, and gentle floral
/// accents. **Deliberately limited and unsaturated** (no neon, no "mobile-game" candy colors) to
/// read as Stardew/Spiritfarer-warm rather than retro-arcade.
///
/// Drooping and dormancy do **not** swap to a second palette — the renderer simply lowers
/// `saturation`/`brightness` and shifts the sky toward the cooler dusk tones below, which keeps the
/// whole garden cohesive at every state.
enum GardenPalette {

    // MARK: Sky — a warm dusk gradient (thriving) easing to a cooler, peaceful dusk (dormant)
    static let skyTop          = RGB(r: 214, g: 226, b: 222)   // soft sage mist
    static let skyBottom       = RGB(r: 243, g: 230, b: 205)   // warm cream glow
    static let skyTopDormant   = RGB(r: 150, g: 162, b: 172)   // cool, restful dusk
    static let skyBottomDormant = RGB(r: 206, g: 190, b: 168)  // dim warm horizon

    // MARK: Soil — muted browns
    static let soilDark  = RGB(r: 90,  g: 70,  b: 51)
    static let soilLight = RGB(r: 122, g: 92,  b: 64)
    static let soilTop   = RGB(r: 138, g: 106, b: 72)

    // MARK: Foliage — warm greens
    static let leafDark  = RGB(r: 62,  g: 107, b: 67)
    static let leafMid   = RGB(r: 92,  g: 154, b: 91)
    static let leafLight = RGB(r: 143, g: 192, b: 121)
    static let stemDark  = RGB(r: 94,  g: 126, b: 69)
    static let stemLight = RGB(r: 123, g: 158, b: 90)
    static let bud       = RGB(r: 136, g: 166, b: 94)

    // MARK: Flowers — gentle accents
    static let petalPink     = RGB(r: 232, g: 166, b: 161)
    static let petalPinkDark = RGB(r: 217, g: 139, b: 134)
    static let petalYellow   = RGB(r: 242, g: 208, b: 139)
    static let petalCream    = RGB(r: 248, g: 235, b: 201)
    static let flowerCenter  = RGB(r: 230, g: 184, b: 92)

    // MARK: Light — warm firefly glow + pale floating motes
    static let firefly = RGB(r: 251, g: 233, b: 160)
    static let mote    = RGB(r: 248, g: 238, b: 210)

    // MARK: Landscape — meadow flower varieties (soft, cohesive — no neon)
    static let petalPurple = RGB(r: 178, g: 150, b: 214)
    static let petalCoral  = RGB(r: 232, g: 122, b: 110)
    static let petalWhite  = RGB(r: 245, g: 244, b: 236)

    // MARK: Landscape — terrain
    static let hillBack      = RGB(r: 150, g: 186, b: 120)
    static let hillFront     = RGB(r: 110, g: 162, b: 96)
    static let meadow        = RGB(r: 130, g: 176, b: 104)
    static let mountainRock  = RGB(r: 150, g: 156, b: 170)
    static let mountainSnow  = RGB(r: 236, g: 240, b: 244)
    static let cloud         = RGB(r: 250, g: 248, b: 242)

    /// The flower varieties unlocked as the world grows (index 0 first).
    static let flowerVarieties: [RGB] = [petalPink, petalYellow, petalWhite, petalPurple, petalCoral, flowerCenter]

    // MARK: Home + props (the cozy focal point)
    static let wallCream  = RGB(r: 244, g: 234, b: 210)
    static let wallWood   = RGB(r: 168, g: 120, b: 82)
    static let wallStone  = RGB(r: 206, g: 204, b: 198)
    static let wallWizard = RGB(r: 196, g: 186, b: 214)
    static let roofRed    = RGB(r: 188, g: 96,  b: 78)
    static let roofDark   = RGB(r: 78,  g: 86,  b: 102)
    static let roofThatch = RGB(r: 198, g: 162, b: 96)
    static let roofWizard = RGB(r: 120, g: 96,  b: 168)
    static let doorBrown  = RGB(r: 112, g: 76,  b: 52)
    static let windowGlow = RGB(r: 250, g: 224, b: 148)
    static let woodFence  = RGB(r: 158, g: 122, b: 86)
    static let plotGrass  = RGB(r: 146, g: 190, b: 112)
}
