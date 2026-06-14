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

/// The garden as a navigable, full-bleed, **crisp pixel-art** world drawn through a `GardenCamera`.
///
/// Everything snaps to a single pixel grid (`px`) for a cohesive "high-fidelity pixel art" look:
/// blocky snow-capped mountains with slope shading, textured grass, golden-hour lighting + sun bloom
/// + vignette, and grounding shadows. Content is generated deterministically per world chunk and
/// culled to the visible rect. Growth (`worldStage`) sets richness; vitality (`GardenStyle`) tints.
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

    // MARK: - Render

    private func draw(into ctx: GraphicsContext, size: CGSize, camera: GardenCamera, style: GardenStyle, time: Double) {
        let px = max(2, (size.width / 150).rounded())          // the world's pixel grid
        let unit = max(2, size.height / 160) * camera.zoom
        let stage = snapshot.worldStage.rawValue

        drawSky(ctx, size, style)
        drawSunBloom(ctx, size)
        drawClouds(ctx, size, camera, px: px, time: time)
        drawMountains(ctx, size, camera, px: px)
        drawHills(ctx, size, camera, px: px)
        drawGround(ctx, size, camera)
        drawTrees(ctx, size, camera, stage: stage, unit: unit, px: px, style: style, time: time)
        drawForeground(ctx, size, camera, stage: stage, unit: unit, px: px, style: style, time: time)
        drawCreatures(ctx, size, camera, stage: stage, unit: unit, style: style, time: time)
        drawAtmosphere(ctx, size)
    }

    private func snap(_ v: CGFloat, _ px: CGFloat) -> CGFloat { (v / px).rounded() * px }

    // Sky: warm golden-hour gradient (cool top → warm near horizon).
    private func drawSky(_ ctx: GraphicsContext, _ size: CGSize, _ style: GardenStyle) {
        let warmHorizon = style.skyBottom.lerp(to: GardenPalette.petalYellow, 0.18)
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(stops: [
                    .init(color: style.skyTop.color, location: 0),
                    .init(color: style.skyTop.lerp(to: style.skyBottom, 0.55).color, location: 0.42),
                    .init(color: warmHorizon.color, location: 0.72)]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height * 0.62)))
    }

    // Soft sun + bloom upper-left, with a faint horizon glow.
    private func drawSunBloom(_ ctx: GraphicsContext, _ size: CGSize) {
        let c = CGPoint(x: size.width * 0.27, y: size.height * 0.17)
        let r = size.height * 0.6
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                 with: .radialGradient(Gradient(colors: [GardenPalette.petalWhite.color.opacity(0.9),
                                                         GardenPalette.petalYellow.color.opacity(0.28), .clear]),
                                       center: c, startRadius: 0, endRadius: r))
        let core = size.height * 0.05
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - core, y: c.y - core, width: core * 2, height: core * 2)),
                 with: .color(GardenPalette.petalWhite.color.opacity(0.85)))
    }

    // Blocky pixel clouds.
    private func drawClouds(_ ctx: GraphicsContext, _ size: CGSize, _ camera: GardenCamera, px: CGFloat, time: Double) {
        let parallax: CGFloat = 0.15, cell: CGFloat = 700
        let (minX, maxX) = camera.visibleWorldX(parallax: parallax, size: size, margin: cell)
        for c in Int(floor(minX / cell))...Int(ceil(maxX / cell)) {
            var rng = SeededGenerator(seed: gardenCellSeed(worldSeed, c, 0xC10D))
            for _ in 0..<Int(rng.double(in: 1, 3)) {
                let wx = CGFloat(c) * cell + CGFloat(rng.double(in: 0, Double(cell)))
                let wy = CGFloat(rng.double(in: -360, -190)) + CGFloat(sin(time * 0.05 + rng.double(in: 0, 6)) * 6)
                let p = camera.project(CGPoint(x: wx, y: wy), parallax: parallax, size: size)
                let s = max(px, size.height * 0.018 * camera.zoom)
                
                for (dx, dy, w_mult) in [(-3.0, 1.0, 4.0), (0.0, 0.0, 5.0), (3.0, 1.0, 4.0), (-1.0, -1.0, 3.0)] as [(CGFloat,CGFloat,CGFloat)] {
                    let cx_puff = snap(p.x + dx * s, px)
                    let cy_puff = snap(p.y + dy * s, px)
                    let w_puff = w_mult * s
                    let h_puff = 2 * s
                    let d_puff = s * 0.5
                    
                    let baseColor = GardenPalette.cloud
                    let shadowColor = baseColor.lerp(to: GardenPalette.skyTop, 0.22)
                    let topColor = RGB(r: 255, g: 255, b: 255)
                    
                    // Draw top face
                    ctx.fill(Path(CGRect(x: cx_puff - w_puff/2, y: cy_puff - d_puff, width: w_puff, height: d_puff)),
                             with: .color(topColor.color.opacity(0.9)))
                    // Draw left face
                    ctx.fill(Path(CGRect(x: cx_puff - w_puff/2, y: cy_puff, width: w_puff/2, height: h_puff)),
                             with: .color(baseColor.color.opacity(0.9)))
                    // Draw right face
                    ctx.fill(Path(CGRect(x: cx_puff, y: cy_puff, width: w_puff/2, height: h_puff)),
                             with: .color(shadowColor.color.opacity(0.9)))
                }
            }
        }
    }

    private func drawMountains(_ ctx: GraphicsContext, _ size: CGSize, _ camera: GardenCamera, px: CGFloat) {
        drawRidge(ctx, size, camera, parallax: 0.20, peak: size.height * 0.40, phase: 1.1, haze: 0.62, px: px * 2)
        drawRidge(ctx, size, camera, parallax: 0.33, peak: size.height * 0.55, phase: 3.7, haze: 0.34, px: px * 1.5)
        drawRidge(ctx, size, camera, parallax: 0.47, peak: size.height * 0.68, phase: 6.2, haze: 0.12, px: px)
    }

    private func voxelHeight(worldX: CGFloat, worldZ: CGFloat, peak: CGFloat, phase: Double, maxZ: Int, voxelSizeWorld: CGFloat) -> CGFloat {
        let x1 = Double(worldX) * 0.005 + phase
        let z1 = Double(worldZ) * 0.008 + phase * 0.7
        let x2 = Double(worldX) * 0.015 - phase * 0.3
        let z2 = Double(worldZ) * 0.022 + phase * 1.2
        
        let n1 = sin(x1) * cos(z1)
        let n2 = sin(x2) * sin(z2)
        
        let base = abs(n1 * 0.7 + n2 * 0.3)
        let ridged = 1.0 - pow(1.0 - base, 3.0)
        
        var h = peak * CGFloat(0.15 + 0.85 * ridged)
        
        let maxZWorld = CGFloat(maxZ) * voxelSizeWorld
        let zRatio = min(1.0, max(0.0, worldZ / maxZWorld))
        let zFade = sin(zRatio * .pi)
        h *= CGFloat(zFade)
        
        return h
    }

    private func drawRidge(_ ctx: GraphicsContext, _ size: CGSize, _ camera: GardenCamera,
                           parallax: CGFloat, peak: CGFloat, phase: Double, haze: Double, px: CGFloat) {
        let rock = GardenPalette.mountainRock.lerp(to: GardenPalette.skyTop, haze)
        let rockShadow = rock.lerp(to: GardenPalette.soilDark, 0.22)
        let snow = GardenPalette.mountainSnow.lerp(to: GardenPalette.skyTop, haze * 0.6)
        let snowShadow = snow.lerp(to: rock, 0.30)
        let grass = GardenPalette.hillBack.lerp(to: GardenPalette.skyTop, haze)
        let grassShadow = grass.lerp(to: GardenPalette.soilDark, 0.25)
        
        let maxZ = 12
        let depthFactor: CGFloat = 0.45
        let voxelSizeWorld: CGFloat = 6.0
        
        let w = max(px, snap(voxelSizeWorld * camera.zoom, px))
        let d = max(px, snap(voxelSizeWorld * depthFactor * camera.zoom, px))
        
        let (minX, maxX) = camera.visibleWorldX(parallax: parallax, size: size, margin: voxelSizeWorld * 2)
        let startX = floor(minX / voxelSizeWorld) * voxelSizeWorld
        let endX = ceil(maxX / voxelSizeWorld) * voxelSizeWorld
        
        for z in 0..<maxZ {
            let worldZ = CGFloat(z) * voxelSizeWorld
            for worldX in stride(from: startX, through: endX, by: voxelSizeWorld) {
                let h = voxelHeight(worldX: worldX, worldZ: worldZ, peak: peak, phase: phase, maxZ: maxZ, voxelSizeWorld: voxelSizeWorld)
                guard h > 1.0 else { continue }
                
                let pCurrent = camera.project(CGPoint(x: worldX, y: -h + worldZ * depthFactor), parallax: parallax, size: size)
                let sx = snap(pCurrent.x, px)
                let sy = snap(pCurrent.y, px)
                
                let hFront: CGFloat
                if z == maxZ - 1 {
                    hFront = 0
                } else {
                    hFront = voxelHeight(worldX: worldX, worldZ: worldZ + voxelSizeWorld, peak: peak, phase: phase, maxZ: maxZ, voxelSizeWorld: voxelSizeWorld)
                }
                
                let pFront = camera.project(CGPoint(x: worldX, y: -hFront + (worldZ + voxelSizeWorld) * depthFactor), parallax: parallax, size: size)
                let heightScreen = snap(pFront.y, px) - sy
                
                var rng = SeededGenerator(seed: gardenCellSeed(worldSeed, Int(worldX / voxelSizeWorld), UInt64(z)))
                let snowThreshold = peak * CGFloat(rng.double(in: 0.52, 0.62))
                let grassThreshold = peak * CGFloat(rng.double(in: 0.26, 0.36))
                
                let isSnow = h > snowThreshold
                let isGrass = h < grassThreshold
                
                let baseColor: RGB
                let shadowColor: RGB
                if isSnow {
                    baseColor = snow
                    shadowColor = snowShadow
                } else if isGrass {
                    baseColor = grass
                    shadowColor = grassShadow
                } else {
                    baseColor = rock
                    shadowColor = rockShadow
                }
                
                // 3D Ray-cast Shadow Solver
                var inShadow = false
                for step in 1...3 {
                    let checkX = worldX - CGFloat(step) * voxelSizeWorld
                    let checkZ = worldZ - CGFloat(step) * voxelSizeWorld * 0.5
                    let checkH = voxelHeight(worldX: checkX, worldZ: checkZ, peak: peak, phase: phase, maxZ: maxZ, voxelSizeWorld: voxelSizeWorld)
                    if checkH > h + CGFloat(step) * 3.5 {
                        inShadow = true
                        break
                    }
                }
                
                // Ambient Occlusion Solver
                let hL = voxelHeight(worldX: worldX - voxelSizeWorld, worldZ: worldZ, peak: peak, phase: phase, maxZ: maxZ, voxelSizeWorld: voxelSizeWorld)
                let hR = voxelHeight(worldX: worldX + voxelSizeWorld, worldZ: worldZ, peak: peak, phase: phase, maxZ: maxZ, voxelSizeWorld: voxelSizeWorld)
                let hB = voxelHeight(worldX: worldX, worldZ: worldZ - voxelSizeWorld, peak: peak, phase: phase, maxZ: maxZ, voxelSizeWorld: voxelSizeWorld)
                let hF = voxelHeight(worldX: worldX, worldZ: worldZ + voxelSizeWorld, peak: peak, phase: phase, maxZ: maxZ, voxelSizeWorld: voxelSizeWorld)
                
                var ao: Double = 1.0
                if hL > h + 3.0 { ao -= 0.08 }
                if hR > h + 3.0 { ao -= 0.08 }
                if hB > h + 3.0 { ao -= 0.08 }
                if hF > h + 3.0 { ao -= 0.08 }
                
                let hNext = voxelHeight(worldX: worldX + voxelSizeWorld, worldZ: worldZ, peak: peak, phase: phase, maxZ: maxZ, voxelSizeWorld: voxelSizeWorld)
                let lit = hNext <= h
                
                let litTop = baseColor.lerp(to: GardenPalette.petalYellow, 0.08)
                let shadowTop = shadowColor
                
                let topColor = (inShadow ? shadowTop : litTop).lerp(to: GardenPalette.soilDark, (1.0 - ao) * 0.6)
                let leftColor = (inShadow ? shadowColor : (lit ? baseColor : shadowColor)).lerp(to: GardenPalette.soilDark, (1.0 - ao) * 0.6)
                let rightColor = shadowColor.lerp(to: GardenPalette.soilDark, (1.0 - ao) * 0.6)
                
                // Draw top face
                ctx.fill(Path(CGRect(x: sx - w/2, y: sy - d, width: w, height: d)), with: .color(topColor.color))
                
                // Draw side faces
                if heightScreen > 0 {
                    ctx.fill(Path(CGRect(x: sx - w/2, y: sy, width: w/2, height: heightScreen)), with: .color(leftColor.color))
                    ctx.fill(Path(CGRect(x: sx, y: sy, width: w/2, height: heightScreen)), with: .color(rightColor.color))
                }
            }
        }
    }

    // MARK: – Ground elevation shared by ground renderer + prop placement

    /// Rolling meadow elevation for a world (x, z) position. `worldZ` = 0 is horizon; grows toward camera.
    private func groundElevation(worldX: CGFloat, worldZ: CGFloat) -> CGFloat {
        let x1 = Double(worldX) * 0.0055 + 1.3
        let z1 = Double(worldZ) * 0.0060 + 0.7
        let x2 = Double(worldX) * 0.0140 + 2.9
        let z2 = Double(worldZ) * 0.0120 + 1.8
        let n1 = sin(x1) * cos(z1)
        let n2 = sin(x2) * sin(z2)
        return 8 + CGFloat(n1 * 22 + n2 * 12)
    }

    private func hillHeight(worldX: CGFloat, worldZ: CGFloat, phase: Double, maxZ: Int, voxelSizeWorld: CGFloat) -> CGFloat {
        let x1 = Double(worldX) * 0.007 + phase
        let z1 = Double(worldZ) * 0.012
        let x2 = Double(worldX) * 0.020 + phase * 1.5
        let z2 = Double(worldZ) * 0.025 + 0.5
        let n1 = sin(x1) * cos(z1)
        let n2 = sin(x2) * cos(z2)
        var h = 18 + CGFloat(n1 * 22 + n2 * 12)

        let maxZWorld = CGFloat(maxZ) * voxelSizeWorld
        let zRatio = min(1.0, max(0.0, worldZ / maxZWorld))
        let zFade = sin(zRatio * .pi)
        h *= CGFloat(zFade)

        return h
    }

    private func drawHills(_ ctx: GraphicsContext, _ size: CGSize, _ camera: GardenCamera, px: CGFloat) {
        let parallax: CGFloat = 0.55
        let maxZ = 8
        let depthFactor: CGFloat = 0.45
        let voxelSizeWorld: CGFloat = 8.0

        let w = max(px, snap(voxelSizeWorld * camera.zoom, px))
        let d = max(px, snap(voxelSizeWorld * depthFactor * camera.zoom, px))

        let (minX, maxX) = camera.visibleWorldX(parallax: parallax, size: size, margin: voxelSizeWorld * 2)
        let startX = floor(minX / voxelSizeWorld) * voxelSizeWorld
        let endX   = ceil(maxX / voxelSizeWorld) * voxelSizeWorld

        let hillBase   = GardenPalette.hillBack
        let hillShadow = GardenPalette.hillFront

        for z in 0..<maxZ {
            let worldZ = CGFloat(z) * voxelSizeWorld
            for worldX in stride(from: startX, through: endX, by: voxelSizeWorld) {
                let h = hillHeight(worldX: worldX, worldZ: worldZ, phase: 2.1, maxZ: maxZ, voxelSizeWorld: voxelSizeWorld)
                guard h > 0.5 else { continue }

                let pC = camera.project(CGPoint(x: worldX, y: -h + worldZ * depthFactor), parallax: parallax, size: size)
                let sx = snap(pC.x, px), sy = snap(pC.y, px)

                let hFront: CGFloat = (z == maxZ - 1) ? 0 :
                    hillHeight(worldX: worldX, worldZ: worldZ + voxelSizeWorld, phase: 2.1, maxZ: maxZ, voxelSizeWorld: voxelSizeWorld)
                let pF = camera.project(CGPoint(x: worldX, y: -hFront + (worldZ + voxelSizeWorld) * depthFactor), parallax: parallax, size: size)
                let heightScreen = snap(pF.y, px) - sy

                // Directional shadow (sun from top-left)
                var inShadow = false
                for step in 1...2 {
                    let chX = worldX - CGFloat(step) * voxelSizeWorld
                    let chZ = worldZ - CGFloat(step) * voxelSizeWorld * 0.5
                    let chH = hillHeight(worldX: chX, worldZ: chZ, phase: 2.1, maxZ: maxZ, voxelSizeWorld: voxelSizeWorld)
                    if chH > h + CGFloat(step) * 4 { inShadow = true; break }
                }

                let hNext = hillHeight(worldX: worldX + voxelSizeWorld, worldZ: worldZ, phase: 2.1, maxZ: maxZ, voxelSizeWorld: voxelSizeWorld)
                let lit = hNext <= h

                let top   = (inShadow ? hillShadow : hillBase.lerp(to: GardenPalette.petalYellow, 0.06))
                let left  = inShadow ? hillShadow : (lit ? hillBase : hillShadow)
                let right = hillShadow

                ctx.fill(Path(CGRect(x: sx - w/2, y: sy - d, width: w, height: d)), with: .color(top.color))
                if heightScreen > 0 {
                    ctx.fill(Path(CGRect(x: sx - w/2, y: sy, width: w/2, height: heightScreen)), with: .color(left.color))
                    ctx.fill(Path(CGRect(x: sx,       y: sy, width: w/2, height: heightScreen)), with: .color(right.color))
                }
            }
        }
    }

    private func drawGround(_ ctx: GraphicsContext, _ size: CGSize, _ camera: GardenCamera) {
        let horizon = camera.horizonScreenY(size: size)
        guard size.height > horizon else { return }

        let px     = max(2, (size.width / 160).rounded())
        let vox    = max(px, snap(7.0 * camera.zoom, px))
        let voxD   = max(px, snap(7.0 * 0.45 * camera.zoom, px))
        let voxZ   = 24                         // depth layers from horizon to camera
        let vSizeW: CGFloat = 7.0               // world units per voxel

        // Shared palette
        let grassTop    = GardenPalette.meadow
        let grassLeft   = GardenPalette.hillFront
        let grassRight  = grassLeft.lerp(to: GardenPalette.soilDark, 0.28)
        let dirtLeft    = GardenPalette.soilLight
        let dirtRight   = GardenPalette.soilDark

        // Flower cluster noise thresholds
        // Left half → warm red/coral cluster; right half → purple/lavender cluster
        let flowerRedColor    = GardenPalette.petalCoral
        let flowerPurpleColor = GardenPalette.petalPurple
        let flowerPinkColor   = GardenPalette.petalPink

        let (minX, maxX) = camera.visibleWorldX(parallax: 1.0, size: size, margin: vSizeW * 4)
        let startX = floor(minX / vSizeW) * vSizeW
        let endX   = ceil(maxX  / vSizeW) * vSizeW

        for z in 0..<voxZ {
            let worldZ  = CGFloat(z) * vSizeW
            let wZNext  = worldZ + vSizeW

            for worldX in stride(from: startX, through: endX, by: vSizeW) {
                let elev     = groundElevation(worldX: worldX, worldZ: worldZ)
                let elevNext = groundElevation(worldX: worldX, worldZ: wZNext)

                let pTop  = camera.project(CGPoint(x: worldX, y: elev + worldZ * 0.45),  parallax: 1.0, size: size)
                let pFront = camera.project(CGPoint(x: worldX, y: elevNext + wZNext * 0.45), parallax: 1.0, size: size)

                let sx    = snap(pTop.x,   px)
                let sy    = snap(pTop.y,   px)
                let sFY   = snap(pFront.y, px)
                let sideH = max(0, sFY - sy)

                guard sy < size.height + vox && sFY > horizon - vox else { continue }

                // Directional shadow
                var inShadow = false
                for step in 1...3 {
                    let chX = worldX - CGFloat(step) * vSizeW
                    let chZ = worldZ - CGFloat(step) * vSizeW * 0.5
                    let chE = groundElevation(worldX: chX, worldZ: chZ)
                    if chE > elev + CGFloat(step) * 3.5 { inShadow = true; break }
                }

                let hNext = groundElevation(worldX: worldX + vSizeW, worldZ: worldZ)
                let lit   = hNext <= elev

                let tColor = inShadow ? grassLeft : grassTop.lerp(to: GardenPalette.petalYellow, 0.10)
                let lColor = inShadow ? grassRight : (lit ? grassLeft : grassRight)
                let rColor = grassRight

                // Grass top face
                ctx.fill(Path(CGRect(x: sx - vox/2, y: sy - voxD, width: vox, height: voxD)), with: .color(tColor.color))
                // Dirt side faces
                if sideH > 0 {
                    ctx.fill(Path(CGRect(x: sx - vox/2, y: sy, width: vox/2, height: sideH)), with: .color((inShadow ? dirtRight : dirtLeft).color))
                    ctx.fill(Path(CGRect(x: sx,         y: sy, width: vox/2, height: sideH)), with: .color(dirtRight.color))
                }

                // ── Flower clusters ─────────────────────────────────────────
                // Use two noise values at different frequencies for cluster density
                let fx1  = Double(worldX) * 0.022 + Double(worldZ) * 0.018 + 4.1
                let fz1  = Double(worldZ) * 0.030 + Double(worldX) * 0.010 + 2.7
                let fx2  = Double(worldX) * 0.055 + Double(worldZ) * 0.040 + 7.3
                let fz2  = Double(worldZ) * 0.062 + Double(worldX) * 0.025 + 1.2

                let clusterN  = (sin(fx1) * cos(fz1) + 1.0) / 2.0    // 0…1 smooth cluster field
                let detailN   = (sin(fx2) * cos(fz2) + 1.0) / 2.0    // 0…1 detail scatter

                // Determine cluster zone
                let xNorm = Double(worldX)
                let redZone    = sin(xNorm * 0.009 + 0.5) > 0.15       // warm cluster side
                let purpleZone = sin(xNorm * 0.009 + 0.5) < -0.15      // cool cluster side

                let inFlowerField = clusterN > 0.52 && detailN > 0.35

                if inFlowerField && !inShadow {
                    let flowerColor: RGB
                    if redZone         { flowerColor = flowerRedColor }
                    else if purpleZone { flowerColor = flowerPurpleColor }
                    else               { flowerColor = flowerPinkColor }

                    let flowerShadow = flowerColor.lerp(to: GardenPalette.soilDark, 0.28)

                    let fw = max(px, snap(vox * 0.55, px))
                    let fh = max(px, snap(vox * 0.70, px))
                    let fd = max(px, snap(fw * 0.45, px))

                    // Flower top
                    ctx.fill(Path(CGRect(x: sx - fw/2, y: sy - voxD - fh - fd, width: fw, height: fd)),
                             with: .color(flowerColor.lerp(to: GardenPalette.petalWhite, 0.15).color))
                    // Flower left
                    ctx.fill(Path(CGRect(x: sx - fw/2, y: sy - voxD - fh, width: fw/2, height: fh)),
                             with: .color(flowerColor.color))
                    // Flower right (shadow)
                    ctx.fill(Path(CGRect(x: sx,         y: sy - voxD - fh, width: fw/2, height: fh)),
                             with: .color(flowerShadow.color))
                }
            }
        }

        // Warm sun-from-left overlay
        let h = max(0, size.height - horizon)
        ctx.fill(Path(CGRect(x: 0, y: horizon, width: size.width, height: h)),
                 with: .linearGradient(Gradient(colors: [GardenPalette.petalYellow.color.opacity(0.16), .clear]),
                                       startPoint: CGPoint(x: 0, y: horizon),
                                       endPoint:   CGPoint(x: size.width * 0.85, y: horizon)))
    }

    private func drawTrees(_ ctx: GraphicsContext, _ size: CGSize, _ camera: GardenCamera,
                           stage: Int, unit: CGFloat, px: CGFloat, style: GardenStyle, time: Double) {
        guard stage >= 2 else { return }
        let parallax: CGFloat = 0.72, cell: CGFloat = 220
        let vSizeW: CGFloat = 7.0
        let perCell = [0, 0, 1, 1, 2, 2, 3][min(stage, 6)]
        let (minX, maxX) = camera.visibleWorldX(parallax: parallax, size: size, margin: cell)
        for c in Int(floor(minX / cell))...Int(ceil(maxX / cell)) {
            var rng = SeededGenerator(seed: gardenCellSeed(worldSeed, c, 0x77EE))
            for _ in 0..<perCell {
                let wx = CGFloat(c) * cell + CGFloat(rng.double(in: 0, Double(cell)))
                // Snap to the nearest ground voxel and query elevation
                let wz = CGFloat(rng.double(in: 2, 8)) * vSizeW
                let elev = groundElevation(worldX: wx, worldZ: wz)
                let wy = elev + wz * 0.45
                let p = camera.project(CGPoint(x: wx, y: wy), parallax: parallax, size: size)
                if p.x < -60 || p.x > size.width + 60 { continue }
                let sway = swayOffset(time: time, phase: rng.double(in: 0, 6), style: style) * unit * 0.5
                drawTree(ctx, base: p, unit: unit * 2.0, sway: sway, px: px)
            }
        }
    }

    private func drawForeground(_ ctx: GraphicsContext, _ size: CGSize, _ camera: GardenCamera,
                                stage: Int, unit: CGFloat, px: CGFloat, style: GardenStyle, time: Double) {
        let parallax: CGFloat = 1.0, cell: CGFloat = 170
        let vSizeW: CGFloat = 7.0
        let density = [5, 12, 20, 28, 36, 44, 52][min(stage, 6)]
        let varieties = max(1, min(GardenPalette.flowerVarieties.count, stage + 1))
        let (minX, maxX) = camera.visibleWorldX(parallax: parallax, size: size, margin: cell)

        enum Kind { case flower, grass, rock }
        struct Item { let p: CGPoint; let depth: CGFloat; let s: CGFloat; let color: Int; let phase: Double; let kind: Kind }
        var items: [Item] = []
        for c in Int(floor(minX / cell))...Int(ceil(maxX / cell)) {
            var rng = SeededGenerator(seed: gardenCellSeed(worldSeed, c, 0xF10E))
            for i in 0..<density {
                let wx = CGFloat(c) * cell + CGFloat(rng.double(in: 0, Double(cell)))
                let depth = CGFloat(rng.double(in: 0, 1))
                // Use depth to pick a z-layer and query the rolling 3D terrain height
                let wz = 1 + depth * CGFloat(22) * vSizeW
                let elev = groundElevation(worldX: wx, worldZ: wz)
                let wy = elev + wz * 0.45
                let p0 = camera.project(CGPoint(x: wx, y: wy), parallax: parallax, size: size)
                let p = CGPoint(x: snap(p0.x, px), y: snap(p0.y, px))
                if p.x < -40 || p.x > size.width + 40 || p.y < -40 || p.y > size.height + 40 { continue }
                let kind: Kind = (i % 13 == 0) ? .rock : (i % 5 == 0 ? .grass : .flower)
                items.append(Item(p: p, depth: depth, s: max(px, unit * (0.6 + depth * 1.5)),
                                  color: Int(rng.next() % UInt64(varieties)), phase: rng.double(in: 0, 6.28), kind: kind))
            }
        }
        for it in items.sorted(by: { $0.depth < $1.depth }) {
            let sway = swayOffset(time: time, phase: it.phase, style: style) * it.s * 0.5 * (0.4 + it.depth)
            switch it.kind {
            case .rock:   drawRock(ctx, base: it.p, s: it.s, px: px)
            case .grass:  drawGrass(ctx, base: it.p, s: it.s, sway: sway, px: px)
            case .flower:
                let lean = CGFloat(style.droopDegrees) * 0.10 * it.s
                drawFlower(ctx, base: it.p, s: it.s, petal: GardenPalette.flowerVarieties[it.color], sway: sway + lean, px: px)
            }
        }
    }

    private func drawCreatures(_ ctx: GraphicsContext, _ size: CGSize, _ camera: GardenCamera,
                               stage: Int, unit: CGFloat, style: GardenStyle, time: Double) {
        if stage >= 2 && style.ambientOpacity > 0.4 {
            let parallax: CGFloat = 1.0, cell: CGFloat = 500
            let (minX, maxX) = camera.visibleWorldX(parallax: parallax, size: size, margin: cell)
            for c in Int(floor(minX / cell))...Int(ceil(maxX / cell)) {
                var rng = SeededGenerator(seed: gardenCellSeed(worldSeed, c, 0xB077))
                for _ in 0..<Int(rng.double(in: 0, 2)) {
                    let baseX = CGFloat(c) * cell + CGFloat(rng.double(in: 0, Double(cell)))
                    let ph = rng.double(in: 0, 6.28)
                    let wx = baseX + CGFloat(sin(time * 0.4 + ph)) * 40
                    let wy = 30 + CGFloat(rng.double(in: 0, 140)) + CGFloat(cos(time * 0.6 + ph)) * 18
                    let p = camera.project(CGPoint(x: wx, y: wy), parallax: parallax, size: size)
                    if p.x < -20 || p.x > size.width + 20 { continue }
                    drawButterfly(ctx, at: p, s: unit * 0.8, flap: sin(time * 6 + ph),
                                  color: GardenPalette.flowerVarieties[Int(rng.next() % 5)])
                }
            }
        }
        drawParticles(ctx, size, camera, style: style, time: time)
    }

    // Soft vignette for depth/focus.
    private func drawAtmosphere(_ ctx: GraphicsContext, _ size: CGSize) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let r = max(size.width, size.height) * 0.75
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .radialGradient(Gradient(stops: [.init(color: .clear, location: 0.6),
                                                         .init(color: .black.opacity(0.22), location: 1)]),
                                       center: c, startRadius: 0, endRadius: r))
    }

    private func swayOffset(time: Double, phase: Double, style: GardenStyle) -> CGFloat {
        guard time != 0, style.swayDegrees > 0 else { return 0 }
        return CGFloat(sin(time * style.swaySpeed * 2 * .pi + phase)) * CGFloat(style.swayDegrees)
    }

    // MARK: Sprite primitives (screen-space, pixel-snapped)

    private func cell(_ ctx: GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ rgb: RGB, _ alpha: Double = 1) {
        ctx.fill(Path(CGRect(x: x, y: y, width: w, height: h)), with: .color(rgb.color.opacity(alpha)))
    }

    private func drawFlower(_ ctx: GraphicsContext, base: CGPoint, s: CGFloat, petal: RGB, sway: CGFloat, px: CGFloat) {
        let shadowW = snap(s * 1.5, px)
        let shadowH = snap(s * 0.4, px)
        ctx.fill(Path(CGRect(x: snap(base.x - shadowW/2, px), y: snap(base.y - shadowH/2, px), width: shadowW, height: shadowH)),
                 with: .color(.black.opacity(0.12)))
                 
        let headX = base.x + sway
        let headY = base.y - 3.2 * s
        let stem = GardenPalette.stemLight
        let stemDark = GardenPalette.stemDark
        
        let stemW = max(px, snap(s * 0.3, px))
        for i in 0...3 {
            let t = CGFloat(i) / 3
            let sx = snap(base.x + (headX - base.x) * t, px)
            let sy = snap(base.y + (headY - base.y) * t, px)
            ctx.fill(Path(CGRect(x: sx - stemW/2, y: sy, width: stemW, height: s)), with: .color((i % 2 == 0 ? stem : stemDark).color))
        }
        
        let petalW = max(px, snap(s * 0.6, px))
        let petalH = max(px, snap(s * 0.6, px))
        let petalD = petalW * 0.5
        
        let centerColor = GardenPalette.flowerCenter
        let centerShadow = centerColor.lerp(to: GardenPalette.soilDark, 0.25)
        let petalShadow = petal.lerp(to: GardenPalette.soilDark, 0.22)
        
        let parts = [
            (0.0, -0.8, -0.5, petal),
            (-0.8, 0.0, -0.5, petal),
            (0.8, 0.0, -0.5, petal),
            (0.0, 0.0, 0.0, centerColor),
            (-0.6, 0.6, 0.5, petal),
            (0.6, 0.6, 0.5, petal),
            (0.0, 0.8, 0.5, petal)
        ]
        
        for (dx, dy, dz, col) in parts {
            let px_coord = snap(headX + dx * s * 0.8, px)
            let py_coord = snap(headY + dy * s * 0.8 + dz * s * 0.3, px)
            
            let baseColor = col
            let shadowColor = col == centerColor ? centerShadow : petalShadow
            
            let topColor = baseColor.lerp(to: GardenPalette.petalWhite, 0.15)
            let leftColor = baseColor
            let rightColor = shadowColor
            
            // Top face
            ctx.fill(Path(CGRect(x: px_coord - petalW/2, y: py_coord - petalD, width: petalW, height: petalD)), with: .color(topColor.color))
            // Left face
            ctx.fill(Path(CGRect(x: px_coord - petalW/2, y: py_coord, width: petalW/2, height: petalH)), with: .color(leftColor.color))
            // Right face
            ctx.fill(Path(CGRect(x: px_coord, y: py_coord, width: petalW/2, height: petalH)), with: .color(rightColor.color))
        }
    }

    private func drawGrass(_ ctx: GraphicsContext, base: CGPoint, s: CGFloat, sway: CGFloat, px: CGFloat) {
        let dark = GardenPalette.leafDark
        let mid = GardenPalette.leafMid
        let light = GardenPalette.leafLight
        
        let w = max(px, snap(s * 0.35, px))
        let h = max(px, snap(s * 1.5, px))
        let d = w * 0.5
        
        let blades = [
            (-s * 0.8, -s * 0.2, dark),
            (0.0, 0.0, mid),
            (s * 0.8, -s * 0.4, light)
        ]
        
        for (dx, dy, color) in blades {
            let bx = snap(base.x + dx + sway * 0.3, px)
            let by = snap(base.y + dy - h, px)
            
            let baseColor = color
            let shadowColor = color.lerp(to: GardenPalette.soilDark, 0.25)
            let topColor = color.lerp(to: GardenPalette.petalYellow, 0.08)
            
            // Draw top face
            ctx.fill(Path(CGRect(x: bx - w/2, y: by - d, width: w, height: d)), with: .color(topColor.color))
            // Draw left face
            ctx.fill(Path(CGRect(x: bx - w/2, y: by, width: w/2, height: h)), with: .color(baseColor.color))
            // Draw right face
            ctx.fill(Path(CGRect(x: bx, y: by, width: w/2, height: h)), with: .color(shadowColor.color))
        }
    }

    private func drawRock(_ ctx: GraphicsContext, base: CGPoint, s: CGFloat, px: CGFloat) {
        let shadowW = snap(s * 1.8, px)
        let shadowH = snap(s * 0.5, px)
        ctx.fill(Path(CGRect(x: snap(base.x - shadowW/2, px), y: snap(base.y - shadowH/2, px), width: shadowW, height: shadowH)),
                 with: .color(.black.opacity(0.12)))
                 
        let w = max(px, snap(s * 1.4, px))
        let h = max(px, snap(s * 1.0, px))
        let d = w * 0.5
        
        let sx = snap(base.x, px)
        let sy = snap(base.y - h * 0.5, px)
        
        let rock = GardenPalette.mountainRock
        let rockShadow = rock.lerp(to: GardenPalette.soilDark, 0.25)
        let snow = GardenPalette.mountainSnow
        
        let topColor = snow.lerp(to: rock, 0.15)
        let leftColor = rock
        let rightColor = rockShadow
        
        // Draw top face
        ctx.fill(Path(CGRect(x: sx - w/2, y: sy - d, width: w, height: d)), with: .color(topColor.color))
        // Draw left face
        ctx.fill(Path(CGRect(x: sx - w/2, y: sy, width: w/2, height: h)), with: .color(leftColor.color))
        // Draw right face
        ctx.fill(Path(CGRect(x: sx, y: sy, width: w/2, height: h)), with: .color(rightColor.color))
    }

    private func drawTree(_ ctx: GraphicsContext, base: CGPoint, unit: CGFloat, sway: CGFloat, px: CGFloat) {
        let shadowW = snap(unit * 2.6, px)
        let shadowH = snap(unit * 0.5, px)
        ctx.fill(Path(CGRect(x: snap(base.x - shadowW/2, px), y: snap(base.y - shadowH/2, px), width: shadowW, height: shadowH)),
                 with: .color(.black.opacity(0.15)))
        
        let trunkW = max(px, snap(unit * 0.8, px))
        let trunkH = max(px, snap(unit * 2.2, px))
        
        // Trunk Shadow (right) and Highlight (left)
        ctx.fill(Path(CGRect(x: snap(base.x - trunkW/2, px), y: snap(base.y - trunkH, px), width: trunkW, height: trunkH)),
                 with: .color(GardenPalette.soilDark.color))
        ctx.fill(Path(CGRect(x: snap(base.x - trunkW/2, px), y: snap(base.y - trunkH, px), width: trunkW/2, height: trunkH)),
                 with: .color(GardenPalette.soilLight.color))
        
        let cx = base.x + sway
        let cy = base.y - trunkH - unit * 1.0
        let voxelSize = max(px, snap(unit * 0.65, px))
        
        // Voxel canopy blocks (dx, dy, dz)
        let leafBlocks: [(CGFloat, CGFloat, CGFloat)] = [
            (-1.5, 0.5, -1.0), (0.0, 0.8, -1.0), (1.5, 0.5, -1.0),
            (-1.0, 0.0, -0.5), (1.0, 0.0, -0.5),
            (-1.2, -0.5, 0.0), (0.0, -0.2, 0.0), (1.2, -0.5, 0.0),
            (-0.5, 0.5, 0.0), (0.5, 0.5, 0.0),
            (-0.8, -1.2, 1.0), (0.0, -1.4, 1.0), (0.8, -1.2, 1.0),
            (-0.4, -0.8, 1.0), (0.4, -0.8, 1.0), (0.0, -0.6, 1.0)
        ]
        
        for (dx, dy, dz) in leafBlocks {
            let wx = cx + dx * voxelSize
            let wy = cy + dy * voxelSize
            let screenZ = dz * voxelSize * 0.45
            
            let px_coord = snap(wx, px)
            let py_coord = snap(wy + screenZ, px)
            let w = voxelSize
            let h = voxelSize
            let d = voxelSize * 0.45
            
            let baseColor = dz < 0 ? GardenPalette.leafDark : (dz > 0.5 ? GardenPalette.leafLight : GardenPalette.leafMid)
            let shadowColor = baseColor.lerp(to: GardenPalette.soilDark, 0.25)
            
            let topColor = baseColor.lerp(to: GardenPalette.petalYellow, 0.08)
            let leftColor = baseColor
            let rightColor = shadowColor
            
            // Top face
            ctx.fill(Path(CGRect(x: px_coord - w/2, y: py_coord - d, width: w, height: d)), with: .color(topColor.color))
            // Left face
            ctx.fill(Path(CGRect(x: px_coord - w/2, y: py_coord, width: w/2, height: h)), with: .color(leftColor.color))
            // Right face
            ctx.fill(Path(CGRect(x: px_coord, y: py_coord, width: w/2, height: h)), with: .color(rightColor.color))
        }
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
        let bandTop = horizon * 0.7, bandBottom = horizon + (size.height - horizon) * 0.55
        for _ in 0..<style.fireflyCount {
            let bx = rng.double(in: 0.1, 0.9) * Double(size.width)
            let by = Double(bandTop) + rng.double(in: 0, 1) * Double(bandBottom - bandTop)
            let phase = rng.double(in: 0, 2 * .pi)
            let x = bx + sin(time * 0.6 + phase) * Double(size.width) * 0.04
            let y = by + cos(time * 0.45 + phase) * Double(size.height) * 0.03
            let alpha = (0.55 + 0.45 * sin(time * 1.3 + phase)) * style.ambientOpacity
            let glowR = Double(size.height) * 0.045
            ctx.fill(Path(ellipseIn: CGRect(x: x - glowR, y: y - glowR, width: glowR * 2, height: glowR * 2)),
                     with: .radialGradient(Gradient(colors: [GardenPalette.firefly.color.opacity(0.5 * alpha), .clear]),
                                           center: CGPoint(x: x, y: y), startRadius: 0, endRadius: glowR))
            let coreR = max(1.5, Double(size.height) * 0.011)
            ctx.fill(Path(ellipseIn: CGRect(x: x - coreR, y: y - coreR, width: coreR * 2, height: coreR * 2)),
                     with: .color(GardenPalette.firefly.color.opacity(alpha)))
        }
    }
}
