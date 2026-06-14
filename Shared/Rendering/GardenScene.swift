import SwiftUI

/// Deterministic RNG (SplitMix64) for reproducible, infinite, app/widget-identical world content.
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

/// The garden as a calm, composed illustration — navigable and full-bleed, drawn through a
/// `GardenCamera`. Deliberately built for **visual hierarchy**, not detail count:
///   • Background (muted): clean snow-capped mountain silhouettes + sky.
///   • Midground (slightly richer): a soft hill band + sparse trees + a path that leads the eye in.
///   • Foreground (most colorful): flowers grouped into **patches/meadows** — the focal point.
/// Growth (`worldStage`) expands and enriches the flower fields; vitality (`GardenStyle`) tints.
struct GardenSceneView: View {
    let snapshot: GardenSnapshot
    var animated: Bool = true
    var interactive: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var camera = GardenCamera.default
    @State private var panStart: CGPoint?
    @State private var zoomStart: CGFloat?
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

            Canvas(opaque: true, rendersAsynchronously: false) { context, size in
                draw(into: context, size: size, camera: interactive ? camera : .default, style: style, time: time)
            }
            .saturation(style.saturation)
            .brightness(style.brightness)
        }
        .contentShape(Rectangle())
        .gesture(explorationGesture, including: interactive ? .all : .none)
        .onAppear { if snapshot.isReviving { revivalStart = Date() } }
        .onChange(of: snapshot.isReviving) { _, reviving in revivalStart = reviving ? Date() : nil }
        .accessibilityElement()
        .accessibilityLabel(Text(GardenCopy.accessibilityDescription(
            growth: snapshot.growthStage, vitality: snapshot.vitality,
            isReviving: snapshot.isReviving, lastEntry: snapshot.lastEntryDate)))
    }

    // MARK: Pan + zoom + momentum

    private var explorationGesture: some Gesture {
        let pan = DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = panStart ?? camera.position
                if panStart == nil { panStart = start }
                camera = GardenCamera(position: CGPoint(x: start.x - value.translation.width / camera.zoom,
                                                        y: start.y - value.translation.height / camera.zoom),
                                      zoom: camera.zoom).clamped()
            }
            .onEnded { value in
                let start = panStart ?? camera.position
                panStart = nil
                let target = CGPoint(x: start.x - value.predictedEndTranslation.width / camera.zoom,
                                     y: start.y - value.predictedEndTranslation.height / camera.zoom)
                let settled = GardenCamera(position: target, zoom: camera.zoom).clamped()
                if motionEnabled { withAnimation(.easeOut(duration: 0.7)) { camera = settled } }
                else { camera = settled }
            }
        let zoom = MagnifyGesture()
            .onChanged { value in
                let base = zoomStart ?? camera.zoom
                if zoomStart == nil { zoomStart = base }
                camera = GardenCamera(position: camera.position, zoom: base * value.magnification).clamped()
            }
            .onEnded { _ in zoomStart = nil }
        return pan.simultaneously(with: zoom)
    }

    // MARK: Revival

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

    // MARK: - Render (back → front, with a clear value/colour hierarchy)

    private func draw(into ctx: GraphicsContext, size: CGSize, camera: GardenCamera, style: GardenStyle, time: Double) {
        let unit = max(2, size.height / 150) * camera.zoom
        let stage = snapshot.worldStage.rawValue
        let horizon = camera.horizonScreenY(size: size)

        drawSky(ctx, size, style)
        drawSunBloom(ctx, size)
        drawClouds(ctx, size, camera, time: time)
        drawMountains(ctx, size, camera, horizon: horizon, style: style)
        drawHills(ctx, size, camera, horizon: horizon)
        drawGround(ctx, size, horizon: horizon)
        drawPath(ctx, size, camera)
        drawTrees(ctx, size, camera, stage: stage, unit: unit, style: style, time: time)
        drawFlowerPatches(ctx, size, camera, stage: stage, unit: unit, style: style, time: time)
        drawCreatures(ctx, size, camera, stage: stage, unit: unit, style: style, time: time)
        drawAtmosphere(ctx, size)
    }

    private func snap(_ v: CGFloat, _ px: CGFloat) -> CGFloat { (v / px).rounded() * px }

    // MARK: Background — sky, sun, clouds (muted, recessive)

    private func drawSky(_ ctx: GraphicsContext, _ size: CGSize, _ style: GardenStyle) {
        let warmHorizon = style.skyBottom.lerp(to: GardenPalette.petalYellow, 0.16)
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(stops: [
                    .init(color: style.skyTop.color, location: 0),
                    .init(color: style.skyTop.lerp(to: style.skyBottom, 0.55).color, location: 0.45),
                    .init(color: warmHorizon.color, location: 0.72)]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height * 0.6)))
    }

    private func drawSunBloom(_ ctx: GraphicsContext, _ size: CGSize) {
        let c = CGPoint(x: size.width * 0.28, y: size.height * 0.16)
        let r = size.height * 0.5
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                 with: .radialGradient(Gradient(colors: [GardenPalette.petalWhite.color.opacity(0.75),
                                                         GardenPalette.petalYellow.color.opacity(0.2), .clear]),
                                       center: c, startRadius: 0, endRadius: r))
        let core = size.height * 0.04
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - core, y: c.y - core, width: core * 2, height: core * 2)),
                 with: .color(GardenPalette.petalWhite.color.opacity(0.8)))
    }

    /// A few soft, clean clouds — calm, low-contrast, far back.
    private func drawClouds(_ ctx: GraphicsContext, _ size: CGSize, _ camera: GardenCamera, time: Double) {
        let parallax: CGFloat = 0.12, cell: CGFloat = 900
        let (minX, maxX) = camera.visibleWorldX(parallax: parallax, size: size, margin: cell)
        for c in Int(floor(minX / cell))...Int(ceil(maxX / cell)) {
            var rng = SeededGenerator(seed: gardenCellSeed(worldSeed, c, 0xC10D))
            let wx = CGFloat(c) * cell + CGFloat(rng.double(in: 0, Double(cell)))
            let wy = CGFloat(rng.double(in: -360, -220)) + CGFloat(sin(time * 0.04 + rng.double(in: 0, 6)) * 5)
            let p = camera.project(CGPoint(x: wx, y: wy), parallax: parallax, size: size)
            let r: CGFloat = size.height * 0.045 * camera.zoom
            let puffs: [(CGFloat, CGFloat, CGFloat)] = [(-1.3, 0.1, 1.0), (0.0, -0.35, 1.25), (1.3, 0.1, 0.95)]
            let cloudColor = GardenPalette.cloud.color.opacity(0.7)
            for puff in puffs {
                let x: CGFloat = p.x + puff.0 * r
                let y: CGFloat = p.y + puff.1 * r
                let w: CGFloat = r * 2 * puff.2
                let h: CGFloat = r * 1.25 * puff.2
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: w, height: h)), with: .color(cloudColor))
            }
        }
    }

    // MARK: Background — mountains (clean silhouettes, strong layering, atmospheric haze)

    private func drawMountains(_ ctx: GraphicsContext, _ size: CGSize, _ camera: GardenCamera, horizon: CGFloat, style: GardenStyle) {
        // Far → near: each range darker/closer and a touch more saturated. Heavily hazed so they
        // recede behind the flowers and never compete with the foreground.
        drawRange(ctx, size, camera, horizon: horizon, parallax: 0.18, peakFrac: 0.34, phase: 1.1,
                  haze: 0.74, snowAt: 0.62, sky: style.skyTop)
        drawRange(ctx, size, camera, horizon: horizon, parallax: 0.30, peakFrac: 0.46, phase: 3.8,
                  haze: 0.52, snowAt: 0.50, sky: style.skyTop)
        drawRange(ctx, size, camera, horizon: horizon, parallax: 0.44, peakFrac: 0.58, phase: 6.2,
                  haze: 0.34, snowAt: 0.46, sky: style.skyTop)
    }

    private func drawRange(_ ctx: GraphicsContext, _ size: CGSize, _ camera: GardenCamera, horizon: CGFloat,
                           parallax: CGFloat, peakFrac: CGFloat, phase: Double, haze: Double, snowAt: CGFloat, sky: RGB) {
        let rock = GardenPalette.mountainRock.lerp(to: sky, haze)
        let snow = GardenPalette.mountainSnow.lerp(to: sky, haze * 0.5)
        let peakWorld = size.height * peakFrac
        let step: CGFloat = 5

        func topY(_ sx: CGFloat) -> CGFloat {
            let worldX = (sx - size.width / 2) / camera.zoom + camera.position.x * parallax
            let n = sin(Double(worldX) * 0.0016 + phase) * 0.6 + sin(Double(worldX) * 0.0041 + phase * 1.9) * 0.4
            let h = peakWorld * CGFloat(0.5 + 0.42 * n)
            return camera.project(CGPoint(x: worldX, y: -h), parallax: parallax, size: size).y
        }

        var ridge = Path()
        ridge.move(to: CGPoint(x: 0, y: horizon))
        var sx: CGFloat = 0
        while sx <= size.width { ridge.addLine(to: CGPoint(x: sx, y: topY(sx))); sx += step }
        ridge.addLine(to: CGPoint(x: size.width, y: horizon))
        ridge.closeSubpath()

        // Clip to the silhouette, then snow on top, rock below a clean snow line → tidy caps.
        var mc = ctx
        mc.clip(to: ridge)
        let snowLineY = horizon - peakWorld * camera.zoom * snowAt
        mc.fill(Path(CGRect(origin: .zero, size: size)), with: .color(snow.color))
        mc.fill(Path(CGRect(x: 0, y: snowLineY, width: size.width, height: max(0, size.height - snowLineY))),
                with: .color(rock.color))
    }

    // MARK: Midground — hill band (slightly richer than the mountains, behind the meadow)

    private func drawHills(_ ctx: GraphicsContext, _ size: CGSize, _ camera: GardenCamera, horizon: CGFloat) {
        let parallax: CGFloat = 0.55, step: CGFloat = 6
        let color = GardenPalette.hillBack.lerp(to: GardenPalette.skyBottom, 0.18)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height))
        var sx: CGFloat = 0
        var started = false
        while sx <= size.width {
            let worldX = (sx - size.width / 2) / camera.zoom + camera.position.x * parallax
            let n = sin(Double(worldX) * 0.0055 + 2.1) * 0.7 + sin(Double(worldX) * 0.013 + 0.5) * 0.3
            let y = camera.project(CGPoint(x: worldX, y: -28 + CGFloat(n) * 34), parallax: parallax, size: size).y
            if !started { path.addLine(to: CGPoint(x: 0, y: y)); started = true }
            path.addLine(to: CGPoint(x: sx, y: y))
            sx += step
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        ctx.fill(path, with: .color(color.color))
    }

    // MARK: Foreground ground — clean meadow gradient + warm light

    private func drawGround(_ ctx: GraphicsContext, _ size: CGSize, horizon: CGFloat) {
        let h = max(0, size.height - horizon)
        guard h > 0 else { return }
        let near = GardenPalette.meadow.lerp(to: GardenPalette.leafDark, 0.28)
        ctx.fill(Path(CGRect(x: 0, y: horizon, width: size.width, height: h)),
                 with: .linearGradient(Gradient(stops: [
                    .init(color: GardenPalette.hillFront.lerp(to: GardenPalette.skyBottom, 0.12).color, location: 0),
                    .init(color: GardenPalette.meadow.color, location: 0.35),
                    .init(color: near.color, location: 1)]),
                                       startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: size.height)))
        ctx.fill(Path(CGRect(x: 0, y: horizon, width: size.width, height: h)),
                 with: .linearGradient(Gradient(colors: [GardenPalette.petalYellow.color.opacity(0.14), .clear]),
                                       startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: size.width * 0.85, y: horizon)))
    }

    // MARK: The path — a clear anchor that leads the eye toward the valley

    private func drawPath(_ ctx: GraphicsContext, _ size: CGSize, _ camera: GardenCamera) {
        let parallax: CGFloat = 1.0
        let edge = GardenPalette.soilTop.lerp(to: GardenPalette.soilDark, 0.30)
        let fill = GardenPalette.soilTop

        func center(_ worldY: CGFloat) -> CGPoint {
            let worldX = sin(Double(worldY) * 0.012) * 34          // gentle S-curve, anchored near origin
            return camera.project(CGPoint(x: CGFloat(worldX), y: worldY), parallax: parallax, size: size)
        }
        func halfWidth(_ worldY: CGFloat) -> CGFloat {
            let t = max(0, min(1, (worldY - 8) / 320))             // far → near
            return (3 + 70 * t) * camera.zoom
        }
        func ribbon(widen: CGFloat) -> Path {
            var p = Path()
            var ys = [CGFloat](); var y: CGFloat = 8; while y <= 330 { ys.append(y); y += 14 }
            var first = true
            for wy in ys {
                let c = center(wy), hw = halfWidth(wy) + widen
                let pt = CGPoint(x: c.x - hw, y: c.y)
                if first { p.move(to: pt); first = false } else { p.addLine(to: pt) }
            }
            for wy in ys.reversed() {
                let c = center(wy), hw = halfWidth(wy) + widen
                p.addLine(to: CGPoint(x: c.x + hw, y: c.y))
            }
            p.closeSubpath()
            return p
        }
        ctx.fill(ribbon(widen: max(1, size.width * 0.006)), with: .color(edge.color.opacity(0.9)))
        ctx.fill(ribbon(widen: 0), with: .color(fill.color))
    }

    // MARK: Midground — sparse trees on the hill line (muted, not competing)

    private func drawTrees(_ ctx: GraphicsContext, _ size: CGSize, _ camera: GardenCamera,
                           stage: Int, unit: CGFloat, style: GardenStyle, time: Double) {
        guard stage >= 3 else { return }
        let parallax: CGFloat = 0.6, cell: CGFloat = 520
        let perCell = [0, 0, 0, 1, 1, 2, 2][min(stage, 6)]
        let (minX, maxX) = camera.visibleWorldX(parallax: parallax, size: size, margin: cell)
        for c in Int(floor(minX / cell))...Int(ceil(maxX / cell)) {
            var rng = SeededGenerator(seed: gardenCellSeed(worldSeed, c, 0x77EE))
            for _ in 0..<perCell {
                let wx = CGFloat(c) * cell + CGFloat(rng.double(in: 0, Double(cell)))
                let p = camera.project(CGPoint(x: wx, y: -18), parallax: parallax, size: size)
                if p.x < -60 || p.x > size.width + 60 { continue }
                let sway = swayOffset(time: time, phase: rng.double(in: 0, 6), style: style) * unit * 0.4
                drawTree(ctx, base: p, unit: unit * 1.8, sway: sway)
            }
        }
    }

    // MARK: Foreground — flowers grouped into patches (the focal point)

    private func drawFlowerPatches(_ ctx: GraphicsContext, _ size: CGSize, _ camera: GardenCamera,
                                   stage: Int, unit: CGFloat, style: GardenStyle, time: Double) {
        let parallax: CGFloat = 1.0, cell: CGFloat = 300
        let patchesPerCell = [1, 1, 2, 2, 3, 3, 4][min(stage, 6)]   // few, intentional groupings
        let perPatch       = [8, 14, 22, 30, 40, 52, 66][min(stage, 6)]
        let patchRadius    = [50, 64, 78, 92, 108, 124, 140][min(stage, 6)]
        let varieties = max(2, min(GardenPalette.flowerVarieties.count, stage + 2))
        let (minX, maxX) = camera.visibleWorldX(parallax: parallax, size: size, margin: cell)

        struct Flower { let p: CGPoint; let depth: CGFloat; let s: CGFloat; let color: Int; let phase: Double }
        var flowers: [Flower] = []

        for c in Int(floor(minX / cell))...Int(ceil(maxX / cell)) {
            var rng = SeededGenerator(seed: gardenCellSeed(worldSeed, c, 0xF10E))
            for _ in 0..<patchesPerCell {
                let cx = CGFloat(c) * cell + CGFloat(rng.double(in: 0, Double(cell)))
                let cDepth = CGFloat(rng.double(in: 0, 1))
                let cy = 40 + cDepth * 300
                let dominant = Int(rng.next() % UInt64(varieties))
                let rx = CGFloat(patchRadius) * CGFloat(rng.double(in: 0.7, 1.1))
                let ry = CGFloat(patchRadius) * 0.45
                for _ in 0..<perPatch {
                    // centre-biased offset → dense middle, sparse edges (nature grows in clumps)
                    let b1: Double = (rng.double(in: -1, 1) + rng.double(in: -1, 1)) / 2
                    let b2: Double = (rng.double(in: -1, 1) + rng.double(in: -1, 1)) / 2
                    let wx: CGFloat = cx + CGFloat(b1) * rx
                    let wy: CGFloat = max(18, cy + CGFloat(b2) * ry)
                    let p = camera.project(CGPoint(x: wx, y: wy), parallax: parallax, size: size)
                    if p.x < -40 || p.x > size.width + 40 || p.y < -40 || p.y > size.height + 40 { continue }
                    let depth: CGFloat = max(0, min(1, (wy - 18) / 300))
                    let s: CGFloat = max(2, unit * (0.7 + depth * 1.6))
                    let color = rng.double(in: 0, 1) < 0.82 ? dominant : Int(rng.next() % UInt64(varieties))
                    flowers.append(Flower(p: p, depth: depth, s: s, color: color, phase: rng.double(in: 0, 6.28)))
                }
            }
        }
        for f in flowers.sorted(by: { $0.depth < $1.depth }) {
            let lean = CGFloat(style.droopDegrees) * 0.10 * f.s
            let sway = swayOffset(time: time, phase: f.phase, style: style) * f.s * 0.5 * (0.4 + f.depth)
            drawFlower(ctx, base: f.p, s: f.s, petal: GardenPalette.flowerVarieties[f.color], sway: sway + lean)
        }
    }

    private func drawCreatures(_ ctx: GraphicsContext, _ size: CGSize, _ camera: GardenCamera,
                               stage: Int, unit: CGFloat, style: GardenStyle, time: Double) {
        if stage >= 3 && style.ambientOpacity > 0.4 {
            let parallax: CGFloat = 1.0, cell: CGFloat = 650
            let (minX, maxX) = camera.visibleWorldX(parallax: parallax, size: size, margin: cell)
            for c in Int(floor(minX / cell))...Int(ceil(maxX / cell)) {
                var rng = SeededGenerator(seed: gardenCellSeed(worldSeed, c, 0xB077))
                for _ in 0..<Int(rng.double(in: 0, 2)) {
                    let baseX = CGFloat(c) * cell + CGFloat(rng.double(in: 0, Double(cell)))
                    let ph = rng.double(in: 0, 6.28)
                    let wx = baseX + CGFloat(sin(time * 0.4 + ph)) * 40
                    let wy = 40 + CGFloat(rng.double(in: 0, 130)) + CGFloat(cos(time * 0.6 + ph)) * 16
                    let p = camera.project(CGPoint(x: wx, y: wy), parallax: parallax, size: size)
                    if p.x < -20 || p.x > size.width + 20 { continue }
                    drawButterfly(ctx, at: p, s: unit * 0.8, flap: sin(time * 6 + ph),
                                  color: GardenPalette.flowerVarieties[Int(rng.next() % 5)])
                }
            }
        }
        drawParticles(ctx, size, camera, style: style, time: time)
    }

    private func drawAtmosphere(_ ctx: GraphicsContext, _ size: CGSize) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let r = max(size.width, size.height) * 0.75
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .radialGradient(Gradient(stops: [.init(color: .clear, location: 0.62),
                                                         .init(color: .black.opacity(0.20), location: 1)]),
                                       center: c, startRadius: 0, endRadius: r))
    }

    private func swayOffset(time: Double, phase: Double, style: GardenStyle) -> CGFloat {
        guard time != 0, style.swayDegrees > 0 else { return 0 }
        return CGFloat(sin(time * style.swaySpeed * 2 * .pi + phase)) * CGFloat(style.swayDegrees)
    }

    // MARK: Sprite primitives

    private func drawFlower(_ ctx: GraphicsContext, base: CGPoint, s: CGFloat, petal: RGB, sway: CGFloat) {
        // grounding shadow
        ctx.fill(Path(ellipseIn: CGRect(x: base.x - s * 0.9, y: base.y - s * 0.22, width: s * 1.8, height: s * 0.45)),
                 with: .color(.black.opacity(0.10)))
        let headX = base.x + sway, headY = base.y - 3 * s
        let stem = GardenPalette.stemLight.color
        for i in 0...3 {
            let t = CGFloat(i) / 3
            ctx.fill(Path(CGRect(x: base.x + (headX - base.x) * t - s * 0.5, y: base.y + (headY - base.y) * t,
                                 width: s, height: s)), with: .color(stem))
        }
        let hi = petal.lerp(to: GardenPalette.petalWhite, 0.35)
        ctx.fill(Path(CGRect(x: headX - s * 0.5, y: headY - 1.5 * s, width: s, height: s)), with: .color(hi.color))
        ctx.fill(Path(CGRect(x: headX - s * 0.5, y: headY + 0.5 * s, width: s, height: s)), with: .color(petal.color))
        ctx.fill(Path(CGRect(x: headX - 1.5 * s, y: headY - 0.5 * s, width: s, height: s)), with: .color(hi.color))
        ctx.fill(Path(CGRect(x: headX + 0.5 * s, y: headY - 0.5 * s, width: s, height: s)), with: .color(petal.color))
        ctx.fill(Path(CGRect(x: headX - 0.5 * s, y: headY - 0.5 * s, width: s, height: s)),
                 with: .color(GardenPalette.flowerCenter.color))
    }

    private func drawTree(_ ctx: GraphicsContext, base: CGPoint, unit: CGFloat, sway: CGFloat) {
        ctx.fill(Path(ellipseIn: CGRect(x: base.x - unit * 1.3, y: base.y - unit * 0.25, width: unit * 2.6, height: unit * 0.6)),
                 with: .color(.black.opacity(0.10)))
        let trunkW = unit * 0.7, trunkH = unit * 2.0
        ctx.fill(Path(CGRect(x: base.x - trunkW / 2, y: base.y - trunkH, width: trunkW, height: trunkH)),
                 with: .color(GardenPalette.soilDark.color))
        let cx = base.x + sway, cy = base.y - trunkH - unit, r = unit * 1.6
        let canopy = GardenPalette.leafMid.lerp(to: GardenPalette.skyBottom, 0.12)
        ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)), with: .color(GardenPalette.leafDark.color))
        ctx.fill(Path(ellipseIn: CGRect(x: cx - r * 0.8, y: cy - r * 1.0, width: r * 1.6, height: r * 1.6)), with: .color(canopy.color))
    }

    private func drawButterfly(_ ctx: GraphicsContext, at p: CGPoint, s: CGFloat, flap: Double, color: RGB) {
        let w = s * (0.5 + 0.5 * abs(flap))
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - w, y: p.y - s * 0.6, width: w, height: s * 1.2)), with: .color(color.color))
        ctx.fill(Path(ellipseIn: CGRect(x: p.x, y: p.y - s * 0.6, width: w, height: s * 1.2)), with: .color(color.color))
        ctx.fill(Path(CGRect(x: p.x - s * 0.08, y: p.y - s * 0.6, width: s * 0.16, height: s * 1.2)), with: .color(GardenPalette.soilDark.color))
    }

    private func drawParticles(_ ctx: GraphicsContext, _ size: CGSize, _ camera: GardenCamera, style: GardenStyle, time: Double) {
        guard style.ambientOpacity > 0.01 else { return }
        var rng = SeededGenerator(seed: snapshot.renderSeed)
        let horizon = camera.horizonScreenY(size: size)
        let bandTop = horizon * 0.75, bandBottom = horizon + (size.height - horizon) * 0.5
        for _ in 0..<style.fireflyCount {
            let bx = rng.double(in: 0.12, 0.88) * Double(size.width)
            let by = Double(bandTop) + rng.double(in: 0, 1) * Double(bandBottom - bandTop)
            let phase = rng.double(in: 0, 2 * .pi)
            let x = bx + sin(time * 0.6 + phase) * Double(size.width) * 0.035
            let y = by + cos(time * 0.45 + phase) * Double(size.height) * 0.025
            let alpha = (0.5 + 0.45 * sin(time * 1.3 + phase)) * style.ambientOpacity
            let glowR = Double(size.height) * 0.04
            ctx.fill(Path(ellipseIn: CGRect(x: x - glowR, y: y - glowR, width: glowR * 2, height: glowR * 2)),
                     with: .radialGradient(Gradient(colors: [GardenPalette.firefly.color.opacity(0.5 * alpha), .clear]),
                                           center: CGPoint(x: x, y: y), startRadius: 0, endRadius: glowR))
            let coreR = max(1.5, Double(size.height) * 0.01)
            ctx.fill(Path(ellipseIn: CGRect(x: x - coreR, y: y - coreR, width: coreR * 2, height: coreR * 2)),
                     with: .color(GardenPalette.firefly.color.opacity(alpha)))
        }
    }
}
