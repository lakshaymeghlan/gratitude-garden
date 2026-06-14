import SwiftUI

/// Deterministic RNG (SplitMix64) for reproducible, app/widget-identical placement.
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

/// The garden as a **cozy, home-centered scene** (Stardew / Cozy Grove feel) — not a procedural
/// landscape. A chosen home sits at the center; the garden grows *outward from it* by **unlocking
/// new things** (flower → patch → bush → tree → butterfly → path → fence → meadow…), so progression
/// is obvious. Layered back→front with a clear hierarchy. Plants are still; only butterflies and
/// fireflies drift. Vitality (`GardenStyle`) tints the whole scene.
struct GardenSceneView: View {
    let snapshot: GardenSnapshot
    var homeStyle: HomeStyle = .cottage
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

    // Home sits here in world space; the garden is composed around it.
    private let homeBaseY: CGFloat = 92

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

    // MARK: Pan + zoom + momentum (gentle, bounded — see GardenCamera.clamped)

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
                if motionEnabled { withAnimation(.easeOut(duration: 0.6)) { camera = settled } }
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

    // MARK: - Render (back → front)

    private func draw(into ctx: GraphicsContext, size: CGSize, camera: GardenCamera, style: GardenStyle, time: Double) {
        let unit = max(2, size.height / 150) * camera.zoom
        let u = unlocks
        drawSky(ctx, size, style)
        drawSun(ctx, size)
        drawDistantMountains(ctx, size, camera, style: style)
        drawHills(ctx, size, camera)
        drawGround(ctx, size, camera)
        drawPlot(ctx, size, camera)
        if u.hasPath { drawPath(ctx, size, camera, unit: unit) }
        drawProps(ctx, size, camera, unit: unit, unlocks: u)
        drawCreatures(ctx, size, camera, unit: unit, unlocks: u, style: style, time: time)
        drawAtmosphere(ctx, size)
    }

    private var unlocks: GardenUnlocks { snapshot.unlocks }

    private func rect(_ ctx: GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: RGB, _ a: Double = 1) {
        ctx.fill(Path(CGRect(x: x, y: y, width: w, height: h)), with: .color(c.color.opacity(a)))
    }
    private func tri(_ ctx: GraphicsContext, _ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ col: RGB) {
        var p = Path(); p.move(to: a); p.addLine(to: b); p.addLine(to: c); p.closeSubpath()
        ctx.fill(p, with: .color(col.color))
    }

    // MARK: Background

