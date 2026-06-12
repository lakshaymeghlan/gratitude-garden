import SwiftUI

/// Deterministic RNG (SplitMix64) so scenery layout is identical wherever the same seed is used —
/// the app and the widget draw the same world, and the meadow is stable as it grows.
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

/// The living world.
///
/// **Artwork-driven:** each `WorldStage` shows a dedicated background image (`world_0`…`world_6`)
/// supplied by a `GardenWorldArt` provider — the art itself communicates growth. The renderer then
/// composites the shared, separate layers on top: **vitality** (a saturation/brightness filter),
/// **particles** (fireflies + motes), and the **revival** animation. If no artwork is present yet,
/// it falls back to the procedural landscape so the app always renders.
///
/// Growth (which image) and vitality (how it's tinted) stay independent, exactly as before. Used by
/// both the app and the widget; `animated: false` renders one still frame.
struct GardenSceneView: View {
    let snapshot: GardenSnapshot
    var animated: Bool = true
    var worldArt: GardenWorldArt = AssetWorldArt()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var revivalStart: Date?

    private let worldSeed: UInt64 = 0xA11CE5EED
    private var frameInterval: Double { 1.0 / 15.0 }
    private var motionEnabled: Bool { animated && !reduceMotion && scenePhase != .background }
    private let revivalDuration: Double = 1.8

    var body: some View {
        TimelineView(.animation(minimumInterval: frameInterval, paused: !motionEnabled)) { timeline in
            let progress = revivalProgress(now: timeline.date)
            let style = effectiveStyle(at: progress)
            let time = motionEnabled ? timeline.date.timeIntervalSinceReferenceDate : 0

            ZStack {
                background(style: style, time: time)
                    .saturation(style.saturation)
                    .brightness(style.brightness)

                // Overlay: fireflies + motes, above the artwork (kept un-desaturated so light stays warm).
                Canvas { context, size in
                    drawParticles(context, size, horizon: size.height * 0.58,
                                  style: style, time: time, seed: snapshot.renderSeed)
                }
                .allowsHitTesting(false)
            }
            .clipped()
        }
        .onAppear { if snapshot.isReviving { revivalStart = Date() } }
        .onChange(of: snapshot.isReviving) { _, reviving in
            revivalStart = reviving ? Date() : nil
        }
        .accessibilityElement()
        .accessibilityLabel(Text(GardenCopy.accessibilityDescription(
            growth: snapshot.growthStage,
            vitality: snapshot.vitality,
            isReviving: snapshot.isReviving,
            lastEntry: snapshot.lastEntryDate)))
    }

    /// The world image for this stage, or the procedural landscape if no artwork exists yet.
    @ViewBuilder
    private func background(style: GardenStyle, time: Double) -> some View {
        if let image = worldArt.image(for: snapshot.worldStage) {
            image
                .resizable()
                .interpolation(.high)            // illustrated art; switch to .none for pixel art
                .aspectRatio(contentMode: .fill)
        } else {
            Canvas(opaque: true, rendersAsynchronously: false) { context, size in
                drawProceduralLandscape(into: context, size: size, style: style, time: time)
            }
        }
    }

    // MARK: Revival timing

    private func revivalProgress(now: Date) -> Double {
        guard snapshot.isReviving else { return 1 }
        guard motionEnabled, let start = revivalStart else { return 1 }
        return min(1, max(0, now.timeIntervalSince(start) / revivalDuration))
    }

    private func effectiveStyle(at progress: Double) -> GardenStyle {
        let target = GardenStyle.make(for: snapshot)
        guard snapshot.isReviving else { return target }
        return GardenStyle.lerp(GardenStyle.preRevival(target: target), target, progress)
    }

    // MARK: - Procedural fallback landscape (used only when no artwork is present)

