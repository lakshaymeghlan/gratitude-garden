import SwiftUI

/// Real-time lighting for the world, driven purely by the **device clock** — completely separate from
/// progression and from vitality. The same world looks bright at 9am, golden at 7pm, and dark-blue
/// with stars + glowing windows at midnight. Values are smoothly interpolated between keyframes so the
/// light shifts gradually across the day rather than snapping between four states.
struct GardenLighting {
    var skyTop: RGB
    var skyBottom: RGB
    var sunCore: RGB        // the sun (or moon) disc colour
    var ambientTint: RGB    // a wash laid over the whole scene to set the mood

    var sunX: CGFloat       // sun/moon position as a fraction of the view (0…1)
    var sunY: CGFloat
    var sunRadiusScale: CGFloat   // × view height
    var sunOpacity: Double

    var ambientOpacity: Double
    var starsOpacity: Double
    var windowGlow: Double  // 0 (off) … 1 (windows glowing warmly)
    var shadowDir: CGFloat  // −1 (shadows fall left) … +1 (right)
    var shadowScale: CGFloat // shadow length multiplier (≈0.9 noon … ≈2.5 low sun)

    var isNight: Bool { starsOpacity > 0.35 }

    // MARK: Keyframes through the day (hour → look). Linearly interpolated, wrapping at 24h.
    private struct Key { let h: Double; let l: GardenLighting }

    private static let night = GardenLighting(
        skyTop: RGB(r: 26, g: 32, b: 62), skyBottom: RGB(r: 52, g: 60, b: 96),
        sunCore: RGB(r: 224, g: 230, b: 238), ambientTint: RGB(r: 22, g: 30, b: 74),
        sunX: 0.76, sunY: 0.15, sunRadiusScale: 0.10, sunOpacity: 0.55,
        ambientOpacity: 0.34, starsOpacity: 0.95, windowGlow: 1.0, shadowDir: 0, shadowScale: 1.0)

    private static let morning = GardenLighting(
        skyTop: RGB(r: 174, g: 208, b: 228), skyBottom: RGB(r: 240, g: 232, b: 212),
        sunCore: RGB(r: 255, g: 246, b: 214), ambientTint: RGB(r: 255, g: 244, b: 222),
        sunX: 0.24, sunY: 0.30, sunRadiusScale: 0.30, sunOpacity: 0.70,
        ambientOpacity: 0.06, starsOpacity: 0.0, windowGlow: 0.12, shadowDir: 1.0, shadowScale: 1.7)

    private static let day = GardenLighting(
        skyTop: RGB(r: 146, g: 198, b: 230), skyBottom: RGB(r: 226, g: 238, b: 226),
        sunCore: RGB(r: 255, g: 252, b: 230), ambientTint: RGB(r: 255, g: 255, b: 255),
        sunX: 0.52, sunY: 0.09, sunRadiusScale: 0.34, sunOpacity: 0.62,
        ambientOpacity: 0.0, starsOpacity: 0.0, windowGlow: 0.0, shadowDir: 0.15, shadowScale: 0.9)

    private static let afternoon = GardenLighting(
        skyTop: RGB(r: 150, g: 196, b: 226), skyBottom: RGB(r: 232, g: 234, b: 214),
        sunCore: RGB(r: 255, g: 248, b: 220), ambientTint: RGB(r: 255, g: 250, b: 236),
        sunX: 0.66, sunY: 0.13, sunRadiusScale: 0.33, sunOpacity: 0.64,
        ambientOpacity: 0.02, starsOpacity: 0.0, windowGlow: 0.0, shadowDir: -0.4, shadowScale: 1.2)

    private static let evening = GardenLighting(
        skyTop: RGB(r: 244, g: 168, b: 118), skyBottom: RGB(r: 250, g: 214, b: 150),
        sunCore: RGB(r: 255, g: 194, b: 128), ambientTint: RGB(r: 248, g: 156, b: 94),
        sunX: 0.83, sunY: 0.33, sunRadiusScale: 0.34, sunOpacity: 0.88,
        ambientOpacity: 0.18, starsOpacity: 0.0, windowGlow: 0.5, shadowDir: -1.0, shadowScale: 2.5)

    private static let dusk = GardenLighting(
        skyTop: RGB(r: 92, g: 84, b: 132), skyBottom: RGB(r: 196, g: 132, b: 120),
        sunCore: RGB(r: 240, g: 172, b: 142), ambientTint: RGB(r: 70, g: 64, b: 116),
        sunX: 0.90, sunY: 0.42, sunRadiusScale: 0.20, sunOpacity: 0.40,
        ambientOpacity: 0.24, starsOpacity: 0.30, windowGlow: 0.85, shadowDir: -1.0, shadowScale: 2.2)

    private static let keys: [Key] = [
        Key(h: 0.0,  l: night),   Key(h: 5.0,  l: night),     Key(h: 7.5,  l: morning),
        Key(h: 11.0, l: day),     Key(h: 15.0, l: afternoon), Key(h: 18.0, l: evening),
        Key(h: 19.8, l: dusk),    Key(h: 21.5, l: night),     Key(h: 24.0, l: night),
    ]

    /// Lighting for a fractional hour in [0, 24).
    static func at(hour: Double) -> GardenLighting {
        let h = hour.truncatingRemainder(dividingBy: 24)
        var lo = keys[0], hi = keys[keys.count - 1]
        for i in 0..<(keys.count - 1) where h >= keys[i].h && h <= keys[i + 1].h {
            lo = keys[i]; hi = keys[i + 1]; break
        }
        let span = hi.h - lo.h
        let t = span > 0 ? (h - lo.h) / span : 0
        return lerp(lo.l, hi.l, t)
    }

    /// Lighting for a moment in time (uses the device's local calendar).
    static func at(date: Date, calendar: Calendar = .current) -> GardenLighting {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let hour = Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60.0
        return at(hour: hour)
    }

    static func lerp(_ a: GardenLighting, _ b: GardenLighting, _ t: Double) -> GardenLighting {
        let t = min(max(t, 0), 1)
        func f(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * CGFloat(t) }
        func d(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        return GardenLighting(
            skyTop: a.skyTop.lerp(to: b.skyTop, t), skyBottom: a.skyBottom.lerp(to: b.skyBottom, t),
            sunCore: a.sunCore.lerp(to: b.sunCore, t), ambientTint: a.ambientTint.lerp(to: b.ambientTint, t),
            sunX: f(a.sunX, b.sunX), sunY: f(a.sunY, b.sunY),
            sunRadiusScale: f(a.sunRadiusScale, b.sunRadiusScale), sunOpacity: d(a.sunOpacity, b.sunOpacity),
            ambientOpacity: d(a.ambientOpacity, b.ambientOpacity), starsOpacity: d(a.starsOpacity, b.starsOpacity),
            windowGlow: d(a.windowGlow, b.windowGlow), shadowDir: f(a.shadowDir, b.shadowDir),
            shadowScale: f(a.shadowScale, b.shadowScale))
    }
}