    private func drawSky(_ ctx: GraphicsContext, _ size: CGSize, _ style: GardenStyle) {
        let warm = style.skyBottom.lerp(to: GardenPalette.petalYellow, 0.14)
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(stops: [
                    .init(color: style.skyTop.color, location: 0),
                    .init(color: style.skyTop.lerp(to: style.skyBottom, 0.6).color, location: 0.5),
                    .init(color: warm.color, location: 0.8)]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height * 0.55)))
    }

    private func drawSun(_ ctx: GraphicsContext, _ size: CGSize) {
        let c = CGPoint(x: size.width * 0.74, y: size.height * 0.14)
        let r = size.height * 0.34
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                 with: .radialGradient(Gradient(colors: [GardenPalette.petalWhite.color.opacity(0.7),
                                                         GardenPalette.petalYellow.color.opacity(0.18), .clear]),
                                       center: c, startRadius: 0, endRadius: r))
    }

    /// A small, soft, distant range low on the horizon — backdrop only, never dominating.
    private func drawDistantMountains(_ ctx: GraphicsContext, _ size: CGSize, _ camera: GardenCamera, style: GardenStyle) {
        let parallax: CGFloat = 0.25, step: CGFloat = 8
        let peak = size.height * 0.12
        let color = GardenPalette.mountainRock.lerp(to: style.skyTop, 0.66)
        let horizon = camera.horizonScreenY(size: size)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: horizon))
        var sx: CGFloat = 0
        while sx <= size.width {
            let worldX = (sx - size.width / 2) / camera.zoom + camera.position.x * parallax
            let n = sin(Double(worldX) * 0.004 + 1.2) * 0.6 + sin(Double(worldX) * 0.009 + 3.1) * 0.4
            let h = peak * CGFloat(0.5 + 0.5 * n)
            let y = camera.project(CGPoint(x: worldX, y: -h), parallax: parallax, size: size).y
            path.addLine(to: CGPoint(x: sx, y: y))
            sx += step
        }
        path.addLine(to: CGPoint(x: size.width, y: horizon))
        path.closeSubpath()
        ctx.fill(path, with: .color(color.color))
    }

    private func drawHills(_ ctx: GraphicsContext, _ size: CGSize, _ camera: GardenCamera) {
        let parallax: CGFloat = 0.6, step: CGFloat = 8
        let color = GardenPalette.hillBack.lerp(to: GardenPalette.skyBottom, 0.10)
        let horizon = camera.horizonScreenY(size: size)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: horizon))
        var sx: CGFloat = 0
        while sx <= size.width {
            let worldX = (sx - size.width / 2) / camera.zoom + camera.position.x * parallax
            let n = sin(Double(worldX) * 0.006 + 0.7)
            let y = camera.project(CGPoint(x: worldX, y: -10 + CGFloat(n) * 22), parallax: parallax, size: size).y
            path.addLine(to: CGPoint(x: sx, y: y))
            sx += step
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        ctx.fill(path, with: .color(color.color))
    }

    private func drawGround(_ ctx: GraphicsContext, _ size: CGSize, _ camera: GardenCamera) {
        let horizon = camera.horizonScreenY(size: size)
        let h = max(0, size.height - horizon)
        let deep = GardenPalette.meadow.lerp(to: GardenPalette.leafDark, 0.22)
        ctx.fill(Path(CGRect(x: 0, y: horizon, width: size.width, height: h)),
                 with: .linearGradient(Gradient(colors: [GardenPalette.meadow.color, deep.color]),
                                       startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: size.height)))
    }

    /// A soft, slightly-lighter lawn the home sits on — focuses the eye without a hard edge.
    private func drawPlot(_ ctx: GraphicsContext, _ size: CGSize, _ camera: GardenCamera) {
        let c = camera.project(CGPoint(x: 0, y: homeBaseY + 30), parallax: 1.0, size: size)
        let w = size.width * 1.5
        let hgt = size.height * 0.5 * camera.zoom
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - w / 2, y: c.y - hgt / 2, width: w, height: hgt)),
                 with: .radialGradient(Gradient(colors: [GardenPalette.plotGrass.color, GardenPalette.plotGrass.color.opacity(0)]),
                                       center: c, startRadius: 0, endRadius: w * 0.5))
    }

    private func drawPath(_ ctx: GraphicsContext, _ size: CGSize, _ camera: GardenCamera, unit: CGFloat) {
        let topW = unit * 2.4, botW = unit * 7
        let top = camera.project(CGPoint(x: 0, y: homeBaseY + 18), parallax: 1.0, size: size)
        let bot = camera.project(CGPoint(x: 0, y: homeBaseY + 120), parallax: 1.0, size: size)
        var p = Path()
        p.move(to: CGPoint(x: top.x - topW / 2, y: top.y))
        p.addLine(to: CGPoint(x: top.x + topW / 2, y: top.y))
        p.addLine(to: CGPoint(x: bot.x + botW / 2, y: bot.y))
        p.addLine(to: CGPoint(x: bot.x - botW / 2, y: bot.y))
        p.closeSubpath()
        ctx.fill(p, with: .color(GardenPalette.soilTop.color.opacity(0.9)))
    }

    // MARK: Props — composed around the home, filled by unlocks, depth-sorted

    private enum PropKind { case tree, bush, flower, patch, stone, fence, sign, home }
    private struct Prop { let x: CGFloat; let y: CGFloat; let kind: PropKind; let i: Int }

    private func drawProps(_ ctx: GraphicsContext, _ size: CGSize, _ camera: GardenCamera, unit: CGFloat, unlocks u: GardenUnlocks) {
        let treeSlots:   [(CGFloat, CGFloat)] = [(-150, 36), (150, 30), (-94, 22), (98, 26)]
        let bushSlots:   [(CGFloat, CGFloat)] = [(-84, 92), (84, 92), (-108, 82), (108, 82)]
        let flowerSlots: [(CGFloat, CGFloat)] = [(-30, 122), (32, 124), (0, 134), (-58, 128), (58, 130)]
        let patchSlots:  [(CGFloat, CGFloat)] = [(-126, 118), (130, 122), (-58, 152), (64, 154), (0, 170),
                                                 (-152, 102), (150, 106), (44, 140)]
        let stoneSlots:  [(CGFloat, CGFloat)] = [(-112, 136), (118, 140)]

        var props: [Prop] = [Prop(x: 0, y: homeBaseY, kind: .home, i: 0)]
        if u.hasFence { props.append(Prop(x: 0, y: 56, kind: .fence, i: 0)) }
        for k in 0..<min(u.trees, treeSlots.count)   { props.append(Prop(x: treeSlots[k].0,   y: treeSlots[k].1,   kind: .tree,   i: k)) }
        for k in 0..<min(u.bushes, bushSlots.count)  { props.append(Prop(x: bushSlots[k].0,   y: bushSlots[k].1,   kind: .bush,   i: k)) }
        for k in 0..<min(u.flowers, flowerSlots.count) { props.append(Prop(x: flowerSlots[k].0, y: flowerSlots[k].1, kind: .flower, i: k)) }
        for k in 0..<min(u.flowerPatches, patchSlots.count) { props.append(Prop(x: patchSlots[k].0, y: patchSlots[k].1, kind: .patch, i: k)) }
        for k in 0..<min(u.stones, stoneSlots.count) { props.append(Prop(x: stoneSlots[k].0, y: stoneSlots[k].1, kind: .stone, i: k)) }
        if u.hasSign { props.append(Prop(x: 70, y: 146, kind: .sign, i: 0)) }

        for prop in props.sorted(by: { $0.y < $1.y }) {
            let p = camera.project(CGPoint(x: prop.x, y: prop.y), parallax: 1.0, size: size)
            let depth = max(0, min(1, prop.y / 180))
            let m = 0.7 + depth * 0.7
            switch prop.kind {
            case .home:   drawHome(ctx, base: p, hs: unit * 3.0)
            case .tree:   drawTree(ctx, base: p, s: unit * 3.4 * m)
            case .bush:   drawBush(ctx, base: p, s: unit * 2.2 * m)
            case .flower: drawFlower(ctx, base: p, s: unit * 1.4 * m, color: prop.i % GardenPalette.flowerVarieties.count)
            case .patch:  drawPatch(ctx, base: p, s: unit * 1.3 * m, seedIndex: prop.i)
            case .stone:  drawStone(ctx, base: p, s: unit * 1.8 * m)
            case .fence:  drawFence(ctx, size, camera, unit: unit)
            case .sign:   drawSign(ctx, base: p, s: unit * 2.0 * m)
            }
        }
    }

    private func drawCreatures(_ ctx: GraphicsContext, _ size: CGSize, _ camera: GardenCamera,
                               unit: CGFloat, unlocks u: GardenUnlocks, style: GardenStyle, time: Double) {
        let dim = style.ambientOpacity
        guard dim > 0.05 else { return }
        // Butterflies drift over the garden (daytime life).
        for k in 0..<u.butterflies {
            let ph = Double(k) * 1.7 + 0.4
            let wx = CGFloat(-90 + 70 * k) + CGFloat(sin(time * 0.5 + ph)) * 26
            let wy = 70 + CGFloat(k % 2) * 30 + CGFloat(cos(time * 0.7 + ph)) * 14
            let p = camera.project(CGPoint(x: wx, y: wy), parallax: 1.0, size: size)
            drawButterfly(ctx, at: p, s: unit * 1.0, flap: sin(time * 6 + ph),
                          color: GardenPalette.flowerVarieties[k % 5], alpha: dim)
        }
        // Fireflies drift softly.
        for k in 0..<u.fireflies {
            let ph = Double(k) * 0.9 + 1.1
            let wx = CGFloat(-120 + 36 * k) + CGFloat(sin(time * 0.4 + ph)) * 22
            let wy = 60 + CGFloat((k * 23) % 90) + CGFloat(cos(time * 0.5 + ph)) * 16
            let p = camera.project(CGPoint(x: wx, y: wy), parallax: 1.0, size: size)
            let pulse = 0.5 + 0.5 * sin(time * 1.4 + ph)
            let a = pulse * dim
            let gr = unit * 2.2
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - gr, y: p.y - gr, width: gr * 2, height: gr * 2)),
                     with: .radialGradient(Gradient(colors: [GardenPalette.firefly.color.opacity(0.5 * a), .clear]),
                                           center: p, startRadius: 0, endRadius: gr))
            let cr = max(1.5, unit * 0.5)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - cr, y: p.y - cr, width: cr * 2, height: cr * 2)),
                     with: .color(GardenPalette.firefly.color.opacity(a)))
        }
    }

    private func drawAtmosphere(_ ctx: GraphicsContext, _ size: CGSize) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let r = max(size.width, size.height) * 0.78
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .radialGradient(Gradient(stops: [.init(color: .clear, location: 0.64),
                                                         .init(color: .black.opacity(0.18), location: 1)]),
                                       center: c, startRadius: 0, endRadius: r))
    }

    // MARK: Sprites (static — no plant movement)

    private func drawHome(_ ctx: GraphicsContext, base: CGPoint, hs: CGFloat) {
        // grounding shadow
        ctx.fill(Path(ellipseIn: CGRect(x: base.x - hs * 4, y: base.y - hs * 0.5, width: hs * 8, height: hs * 1.1)),
                 with: .color(.black.opacity(0.12)))
        let w = hs * 7, wallH = hs * 4
        let wx = base.x - w / 2, wy = base.y - wallH
        switch homeStyle {
        case .cottage:
            rect(ctx, wx, wy, w, wallH, GardenPalette.wallCream)
            rect(ctx, wx, wy, w, hs * 0.5, GardenPalette.wallCream.lerp(to: .init(r: 255, g: 255, b: 255), 0.3)) // lit top
            tri(ctx, CGPoint(x: wx - hs, y: wy), CGPoint(x: base.x, y: wy - hs * 3), CGPoint(x: wx + w + hs, y: wy), GardenPalette.roofRed)
            rect(ctx, wx + w * 0.62, wy - hs * 2.6, hs * 0.9, hs * 2.6, GardenPalette.roofRed.lerp(to: GardenPalette.soilDark, 0.3)) // chimney
            rect(ctx, base.x - hs * 1.1, base.y - hs * 2.4, hs * 2.2, hs * 2.4, GardenPalette.doorBrown)
            rect(ctx, wx + hs * 0.8, wy + hs * 1.2, hs * 1.6, hs * 1.6, GardenPalette.windowGlow)
        case .japanese:
            rect(ctx, wx, wy, w, wallH, GardenPalette.wallCream.lerp(to: GardenPalette.wallStone, 0.4))
            // wide low dark roof with upturned eaves
            tri(ctx, CGPoint(x: wx - hs * 1.6, y: wy + hs * 0.4), CGPoint(x: base.x, y: wy - hs * 1.8), CGPoint(x: wx + w + hs * 1.6, y: wy + hs * 0.4), GardenPalette.roofDark)
            rect(ctx, wx - hs * 1.6, wy + hs * 0.2, hs * 1.0, hs * 0.5, GardenPalette.roofDark)
            rect(ctx, wx + w + hs * 0.6, wy + hs * 0.2, hs * 1.0, hs * 0.5, GardenPalette.roofDark)
            rect(ctx, base.x - hs * 1.4, base.y - hs * 2.6, hs * 2.8, hs * 2.6, GardenPalette.roofDark.lerp(to: GardenPalette.wallStone, 0.2)) // sliding door frame
            rect(ctx, base.x - hs * 1.1, base.y - hs * 2.3, hs * 2.2, hs * 2.3, GardenPalette.windowGlow.lerp(to: GardenPalette.wallCream, 0.4))
        case .cabin:
            for r in 0..<5 {                                   // stacked log courses
                let shade = r % 2 == 0 ? GardenPalette.wallWood : GardenPalette.wallWood.lerp(to: GardenPalette.soilDark, 0.18)
                rect(ctx, wx, wy + CGFloat(r) * (wallH / 5), w, wallH / 5, shade)
            }
            tri(ctx, CGPoint(x: wx - hs, y: wy), CGPoint(x: base.x, y: wy - hs * 2.8), CGPoint(x: wx + w + hs, y: wy), GardenPalette.roofDark)
            rect(ctx, wx + w * 0.66, wy - hs * 2.4, hs * 0.9, hs * 2.4, GardenPalette.roofDark.lerp(to: GardenPalette.soilDark, 0.2))
            rect(ctx, base.x - hs * 1.0, base.y - hs * 2.2, hs * 2.0, hs * 2.2, GardenPalette.doorBrown.lerp(to: GardenPalette.soilDark, 0.2))
            rect(ctx, wx + hs * 0.9, wy + hs * 1.0, hs * 1.4, hs * 1.4, GardenPalette.windowGlow)
        case .wizard:
            let ww = w * 0.82, wwx = base.x - ww / 2
            rect(ctx, wwx, wy, ww, wallH, GardenPalette.wallWizard)
            tri(ctx, CGPoint(x: wwx - hs * 0.6, y: wy), CGPoint(x: base.x + hs * 0.4, y: wy - hs * 5), CGPoint(x: wwx + ww + hs * 0.6, y: wy), GardenPalette.roofWizard) // tall crooked roof
            rect(ctx, base.x - hs * 0.35, wy - hs * 5.6, hs * 0.7, hs * 0.7, GardenPalette.windowGlow)  // orb on top
            rect(ctx, base.x - hs * 1.0, base.y - hs * 2.2, hs * 2.0, hs * 2.2, GardenPalette.doorBrown)
            rect(ctx, wwx + hs * 0.7, wy + hs * 1.2, hs * 1.3, hs * 1.3, GardenPalette.windowGlow.lerp(to: GardenPalette.petalPurple, 0.2))
        }
    }

    private func drawTree(_ ctx: GraphicsContext, base: CGPoint, s: CGFloat) {
        ctx.fill(Path(ellipseIn: CGRect(x: base.x - s * 1.3, y: base.y - s * 0.25, width: s * 2.6, height: s * 0.6)), with: .color(.black.opacity(0.10)))
        let trunkW = s * 0.7, trunkH = s * 2.2
        rect(ctx, base.x - trunkW / 2, base.y - trunkH, trunkW, trunkH, GardenPalette.soilDark)
        let cy = base.y - trunkH - s
        let r = s * 1.7
        ctx.fill(Path(ellipseIn: CGRect(x: base.x - r, y: cy - r, width: r * 2, height: r * 2)), with: .color(GardenPalette.leafDark.color))
        ctx.fill(Path(ellipseIn: CGRect(x: base.x - r * 0.8, y: cy - r * 1.05, width: r * 1.6, height: r * 1.6)), with: .color(GardenPalette.leafMid.color))
        ctx.fill(Path(ellipseIn: CGRect(x: base.x - r * 0.45, y: cy - r * 1.1, width: r * 0.9, height: r * 0.9)), with: .color(GardenPalette.leafLight.color))
    }

    private func drawBush(_ ctx: GraphicsContext, base: CGPoint, s: CGFloat) {
        ctx.fill(Path(ellipseIn: CGRect(x: base.x - s * 1.2, y: base.y - s * 0.2, width: s * 2.4, height: s * 0.5)), with: .color(.black.opacity(0.10)))
        for (dx, dy, rr) in [(-0.7, 0.0, 1.0), (0.7, 0.0, 1.0), (0.0, -0.4, 1.2)] as [(CGFloat, CGFloat, CGFloat)] {
            let r = s * rr
            ctx.fill(Path(ellipseIn: CGRect(x: base.x + dx * s - r, y: base.y - s * 0.6 + dy * s - r, width: r * 2, height: r * 2)),
                     with: .color(GardenPalette.leafDark.color))
        }
        let r = s * 1.0
        ctx.fill(Path(ellipseIn: CGRect(x: base.x - r, y: base.y - s * 1.0 - r, width: r * 2, height: r * 2)), with: .color(GardenPalette.leafMid.color))
    }

    private func drawFlower(_ ctx: GraphicsContext, base: CGPoint, s: CGFloat, color: Int) {
        let petal = GardenPalette.flowerVarieties[color % GardenPalette.flowerVarieties.count]
        ctx.fill(Path(ellipseIn: CGRect(x: base.x - s * 0.8, y: base.y - s * 0.2, width: s * 1.6, height: s * 0.4)), with: .color(.black.opacity(0.08)))
        let headY = base.y - 2.6 * s
        rect(ctx, base.x - s * 0.25, headY, s * 0.5, 2.6 * s, GardenPalette.stemLight)   // stem (straight, still)
        let hi = petal.lerp(to: GardenPalette.petalWhite, 0.3)
        rect(ctx, base.x - s * 0.5, headY - s, s, s, hi)
        rect(ctx, base.x - s * 1.5, headY, s, s, petal)
        rect(ctx, base.x + s * 0.5, headY, s, s, petal)
        rect(ctx, base.x - s * 0.5, headY + s, s, s, hi)
        rect(ctx, base.x - s * 0.5, headY, s, s, GardenPalette.flowerCenter)
    }

    /// A composed cluster of a few still flowers (one dominant colour) — a flower bed.
    private func drawPatch(_ ctx: GraphicsContext, base: CGPoint, s: CGFloat, seedIndex: Int) {
        var rng = SeededGenerator(seed: gardenCellSeed(worldSeed, seedIndex, 0xBED))
        let dominant = Int(rng.next() % UInt64(GardenPalette.flowerVarieties.count))
        let count = 7
        var pts: [(CGFloat, CGFloat, Int)] = []
        for _ in 0..<count {
            let dx = CGFloat(rng.double(in: -1, 1)) * s * 3.2
            let dy = CGFloat(rng.double(in: -1, 1)) * s * 1.4
            let col = rng.double(in: 0, 1) < 0.8 ? dominant : Int(rng.next() % UInt64(GardenPalette.flowerVarieties.count))
            pts.append((dx, dy, col))
        }
        for f in pts.sorted(by: { $0.1 < $1.1 }) {
            drawFlower(ctx, base: CGPoint(x: base.x + f.0, y: base.y + f.1), s: s, color: f.2)
        }
    }

    private func drawStone(_ ctx: GraphicsContext, base: CGPoint, s: CGFloat) {
        ctx.fill(Path(ellipseIn: CGRect(x: base.x - s, y: base.y - s * 0.7, width: s * 2, height: s * 1.1)), with: .color(GardenPalette.mountainRock.color))
        ctx.fill(Path(ellipseIn: CGRect(x: base.x - s * 0.6, y: base.y - s * 0.7, width: s * 1.1, height: s * 0.6)), with: .color(GardenPalette.wallStone.color.opacity(0.6)))
    }

    private func drawFence(_ ctx: GraphicsContext, _ size: CGSize, _ camera: GardenCamera, unit: CGFloat) {
        let postW = unit * 0.7, postH = unit * 2.2
        for wx in stride(from: CGFloat(-170), through: 170, by: 40) {
            let p = camera.project(CGPoint(x: wx, y: 56), parallax: 1.0, size: size)
            rect(ctx, p.x - postW / 2, p.y - postH, postW, postH, GardenPalette.woodFence)
            let next = camera.project(CGPoint(x: wx + 40, y: 56), parallax: 1.0, size: size)
            rect(ctx, p.x, p.y - postH * 0.7, max(1, next.x - p.x), postH * 0.28, GardenPalette.woodFence.lerp(to: GardenPalette.soilDark, 0.1))
        }
    }

    private func drawSign(_ ctx: GraphicsContext, base: CGPoint, s: CGFloat) {
        rect(ctx, base.x - s * 0.25, base.y - s * 2.2, s * 0.5, s * 2.2, GardenPalette.soilDark)
        rect(ctx, base.x - s * 1.3, base.y - s * 2.6, s * 2.6, s * 1.4, GardenPalette.woodFence)
        rect(ctx, base.x - s * 1.1, base.y - s * 2.4, s * 2.2, s * 1.0, GardenPalette.woodFence.lerp(to: GardenPalette.petalWhite, 0.2))
    }

    private func drawButterfly(_ ctx: GraphicsContext, at p: CGPoint, s: CGFloat, flap: Double, color: RGB, alpha: Double) {
        let w = s * (0.5 + 0.5 * abs(flap))
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - w, y: p.y - s * 0.6, width: w, height: s * 1.2)), with: .color(color.color.opacity(alpha)))
        ctx.fill(Path(ellipseIn: CGRect(x: p.x, y: p.y - s * 0.6, width: w, height: s * 1.2)), with: .color(color.color.opacity(alpha)))
        rect(ctx, p.x - s * 0.08, p.y - s * 0.6, s * 0.16, s * 1.2, GardenPalette.soilDark, alpha)
    }
}