    private func drawProceduralLandscape(into context: GraphicsContext, size: CGSize, style: GardenStyle, time: Double) {
        let stage = snapshot.worldStage.rawValue
        let horizon = (size.height * 0.58).rounded()
        let unit = max(1.5, size.height / 140)

        drawSky(context, size, style, horizon: horizon)
        drawSunGlow(context, size)
        drawMountains(context, size, style, horizon: horizon)
        drawClouds(context, size, time: time)
        drawHorizonHaze(context, size, style, horizon: horizon)
        drawLand(context, size, horizon: horizon, stage: stage)
        if stage >= 3 { drawPath(context, size, horizon: horizon) }
        drawScenery(context, size, horizon: horizon, unit: unit, stage: stage, style: style, time: time)
    }

    private func drawSky(_ ctx: GraphicsContext, _ size: CGSize, _ style: GardenStyle, horizon: CGFloat) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: [style.skyTop.color, style.skyBottom.color]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon)))
    }

    private func drawSunGlow(_ ctx: GraphicsContext, _ size: CGSize) {
        let c = CGPoint(x: size.width * 0.24, y: size.height * 0.18)
        let r = size.height * 0.5
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                 with: .radialGradient(
                    Gradient(colors: [GardenPalette.petalWhite.color.opacity(0.85),
                                      GardenPalette.petalYellow.color.opacity(0.25), .clear]),
                    center: c, startRadius: 0, endRadius: r))
    }

    private func drawMountains(_ ctx: GraphicsContext, _ size: CGSize, _ style: GardenStyle, horizon: CGFloat) {
        drawBlockyRange(ctx, size, baseY: horizon, peakFrac: 0.40, phase: 1.3, step: max(6, size.width / 36),
                        haze: 0.62, opacity: 0.7, skyTint: style.skyTop)
        drawBlockyRange(ctx, size, baseY: horizon, peakFrac: 0.50, phase: 3.9, step: max(5, size.width / 44),
                        haze: 0.32, opacity: 0.9, skyTint: style.skyTop)
        drawBlockyRange(ctx, size, baseY: horizon, peakFrac: 0.58, phase: 6.1, step: max(4, size.width / 52),
                        haze: 0.08, opacity: 1.0, skyTint: style.skyTop)
    }

    private func drawBlockyRange(_ ctx: GraphicsContext, _ size: CGSize, baseY: CGFloat, peakFrac: CGFloat,
                                 phase: Double, step: CGFloat, haze: Double, opacity: Double, skyTint: RGB) {
        let rock = GardenPalette.mountainRock.lerp(to: skyTint, haze)
        let snow = GardenPalette.mountainSnow.lerp(to: skyTint, haze * 0.6)
        let peak = size.height * peakFrac
        var path = Path()
        path.move(to: CGPoint(x: 0, y: baseY))
        var x: CGFloat = 0
        while x <= size.width + step {
            let t = Double(x / size.width)
            let valley = 0.42 + 0.58 * abs(2 * t - 1)
            let n = (sin(Double(x) * 0.018 + phase) + sin(Double(x) * 0.052 + phase * 1.7)) * 0.5
            let h = peak * CGFloat(valley) * CGFloat(0.72 + 0.28 * n)
            let y = ((baseY - h) / step).rounded() * step
            path.addLine(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x + step, y: y))
            x += step
        }
        path.addLine(to: CGPoint(x: size.width, y: baseY))
        path.closeSubpath()
        ctx.fill(path, with: .linearGradient(
            Gradient(stops: [
                .init(color: snow.color.opacity(opacity), location: 0.0),
                .init(color: snow.color.opacity(opacity), location: 0.30),
                .init(color: rock.color.opacity(opacity), location: 0.48),
                .init(color: rock.color.opacity(opacity), location: 1.0),
            ]),
            startPoint: CGPoint(x: 0, y: baseY - peak), endPoint: CGPoint(x: 0, y: baseY)))
    }

    private func drawHorizonHaze(_ ctx: GraphicsContext, _ size: CGSize, _ style: GardenStyle, horizon: CGFloat) {
        let band = size.height * 0.14
        ctx.fill(Path(CGRect(x: 0, y: horizon - band, width: size.width, height: band)),
                 with: .linearGradient(Gradient(colors: [.clear, style.skyBottom.color.opacity(0.75)]),
                                       startPoint: CGPoint(x: 0, y: horizon - band),
                                       endPoint: CGPoint(x: 0, y: horizon)))
    }

    private func drawClouds(_ ctx: GraphicsContext, _ size: CGSize, time: Double) {
        for i in 0..<3 {
            let span = size.width + 120
            let drift = (size.width * CGFloat(0.15 + 0.3 * Double(i)) + CGFloat(time * 5)).truncatingRemainder(dividingBy: span) - 60
            let y = size.height * (0.10 + 0.05 * CGFloat(i))
            let r = size.height * 0.04
            for (dx, dy, s) in [(-r, 0.0 as CGFloat, 1.0 as CGFloat), (r * 0.8, 0, 0.9), (0, -r * 0.5, 0.7)] {
                ctx.fill(Path(ellipseIn: CGRect(x: drift + dx, y: y + dy, width: r * 2 * s, height: r * 1.4 * s)),
                         with: .color(GardenPalette.cloud.color.opacity(0.8)))
            }
        }
    }

    private func drawLand(_ ctx: GraphicsContext, _ size: CGSize, horizon: CGFloat, stage: Int) {
        ctx.fill(Path(CGRect(x: 0, y: horizon, width: size.width, height: size.height - horizon)),
                 with: .linearGradient(Gradient(colors: [GardenPalette.hillBack.color, GardenPalette.hillFront.color]),
                                       startPoint: CGPoint(x: 0, y: horizon),
                                       endPoint: CGPoint(x: 0, y: size.height)))
        let layers = stage >= 4 ? 3 : (stage >= 2 ? 2 : 1)
        for layer in 0..<layers {
            let baseY = horizon + CGFloat(layer) * (size.height - horizon) * 0.12
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: baseY))
            var x: CGFloat = 0
            while x <= size.width {
                let n = sin(Double(x) * 0.014 + Double(layer) * 2.1)
                let y = (baseY + CGFloat(n) * size.height * 0.035).rounded()
                path.addLine(to: CGPoint(x: x.rounded(), y: y))
                x += 6
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
            ctx.fill(path, with: .color(GardenPalette.hillFront.color.opacity(0.55)))
        }
    }

    private func drawPath(_ ctx: GraphicsContext, _ size: CGSize, horizon: CGFloat) {
        let topX = size.width * 0.50, topW = size.width * 0.025
        let botX = size.width * 0.42, botW = size.width * 0.16
        var p = Path()
        p.move(to: CGPoint(x: topX - topW / 2, y: horizon + (size.height - horizon) * 0.10))
        p.addLine(to: CGPoint(x: topX + topW / 2, y: horizon + (size.height - horizon) * 0.10))
        p.addLine(to: CGPoint(x: botX + botW / 2, y: size.height))
        p.addLine(to: CGPoint(x: botX - botW / 2, y: size.height))
        p.closeSubpath()
        ctx.fill(p, with: .color(GardenPalette.soilTop.color.opacity(0.8)))
    }

    private func drawScenery(_ ctx: GraphicsContext, _ size: CGSize, horizon: CGFloat, unit: CGFloat,
                             stage: Int, style: GardenStyle, time: Double) {
        let yLow = horizon - (size.height * 0.02)
        let yHigh = size.height - unit
        let span = yHigh - yLow
        let s = min(stage, 6)

        let carpetCounts = [40, 130, 280, 480, 700, 950, 1200]
        let clumpCounts  = [4, 14, 30, 55, 85, 115, 140]
        let treeCounts   = [0, 0, 1, 3, 5, 8, 11]
        let varietyCount = max(1, min(GardenPalette.flowerVarieties.count, s + 1))

        var cRng = SeededGenerator(seed: worldSeed ^ 0xCA47)
        for _ in 0..<carpetCounts[s] {
            let depth = CGFloat(cRng.double(in: 0, 1))
            let x = CGFloat(cRng.double(in: 0, 1)) * size.width
            let y = yLow + depth * span
            let color = GardenPalette.flowerVarieties[Int(cRng.next() % UInt64(varietyCount))].color
            let dot = max(1, unit * (0.25 + depth * 0.6))
            ctx.fill(Path(CGRect(x: x, y: y, width: dot, height: dot)), with: .color(color))
        }

        var tRng = SeededGenerator(seed: worldSeed ^ 0x7EE5)
        for _ in 0..<treeCounts[s] {
            let x = CGFloat(tRng.double(in: 0.06, 0.94)) * size.width
            let y = yLow + CGFloat(tRng.double(in: 0.05, 0.35)) * span
            let ph = tRng.double(in: 0, 6.28)
            drawTree(ctx, base: CGPoint(x: x, y: y), unit: unit * 2.0,
                     sway: sway(time: time, phase: ph, style: style) * unit * 0.5)
        }

        var fRng = SeededGenerator(seed: worldSeed ^ 0xF10E)
        var clumps: [(x: CGFloat, y: CGFloat, ph: Double, color: Int)] = []
        for _ in 0..<clumpCounts[s] {
            let x = CGFloat(fRng.double(in: 0, 1)) * size.width
            let depth = CGFloat(fRng.double(in: 0, 1))
            let y = yLow + depth * span
            clumps.append((x, y, fRng.double(in: 0, 6.28), Int(fRng.next() % UInt64(varietyCount))))
        }
        for f in clumps.sorted(by: { $0.y < $1.y }) {
            let depth = span > 0 ? (f.y - yLow) / span : 0
            let fs = unit * (0.7 + depth * 1.6)
            let lean = CGFloat(style.droopDegrees) * 0.10 * fs
            let sway = sway(time: time, phase: f.ph, style: style) * fs * 0.5 * (0.4 + depth)
            drawFlowerClump(ctx, base: CGPoint(x: f.x, y: f.y), s: fs,
                            petal: GardenPalette.flowerVarieties[f.color], sway: sway + lean)
        }
    }

    private func sway(time: Double, phase: Double, style: GardenStyle) -> CGFloat {
        guard time != 0, style.swayDegrees > 0 else { return 0 }
        return CGFloat(sin(time * style.swaySpeed * 2 * .pi + phase)) * CGFloat(style.swayDegrees)
    }

    private func drawFlowerClump(_ ctx: GraphicsContext, base: CGPoint, s: CGFloat, petal: RGB, sway: CGFloat) {
        drawFlower(ctx, base: base, s: s, petal: petal, sway: sway)
        drawFlower(ctx, base: CGPoint(x: base.x - s * 1.4, y: base.y + s * 0.4), s: s * 0.8, petal: petal, sway: sway * 0.8)
        drawFlower(ctx, base: CGPoint(x: base.x + s * 1.4, y: base.y + s * 0.2), s: s * 0.85, petal: petal, sway: sway * 0.9)
    }

    private func drawFlower(_ ctx: GraphicsContext, base: CGPoint, s: CGFloat, petal: RGB, sway: CGFloat) {
        let headX = base.x + sway
        let headY = base.y - 3 * s
        let stem = GardenPalette.stemLight.color
        for i in 0...3 {
            let t = CGFloat(i) / 3
            let x = base.x + (headX - base.x) * t
            let y = base.y + (headY - base.y) * t
            ctx.fill(Path(CGRect(x: x - s * 0.5, y: y, width: s, height: s)), with: .color(stem))
        }
        let p = petal.color
        ctx.fill(Path(CGRect(x: headX - s * 0.5, y: headY - 1.5 * s, width: s, height: s)), with: .color(p))
        ctx.fill(Path(CGRect(x: headX - s * 0.5, y: headY + 0.5 * s, width: s, height: s)), with: .color(p))
        ctx.fill(Path(CGRect(x: headX - 1.5 * s, y: headY - 0.5 * s, width: s, height: s)), with: .color(p))
        ctx.fill(Path(CGRect(x: headX + 0.5 * s, y: headY - 0.5 * s, width: s, height: s)), with: .color(p))
        ctx.fill(Path(CGRect(x: headX - 0.5 * s, y: headY - 0.5 * s, width: s, height: s)),
                 with: .color(GardenPalette.flowerCenter.color))
    }

    private func drawTree(_ ctx: GraphicsContext, base: CGPoint, unit: CGFloat, sway: CGFloat) {
        let trunkW = unit * 0.8, trunkH = unit * 2.2
        ctx.fill(Path(CGRect(x: base.x - trunkW / 2, y: base.y - trunkH, width: trunkW, height: trunkH)),
                 with: .color(GardenPalette.soilDark.color))
        let cx = base.x + sway, cy = base.y - trunkH - unit * 1.1
        let r = unit * 1.6
        ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                 with: .color(GardenPalette.leafMid.color))
        ctx.fill(Path(ellipseIn: CGRect(x: cx - r * 0.7, y: cy - r * 1.2, width: r * 1.3, height: r * 1.3)),
                 with: .color(GardenPalette.leafLight.color))
    }

    // MARK: - Ambient particles overlay (fireflies + motes) — over artwork or fallback alike

    private func drawParticles(_ ctx: GraphicsContext, _ size: CGSize, horizon: CGFloat,
                               style: GardenStyle, time: Double, seed: UInt64) {
        guard style.ambientOpacity > 0.01 else { return }
        var rng = SeededGenerator(seed: seed)
        let bandTop = horizon * 0.7
        let bandBottom = horizon + (size.height - horizon) * 0.55

        for _ in 0..<style.fireflyCount {
            let bx = rng.double(in: 0.1, 0.9) * Double(size.width)
            let by = Double(bandTop) + rng.double(in: 0, 1) * Double(bandBottom - bandTop)
            let phase = rng.double(in: 0, 2 * .pi)
            let x = bx + sin(time * 0.6 + phase) * Double(size.width) * 0.04
            let y = by + cos(time * 0.45 + phase) * Double(size.height) * 0.03
            let pulse = 0.55 + 0.45 * sin(time * 1.3 + phase)
            let alpha = pulse * style.ambientOpacity
            let glowR = Double(size.height) * 0.05
            ctx.fill(Path(ellipseIn: CGRect(x: x - glowR, y: y - glowR, width: glowR * 2, height: glowR * 2)),
                     with: .radialGradient(Gradient(colors: [GardenPalette.firefly.color.opacity(0.5 * alpha), .clear]),
                                           center: CGPoint(x: x, y: y), startRadius: 0, endRadius: glowR))
            let coreR = max(1.5, Double(size.height) * 0.012)
            ctx.fill(Path(ellipseIn: CGRect(x: x - coreR, y: y - coreR, width: coreR * 2, height: coreR * 2)),
                     with: .color(GardenPalette.firefly.color.opacity(alpha)))
        }

        for _ in 0..<style.moteCount {
            let bx = rng.double(in: 0.0, 1.0) * Double(size.width)
            let travel = Double(size.height) * 0.5
            let drift = (rng.double(in: 0, travel) + time * 6).truncatingRemainder(dividingBy: travel)
            let y = Double(bandBottom) - drift
            let m = max(1.5, Double(size.height) * 0.009)
            ctx.fill(Path(CGRect(x: bx, y: y, width: m, height: m)),
                     with: .color(GardenPalette.mote.color.opacity(0.4 * style.ambientOpacity)))
        }
    }
}
