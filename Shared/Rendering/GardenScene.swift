import SwiftUI

/// Deterministic RNG (SplitMix64) so particle layout is identical wherever the same seed is used —
/// the app and the widget draw the *same* garden.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed != 0 ? seed : 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func double(in lo: Double, _ hi: Double) -> Double {
        lo + (Double(next() >> 11) / Double(1 << 53)) * (hi - lo)
    }
}

/// The garden, rendered from a `GardenSnapshot` and nothing else.
///
/// This single view is the entire visual layer the app **and** the Phase 4 widget use. Set
/// `animated: false` for static contexts (widgets, snapshots, reduce-motion) and it renders one
/// crisp frame; set it `true` and a `TimelineView` drives gentle sway, drifting fireflies/motes, and
/// the welcome-back revival sequence.
struct GardenSceneView: View {
    let snapshot: GardenSnapshot
    var animated: Bool = true
    var artProvider: GardenArtProvider = ProceduralGardenArt()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var revivalStart: Date?

    /// Frame rate is capped at 15fps — plenty for gentle pixel motion and easy on the battery. The
    /// timeline pauses entirely when motion is off, off-screen, or the user prefers reduced motion.
    private var frameInterval: Double { 1.0 / 15.0 }
    private var motionEnabled: Bool { animated && !reduceMotion && scenePhase != .background }
    private let revivalDuration: Double = 1.8

    var body: some View {
        TimelineView(.animation(minimumInterval: frameInterval, paused: !motionEnabled)) { timeline in
            let now = timeline.date
            let progress = revivalProgress(now: now)
            let style = effectiveStyle(at: progress)
            let time = motionEnabled ? now.timeIntervalSinceReferenceDate : 0

            Canvas(opaque: true, rendersAsynchronously: false) { context, size in
                draw(into: context, size: size, style: style, time: time, seed: snapshot.renderSeed)
            }
            .saturation(style.saturation)
            .brightness(style.brightness)
        }
        .onAppear { if snapshot.isReviving { revivalStart = Date() } }
        .onChange(of: snapshot.isReviving) { _, reviving in
            revivalStart = reviving ? Date() : nil
        }
        // The pixel art is decorative; VoiceOver hears the full state instead.
        .accessibilityElement()
        .accessibilityLabel(Text(GardenCopy.accessibilityDescription(
            growth: snapshot.growthStage,
            vitality: snapshot.vitality,
            isReviving: snapshot.isReviving,
            lastEntry: snapshot.lastEntryDate)))
    }

    // MARK: Revival timing

    private func revivalProgress(now: Date) -> Double {
        guard snapshot.isReviving else { return 1 }      // not reviving → show the style as-is
        guard motionEnabled, let start = revivalStart else { return 1 } // static → jump to final
        return min(1, max(0, now.timeIntervalSince(start) / revivalDuration))
    }

    private func effectiveStyle(at progress: Double) -> GardenStyle {
        let target = GardenStyle.make(for: snapshot)
        guard snapshot.isReviving else { return target }
        return GardenStyle.lerp(GardenStyle.preRevival(target: target), target, progress)
    }

    // MARK: Drawing

    private func draw(into context: GraphicsContext, size: CGSize, style: GardenStyle, time: Double, seed: UInt64) {
        drawSky(context, size, style)
        let groundY = (size.height * 0.82).rounded()
        let scale = max(2, floor(size.height * 0.70 / 20))   // 20 = sprite grid height
        drawSoil(context, size, groundY: groundY, unit: scale)
        drawPlant(context, base: CGPoint(x: (size.width / 2).rounded(), y: groundY),
                  scale: scale, style: style, time: time)
        drawParticles(context, size, groundY: groundY, style: style, time: time, seed: seed)
    }

