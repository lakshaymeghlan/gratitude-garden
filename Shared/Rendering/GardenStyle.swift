import SwiftUI

// MARK: - Snapshot rendering helpers (additive, backwards-compatible — no change to the stored type)

extension GardenSnapshot {
    /// 0...1 droop amount, for *continuous* visual interpolation rather than hard per-level steps.
    var wiltFraction: Double {
        guard wiltLevel > 0 else { return 0 }
        return min(1, Double(wiltLevel) / Double(GardenRules.maxWiltLevel))
    }

    /// Deterministic seed derived from durable state, so the app and the widget lay out fireflies
    /// and motes **identically** (visual parity, no per-process randomness).
    var renderSeed: UInt64 {
        var hash: UInt64 = 14695981039346656037
        let parts: [UInt64] = [
            UInt64(bitPattern: Int64(totalEntries)) &+ 1,
            UInt64(growthStage.rawValue) &+ 7,
            UInt64(bitPattern: Int64(consecutiveDayCount)) &+ 13,
        ]
        for p in parts { hash = (hash ^ p) &* 1099511628211 }
        return hash == 0 ? 0x9E3779B97F4A7C15 : hash
    }
}

/// The garden's appearance expressed as **continuous render parameters**. This is the one place
/// that decides "what thriving/drooping/dormant/reviving *looks like*" — a pure function of the
/// snapshot, so it's trivially unit-tested and identical across app and widget.
struct GardenStyle: Equatable {
    var saturation: Double       // 1.0 = full color → lower = drained
    var brightness: Double       // 0 = neutral → slightly negative = dimmer
    var droopDegrees: Double     // 0 = upright → larger = leaves tilt downward
    var swayDegrees: Double      // sway amplitude
    var swaySpeed: Double        // sway cycles per second-ish
    var fireflyCount: Int
    var moteCount: Int
    var ambientOpacity: Double   // master opacity for fireflies/motes (0 = none)
    var skyTop: RGB
    var skyBottom: RGB

    static func make(for s: GardenSnapshot) -> GardenStyle {
        switch s.vitality {
        case .thriving:
            return GardenStyle(
                saturation: 1.0, brightness: 0.0,
                droopDegrees: 0, swayDegrees: 2.2, swaySpeed: 0.5,
                fireflyCount: s.isReviving ? 7 : fireflies(for: s.growthStage),
                moteCount: 7, ambientOpacity: 1.0,
                skyTop: GardenPalette.skyTop, skyBottom: GardenPalette.skyBottom)

        case .drooping:
            let f = s.wiltFraction
            return GardenStyle(
                saturation: 1.0 - 0.40 * f, brightness: -0.02 * f,
                droopDegrees: 4 + 11 * f, swayDegrees: 1.6 * (1 - 0.5 * f), swaySpeed: 0.4,
                fireflyCount: max(0, 2 - Int((f * 2).rounded())),
                moteCount: max(1, 5 - Int((f * 4).rounded())),
                ambientOpacity: 1.0 - 0.45 * f,
                skyTop: GardenPalette.skyTop.lerp(to: GardenPalette.skyTopDormant, 0.4 * f),
                skyBottom: GardenPalette.skyBottom.lerp(to: GardenPalette.skyBottomDormant, 0.4 * f))

        case .dormant:
            // Resting and peaceful — never dead. Muted, gently lit, barely stirring.
            return GardenStyle(
                saturation: 0.5, brightness: -0.03,
                droopDegrees: 15, swayDegrees: 0.6, swaySpeed: 0.25,
                fireflyCount: 1, moteCount: 1, ambientOpacity: 0.5,
                skyTop: GardenPalette.skyTopDormant, skyBottom: GardenPalette.skyBottomDormant)
        }
    }

    /// The "before" look the revival animation grows *out of*: muted, drooped, lights off. The scene
    /// interpolates from this to `make(for:)` over the welcome-back sequence so flowers straighten,
    /// color returns, and fireflies fade in.
    static func preRevival(target: GardenStyle) -> GardenStyle {
        GardenStyle(
            saturation: 0.5, brightness: -0.03,
            droopDegrees: 15, swayDegrees: 0.6, swaySpeed: 0.3,
            fireflyCount: target.fireflyCount, moteCount: target.moteCount,
            ambientOpacity: 0,
            skyTop: GardenPalette.skyTopDormant, skyBottom: GardenPalette.skyBottomDormant)
    }

    private static func fireflies(for stage: GrowthStage) -> Int {
        switch stage {
        case .seed, .sprout:        return 2
        case .seedling, .budding:   return 4
        case .blooming, .flourishing: return 6
        }
    }

    /// Linear blend between two styles. Continuous fields interpolate; particle counts take `b`'s
    /// (the target's) so they're positioned but faded in via `ambientOpacity`.
    static func lerp(_ a: GardenStyle, _ b: GardenStyle, _ t: Double) -> GardenStyle {
        let t = min(max(t, 0), 1)
        func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        return GardenStyle(
            saturation: mix(a.saturation, b.saturation),
            brightness: mix(a.brightness, b.brightness),
            droopDegrees: mix(a.droopDegrees, b.droopDegrees),
            swayDegrees: mix(a.swayDegrees, b.swayDegrees),
            swaySpeed: mix(a.swaySpeed, b.swaySpeed),
            fireflyCount: b.fireflyCount,
            moteCount: b.moteCount,
            ambientOpacity: mix(a.ambientOpacity, b.ambientOpacity),
            skyTop: a.skyTop.lerp(to: b.skyTop, t),
            skyBottom: a.skyBottom.lerp(to: b.skyBottom, t))
    }
}