    private func drawSky(_ context: GraphicsContext, _ size: CGSize, _ style: GardenStyle) {
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .linearGradient(
                Gradient(colors: [style.skyTop.color, style.skyBottom.color]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: size.height)))
    }

    private func drawSoil(_ context: GraphicsContext, _ size: CGSize, groundY: CGFloat, unit: CGFloat) {
        context.fill(Path(CGRect(x: 0, y: groundY, width: size.width, height: size.height - groundY)),
                     with: .color(GardenPalette.soilLight.color))
        // A lighter crumbly top edge, drawn one "pixel" tall for a tidy pixel-art seam.
        context.fill(Path(CGRect(x: 0, y: groundY, width: size.width, height: unit)),
                     with: .color(GardenPalette.soilTop.color))
        // A few deterministic darker specks for texture (no randomness across processes).
        var rng = SeededGenerator(seed: 0x5011 &+ UInt64(size.width.rounded()))
        let specks = Int((size.width / unit) / 6)
        for _ in 0..<max(2, specks) {
            let x = (rng.double(in: 0, Double(size.width)) / Double(unit)).rounded() * Double(unit)
            let y = groundY + unit * CGFloat(Int(rng.double(in: 1, 4)))
            context.fill(Path(CGRect(x: x, y: Double(y), width: Double(unit), height: Double(unit))),
                         with: .color(GardenPalette.soilDark.color))
        }
    }

    private func drawPlant(_ context: GraphicsContext, base: CGPoint, scale: CGFloat, style: GardenStyle, time: Double) {
        let frames = artProvider.plantFrames(for: snapshot.growthStage)
        guard !frames.isEmpty else { return }
        let frame = frames.count > 1 ? frames[Int(time * 4) % frames.count] : frames[0]

        let sway = sin(time * style.swaySpeed * 2 * .pi) * style.swayDegrees
        let lean = sway + style.droopDegrees * 0.5            // gentle constant lean when wilting
        let sag = 1 - min(0.18, style.droopDegrees / 100)     // and a little vertical sag

        var plant = context
        plant.translateBy(x: base.x, y: base.y)
        plant.rotate(by: .degrees(lean))
        plant.scaleBy(x: 1, y: sag)
        frame.draw(into: plant, scale: scale, bottomCenter: .zero)
    }

    private func drawParticles(_ context: GraphicsContext, _ size: CGSize, groundY: CGFloat, style: GardenStyle, time: Double, seed: UInt64) {
        guard style.ambientOpacity > 0.01 else { return }
        var rng = SeededGenerator(seed: seed)

        // Fireflies — warm glows that drift and pulse.
        for _ in 0..<style.fireflyCount {
            let bx = rng.double(in: 0.12, 0.88) * Double(size.width)
            let by = rng.double(in: 0.12, 0.62) * Double(groundY)
            let phase = rng.double(in: 0, 2 * .pi)
            let x = bx + sin(time * 0.6 + phase) * Double(size.width) * 0.04
            let y = by + cos(time * 0.45 + phase) * Double(size.height) * 0.03
            let pulse = 0.55 + 0.45 * sin(time * 1.3 + phase)
            let alpha = pulse * style.ambientOpacity

            let glowR = Double(size.height) * 0.06
            let glowRect = CGRect(x: x - glowR, y: y - glowR, width: glowR * 2, height: glowR * 2)
            context.fill(Path(ellipseIn: glowRect),
                         with: .radialGradient(
                            Gradient(colors: [GardenPalette.firefly.color.opacity(0.5 * alpha), .clear]),
                            center: CGPoint(x: x, y: y), startRadius: 0, endRadius: glowR))
            let coreR = max(1.5, Double(size.height) * 0.012)
            context.fill(Path(ellipseIn: CGRect(x: x - coreR, y: y - coreR, width: coreR * 2, height: coreR * 2)),
                         with: .color(GardenPalette.firefly.color.opacity(alpha)))
        }

        // Motes — tiny pale specks drifting slowly upward.
        for _ in 0..<style.moteCount {
            let bx = rng.double(in: 0.05, 0.95) * Double(size.width)
            let span = Double(groundY) * 0.9
            let drift = (rng.double(in: 0, span) + time * 6).truncatingRemainder(dividingBy: span)
            let y = Double(groundY) - drift
            let s = max(1.5, Double(size.height) * 0.01)
            context.fill(Path(CGRect(x: bx, y: y, width: s, height: s)),
                         with: .color(GardenPalette.mote.color.opacity(0.4 * style.ambientOpacity)))
        }
    }
}
