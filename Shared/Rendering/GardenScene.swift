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
    var petType: PetType = .cat
    var animated: Bool = true
    var interactive: Bool = true
    /// Override the real-time lighting (used by previews/tests to render a specific hour). `nil` ⇒ live.
    var lighting: GardenLighting? = nil
    /// Current real-world weather (atmosphere only). Defaults to clear.
    var weather: GardenWeather = .clear
    /// Called when the user taps the pet awake — the app uses this for an optional soft sound/haptic.
    var onPetWake: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var camera = GardenCamera.default
    @State private var panStart: CGPoint?
    @State private var zoomStart: CGFloat?
    @State private var revivalStart: Date?
    @State private var petWakeUntil: Date?
    @State private var petVariant = 0

    private let worldSeed: UInt64 = 0xA11CE5EED
    private var frameInterval: Double { 1.0 / 15.0 }
    private var motionEnabled: Bool { animated && !reduceMotion && scenePhase != .background }
    private let revivalDuration: Double = 1.8

    // Home sits here in world space; the garden is composed around it.
    private let homeBaseY: CGFloat = 92

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: frameInterval, paused: !motionEnabled)) { timeline in
                let now = timeline.date
                let progress = revivalProgress(now: now)
                let style = effectiveStyle(at: progress)
                let time = motionEnabled ? now.timeIntervalSinceReferenceDate : 0
                let petState = currentPetState(now: now)
                let light = lighting ?? GardenLighting.at(date: now)

                Canvas(opaque: true, rendersAsynchronously: false) { context, size in
                    draw(into: context, size: size, camera: interactive ? camera : .default,
                         style: style, time: time, petState: petState, light: light, weather: weather)
                }
                .saturation(style.saturation)
                .brightness(style.brightness)
            }
            .contentShape(Rectangle())
            .gesture(explorationGesture, including: interactive ? .all : .none)
            .simultaneousGesture(petTapGesture(size: geo.size), including: interactive ? .all : .none)
        }
        .onAppear { if snapshot.isReviving { revivalStart = Date() } }
        .onChange(of: snapshot.isReviving) { _, reviving in revivalStart = reviving ? Date() : nil }
        .accessibilityElement()
        .accessibilityLabel(Text(sceneAccessibilityLabel))
    }

    private var sceneAccessibilityLabel: String {
        let garden = GardenCopy.accessibilityDescription(
            growth: snapshot.growthStage, vitality: snapshot.vitality,
            isReviving: snapshot.isReviving, lastEntry: snapshot.lastEntryDate)
        let awake = petWakeUntil.map { Date() < $0 } ?? false
        let isNight = (lighting ?? GardenLighting.at(date: Date())).isNight
        let pet: String
        if !awake && isNight {
            pet = "Your companion \(petType.displayName.lowercased()) is asleep near your \(homeStyle.displayName.lowercased())."
        } else {
            pet = Pet.accessibility(petType, state: awake ? .playing(petVariant) : .resting, home: homeStyle)
        }
        return garden + " " + pet
    }

    // MARK: Companion tap (wake / alternate animation) — never a chore, just a happy hello

    private func currentPetState(now: Date) -> PetState {
        if let w = petWakeUntil, now < w { return .playing(petVariant) }
        return .resting
    }

    private func petTapGesture(size: CGSize) -> some Gesture {
        SpatialTapGesture(coordinateSpace: .local).onEnded { value in
            let spot = Pet.restSpot(snapshot.unlocks)
            let petScreen = camera.project(spot, parallax: 1.0, size: size)
            let hit = hypot(value.location.x - petScreen.x, value.location.y - petScreen.y)
            guard hit < max(size.height * 0.10, 44) else { return }
            let now = Date()
            if let w = petWakeUntil, now < w {
                petVariant = (petVariant + 1) % 2   // second tap → the alternate animation
            } else {
                petVariant = 0
            }
            petWakeUntil = now.addingTimeInterval(3.5)
            onPetWake?()
        }
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

    private func draw(into ctx: GraphicsContext, size: CGSize, camera: GardenCamera, style: GardenStyle, time: Double, petState: PetState, light: GardenLighting, weather: GardenWeather) {
        let unit = max(2, size.height / 150) * camera.zoom
        let u = unlocks
        let wind = weather.wind
        // Depth: far mountains → mid hills → near hills → ground → foreground grass (front).
        drawSky(ctx, size, light)
        drawStars(ctx, size, light, time: time)
        drawSun(ctx, size, light)
        drawClouds(ctx, size, light, weather: weather, time: time)
        drawDistantMountains(ctx, size, camera, light: light)
        drawHills(ctx, size, camera)
        drawNearHills(ctx, size, camera)
        drawGround(ctx, size, camera)
        if weather.condition == .rain { drawWetGround(ctx, size) }
        drawPlot(ctx, size, camera)
        // ZONE 3 (left): the calm lake (entry 30), then a bridge across it (entry 50).
        if u.hasLake {
            drawLake(ctx, size, camera, unit: unit, unlocks: u, time: time)
        }
        if u.hasBridge {
            drawLakeBridge(ctx, size, camera, unit: unit)
        }
        // The path connects the home to the garden (and, once unlocked, to the lake bridge).
        drawPath(ctx, size, camera, unit: unit, hasLake: u.hasLake)
        // ZONE 2 (right): all flowers / trees / growth.
        drawGardenZone(ctx, size, camera, unit: unit, unlocks: u, light: light, wind: wind, time: time)
        // ZONE 1 (center): house + home decorations (no flowers).
        drawHomeZone(ctx, size, camera, unit: unit, unlocks: u, light: light)
        // The companion — always in the Home Area, with clear spacing.
        drawPet(ctx, size, camera, unit: unit, unlocks: u, petState: petState, time: time, isNight: light.isNight)
        // Butterflies / fireflies live over the Garden Area only (the pet is the only creature at home).
        drawCreatures(ctx, size, camera, unit: unit, unlocks: u, style: style, time: time)
        drawForegroundGrass(ctx, size, camera, unit: unit)
        // Snow settles as a soft white ground sheet; rain/snow particles fall over everything.
        if weather.condition == .snow { drawSnowGround(ctx, size) }
        // A real-time colour wash (warm at dusk, blue at night) — set last, under precipitation.
        drawLightingOverlay(ctx, size, light)
        drawPrecipitation(ctx, size, weather: weather, time: time)
        drawAtmosphere(ctx, size)
    }

    private func drawPet(_ ctx: GraphicsContext, _ size: CGSize, _ camera: GardenCamera,
                         unit: CGFloat, unlocks u: GardenUnlocks, petState: PetState, time: Double, isNight: Bool) {
        let spot = Pet.restSpot(u)
        let p = camera.project(spot, parallax: 1.0, size: size)
        let depth = max(0, min(1, spot.y / 180))
        let s = unit * 2.5 * (0.9 + depth * 0.4)   // small & cute, clearly readable
        // At night the companion curls up and sleeps — unless the user just tapped it awake.
        let resting: Bool = { if case .resting = petState { return true }; return false }()
        let sleeping = resting && isNight
        var pose = Pet.pose(petType, petState, time: time)
        if sleeping {
            pose.moveX = 0
            pose.hopY = 0
            pose.bobY = 0.10 * CGFloat(sin(time * 0.7))   // slow, settled breathing
            pose.eyesOpen = false
        }
        let frame: PetFrame = sleeping ? .sleep : Pet.frame(for: petState)
        Pet.draw(ctx, type: petType, base: p, s: s, frame: frame, pose: pose)
        if sleeping { drawSleepZ(ctx, at: CGPoint(x: p.x + s * 1.4, y: p.y - s * 2.6), s: s, time: time) }
    }

    /// Floating "z z z" rising above a sleeping companion (the universal "asleep" signal).
    private func drawSleepZ(_ ctx: GraphicsContext, at base: CGPoint, s: CGFloat, time: Double) {
        for k in 0..<3 {
            let t = (time * 0.5 + Double(k) * 0.45).truncatingRemainder(dividingBy: 1.35) / 1.35
            let rise = CGFloat(t) * s * 2.6
            let alpha = (1 - t) * 0.85
            let fontSize = s * (0.9 + CGFloat(k) * 0.35)
            let pt = CGPoint(x: base.x + CGFloat(t) * s * 0.9, y: base.y - rise)
            ctx.draw(Text("z").font(.system(size: fontSize, weight: .bold, design: .rounded))
                        .foregroundColor(GardenPalette.petalWhite.color.opacity(alpha)), at: pt)
        }
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

    private func drawSky(_ ctx: GraphicsContext, _ size: CGSize, _ light: GardenLighting) {
        let warm = light.skyBottom.lerp(to: GardenPalette.petalYellow, light.isNight ? 0.0 : 0.10)
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(stops: [
                    .init(color: light.skyTop.color, location: 0),
                    .init(color: light.skyTop.lerp(to: light.skyBottom, 0.6).color, location: 0.5),
                    .init(color: warm.color, location: 0.8)]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height * 0.55)))
    }

    /// Stars in the upper sky at night (and a touch at dusk). A gentle twinkle is the only motion —
    /// allowed because they're sky, not plants. Deterministic positions (identical app/widget).
    private func drawStars(_ ctx: GraphicsContext, _ size: CGSize, _ light: GardenLighting, time: Double) {
        guard light.starsOpacity > 0.02 else { return }
        var rng = SeededGenerator(seed: 0x57A45)
        for i in 0..<46 {
            let x = CGFloat(rng.double(in: 0, 1)) * size.width
            let y = CGFloat(rng.double(in: 0.02, 0.5)) * size.height
            let baseR = CGFloat(rng.double(in: 0.6, 1.8))
            let twinkle = 0.6 + 0.4 * sin(time * 1.2 + Double(i))
            let a = light.starsOpacity * twinkle
            ctx.fill(Path(ellipseIn: CGRect(x: x - baseR, y: y - baseR, width: baseR * 2, height: baseR * 2)),
                     with: .color(GardenPalette.petalWhite.color.opacity(a)))
        }
    }

    /// The sun by day, a pale moon by night — position/colour/size all come from the lighting.
    private func drawSun(_ ctx: GraphicsContext, _ size: CGSize, _ light: GardenLighting) {
        let c = CGPoint(x: size.width * light.sunX, y: size.height * light.sunY)
        let r = size.height * light.sunRadiusScale
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                 with: .radialGradient(Gradient(colors: [light.sunCore.color.opacity(0.85 * light.sunOpacity),
                                                         light.sunCore.color.opacity(0.20 * light.sunOpacity), .clear]),
                                       center: c, startRadius: 0, endRadius: r))
        if light.isNight {   // a crisp little moon disc inside the glow
            let mr = r * 0.42
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - mr, y: c.y - mr, width: mr * 2, height: mr * 2)),
                     with: .color(light.sunCore.color.opacity(0.9)))
        }
    }

    /// A warm-at-dusk / blue-at-night colour wash over the finished scene.
    private func drawLightingOverlay(_ ctx: GraphicsContext, _ size: CGSize, _ light: GardenLighting) {
        guard light.ambientOpacity > 0.005 else { return }
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .color(light.ambientTint.color.opacity(light.ambientOpacity)))
    }

    // MARK: Weather (atmosphere only — never changes what the world contains)

    /// Drifting clouds across the upper sky; more, darker, and lower as cover increases. Rain/snow
    /// clouds are noticeably grey so a storm reads at a glance.
    private func drawClouds(_ ctx: GraphicsContext, _ size: CGSize, _ light: GardenLighting, weather: GardenWeather, time: Double) {
        guard weather.clouds > 0.05 else { return }
        let count = Int((weather.clouds * 6).rounded()) + 1
        let stormy = weather.isPrecipitating
        let base = stormy ? GardenPalette.roofDark.lerp(to: GardenPalette.wallStone, 0.35)
                          : GardenPalette.cloud.lerp(to: GardenPalette.wallStone, weather.clouds * 0.5)
        let tint = light.isNight ? base.lerp(to: light.skyTop, 0.5) : base
        var rng = SeededGenerator(seed: 0xC10D)
        for i in 0..<count {
            let span = size.width * 1.3
            let speed = 6.0 + Double(i % 3) * 3
            let baseX = CGFloat(rng.double(in: 0, 1)) * span
            let drift = CGFloat((time * speed).truncatingRemainder(dividingBy: Double(span)))
            let cx = (baseX + drift).truncatingRemainder(dividingBy: span) - size.width * 0.15
            let cy = CGFloat(rng.double(in: 0.04, 0.30)) * size.height
            let cw = size.width * CGFloat(rng.double(in: 0.22, 0.42))
            let ch = cw * 0.42
            let op = (stormy ? 0.85 : 0.6) * min(1, weather.clouds + 0.3)
            for (ox, oy, rs) in [(-0.28, 0.10, 0.6), (0.0, -0.05, 0.85), (0.30, 0.10, 0.62), (0.05, 0.18, 0.7)] as [(CGFloat, CGFloat, CGFloat)] {
                let w = cw * rs, h = ch * rs
                ctx.fill(Path(ellipseIn: CGRect(x: cx + ox * cw - w / 2, y: cy + oy * ch - h / 2, width: w, height: h)),
                         with: .color(tint.color.opacity(op)))
            }
        }
    }

    /// A darker, faintly-reflective sheen over the lawn when it's raining.
    private func drawWetGround(_ ctx: GraphicsContext, _ size: CGSize) {
        ctx.fill(Path(CGRect(x: 0, y: size.height * 0.45, width: size.width, height: size.height * 0.55)),
                 with: .linearGradient(Gradient(colors: [GardenPalette.water.color.opacity(0.0), GardenPalette.water.color.opacity(0.22)]),
                                       startPoint: CGPoint(x: 0, y: size.height * 0.45), endPoint: CGPoint(x: 0, y: size.height)))
    }

    /// A soft white sheet of settled snow over the lower world.
    private func drawSnowGround(_ ctx: GraphicsContext, _ size: CGSize) {
        ctx.fill(Path(CGRect(x: 0, y: size.height * 0.5, width: size.width, height: size.height * 0.5)),
                 with: .linearGradient(Gradient(colors: [Color.white.opacity(0.0), Color.white.opacity(0.5)]),
                                       startPoint: CGPoint(x: 0, y: size.height * 0.5), endPoint: CGPoint(x: 0, y: size.height)))
    }

    /// Falling rain streaks or drifting snowflakes over the whole scene (deterministic, looping).
    private func drawPrecipitation(_ ctx: GraphicsContext, _ size: CGSize, weather: GardenWeather, time: Double) {
        guard weather.isPrecipitating else { return }
        var rng = SeededGenerator(seed: 0x9A1F)
        if weather.condition == .rain {
            let drops = 110
            let speed = size.height * (1.1 + weather.wind * 0.5)
            let slant = (4 + weather.wind * 16)
            for _ in 0..<drops {
                let x0 = CGFloat(rng.double(in: -0.1, 1.0)) * size.width
                let phase = rng.double(in: 0, 1)
                let yf = ((time * Double(speed) / Double(size.height)) + phase).truncatingRemainder(dividingBy: 1)
                let y = CGFloat(yf) * (size.height + 20) - 20
                let len = size.height * 0.035
                var p = Path()
                p.move(to: CGPoint(x: x0, y: y))
                p.addLine(to: CGPoint(x: x0 - CGFloat(slant) * 0.3, y: y + len))
                ctx.stroke(p, with: .color(GardenPalette.waterLight.color.opacity(0.5)), lineWidth: 1.2)
            }
        } else {   // snow
            let flakes = 90
            let fall = size.height * 0.45
            for i in 0..<flakes {
                let x0 = CGFloat(rng.double(in: 0, 1)) * size.width
                let phase = rng.double(in: 0, 1)
                let yf = ((time * Double(fall) / Double(size.height)) + phase).truncatingRemainder(dividingBy: 1)
                let y = CGFloat(yf) * (size.height + 16) - 16
                let drift = CGFloat(sin(time * 0.8 + Double(i))) * (4 + CGFloat(weather.wind) * 18)
                let r = CGFloat(rng.double(in: 1.0, 2.6))
                ctx.fill(Path(ellipseIn: CGRect(x: x0 + drift - r, y: y - r, width: r * 2, height: r * 2)),
                         with: .color(Color.white.opacity(0.85)))
            }
        }
    }

    /// A soft, distant range low on the horizon — backdrop only. Blends toward the current sky colour.
    private func drawDistantMountains(_ ctx: GraphicsContext, _ size: CGSize, _ camera: GardenCamera, light: GardenLighting) {
        let parallax: CGFloat = 0.25, step: CGFloat = 8
        let peak = size.height * 0.12
        let color = GardenPalette.mountainRock.lerp(to: light.skyTop, 0.66)
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

    /// A closer, richer hill band just behind the meadow — adds a near layer of depth.
    private func drawNearHills(_ ctx: GraphicsContext, _ size: CGSize, _ camera: GardenCamera) {
        let parallax: CGFloat = 0.82, step: CGFloat = 8
        let color = GardenPalette.hillFront.lerp(to: GardenPalette.meadow, 0.15)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height))
        var sx: CGFloat = 0
        var started = false
        while sx <= size.width {
            let worldX = (sx - size.width / 2) / camera.zoom + camera.position.x * parallax
            let n = sin(Double(worldX) * 0.0075 + 4.2) * 0.7 + sin(Double(worldX) * 0.017 + 1.0) * 0.3
            let y = camera.project(CGPoint(x: worldX, y: 14 + CGFloat(n) * 26), parallax: parallax, size: size).y
            if !started { path.addLine(to: CGPoint(x: 0, y: y)); started = true }
            path.addLine(to: CGPoint(x: sx, y: y))
            sx += step
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        ctx.fill(path, with: .color(color.color))
    }

    /// A thin fringe of out-of-focus grass blades along the very bottom edge — foreground depth.
    private func drawForegroundGrass(_ ctx: GraphicsContext, _ size: CGSize, _ camera: GardenCamera, unit: CGFloat) {
        let baseY = size.height + unit
        let blade = GardenPalette.meadow.lerp(to: GardenPalette.leafDark, 0.45)
        var x: CGFloat = -unit
        var i = 0
        while x < size.width + unit {
            let h = unit * (2.4 + CGFloat((i * 37) % 5) * 0.5)
            ctx.fill(Path(CGRect(x: x, y: baseY - h, width: unit * 1.4, height: h)), with: .color(blade.color.opacity(0.9)))
            x += unit * 2.2
            i += 1
        }
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

    /// Paths that connect real destinations (never a stub): home → garden, and — once the lake is
    /// open — home → bridge → lake. Both start at the doorstep so the home feels like a hub.
    private func drawPath(_ ctx: GraphicsContext, _ size: CGSize, _ camera: GardenCamera, unit: CGFloat, hasLake: Bool) {
        // Home → Garden (forward-right, into the flower beds).
        pathRibbon(ctx, size, camera, from: CGPoint(x: 12, y: homeBaseY + 22), to: CGPoint(x: 124, y: homeBaseY + 92),
                   topW: unit * 2.2, botW: unit * 6)
        // Home → Lake (forward-left, meeting the bridge).
        if hasLake {
            pathRibbon(ctx, size, camera, from: CGPoint(x: -12, y: homeBaseY + 22), to: CGPoint(x: -86, y: homeBaseY + 56),
                       topW: unit * 2.0, botW: unit * 3.4)
        }
    }

    private func pathRibbon(_ ctx: GraphicsContext, _ size: CGSize, _ camera: GardenCamera,
                            from a: CGPoint, to b: CGPoint, topW: CGFloat, botW: CGFloat) {
        let top = camera.project(a, parallax: 1.0, size: size)
        let bot = camera.project(b, parallax: 1.0, size: size)
        var p = Path()
        p.move(to: CGPoint(x: top.x - topW / 2, y: top.y))
        p.addLine(to: CGPoint(x: top.x + topW / 2, y: top.y))
        p.addLine(to: CGPoint(x: bot.x + botW / 2, y: bot.y))
        p.addLine(to: CGPoint(x: bot.x - botW / 2, y: bot.y))
        p.closeSubpath()
        ctx.fill(p, with: .color(GardenPalette.soilTop.color.opacity(0.9)))
    }

    /// A little wooden bridge where the lake path reaches the water's near edge.
    private func drawLakeBridge(_ ctx: GraphicsContext, _ size: CGSize, _ camera: GardenCamera, unit: CGFloat) {
        let a = camera.project(CGPoint(x: -84, y: homeBaseY + 54), parallax: 1.0, size: size)
        let b = camera.project(CGPoint(x: -116, y: homeBaseY + 40), parallax: 1.0, size: size)
        let wood = GardenPalette.woodFence
        // Deck (a few planks).
        let dx = (b.x - a.x) / 5, dy = (b.y - a.y) / 5
        for k in 0...5 {
            let px = a.x + dx * CGFloat(k), py = a.y + dy * CGFloat(k)
            rect(ctx, px - unit * 1.1, py - unit * 0.25, unit * 2.2, unit * 0.5, k % 2 == 0 ? wood : wood.lerp(to: GardenPalette.soilDark, 0.15))
        }
        // Rails.
        rect(ctx, a.x - unit * 0.9, a.y - unit * 1.2, unit * 0.3, unit * 1.0, wood)
        rect(ctx, b.x + unit * 0.6, b.y - unit * 1.2, unit * 0.3, unit * 1.0, wood)
    }

    // MARK: Zones — fixed world regions so the world reads clearly
    //   HOME  x ∈ [-70, 80] · GARDEN x ∈ [95, 245] · LAKE x ∈ [-245, -95]

    private enum PropKind { case tree, flower, patch, birdbath }
    private struct Prop { let x: CGFloat; let y: CGFloat; let kind: PropKind; let i: Int }

    /// ZONE 1 — the house and a couple of tidy home decorations. **No flowers.** Low density.
    private func drawHomeZone(_ ctx: GraphicsContext, _ size: CGSize, _ camera: GardenCamera, unit: CGFloat, unlocks u: GardenUnlocks, light: GardenLighting) {
        // The house is the visual anchor — the biggest, most central object in the world.
        drawHome(ctx, base: camera.project(CGPoint(x: 0, y: homeBaseY), parallax: 1.0, size: size), hs: unit * 4.2, light: light)
        drawMailbox(ctx, base: camera.project(CGPoint(x: -64, y: 118), parallax: 1.0, size: size), s: unit * 1.8)
        drawBench(ctx, base: camera.project(CGPoint(x: 56, y: 122), parallax: 1.0, size: size), s: unit * 1.9)
    }

    private struct GItem { let x: CGFloat; let y: CGFloat; let kind: PropKind; let i: Int; let color: Int }

    // Discrete milestone slots — each unlock lands in a fixed, well-separated spot so a new one is
    // instantly noticeable ("something appeared there"). Positions never shift as more unlock.
    private static let treeSlots:        [(CGFloat, CGFloat)] = [(132, 30), (220, 24), (172, 18)]
    private static let patchAnchors:     [(CGFloat, CGFloat)] = [(126, 150), (196, 140), (150, 176), (224, 166), (110, 128), (176, 116)]
    private static let singleSlots:      [(CGFloat, CGFloat)] = [(150, 158), (124, 168), (176, 168), (138, 150)]
    private static let birdbath:          (CGFloat, CGFloat)  = (200, 178)

    /// ZONE 2 — everything that grows, as **discrete milestone unlocks** (never density): a lone
    /// flower (entries 1–4), then big obvious flower *patches*, trees, and a birdbath. Each lands in a
    /// fixed slot so its arrival reads as a clear new addition. Depth-sorted (back → front).
    private func drawGardenZone(_ ctx: GraphicsContext, _ size: CGSize, _ camera: GardenCamera, unit: CGFloat, unlocks u: GardenUnlocks, light: GardenLighting, wind: Double, time: Double) {
        // Wind sway (px) — only noticeable in real wind; calm weather ⇒ plants stay still. Each
        // object sways on its own phase (by x) so the garden moves like a breeze, not in lockstep.
        func sway(_ x: CGFloat, _ amp: CGFloat) -> CGFloat {
            wind < 0.02 ? 0 : CGFloat(sin(time * 1.5 + Double(x) * 0.04)) * amp * CGFloat(wind)
        }
        var items: [GItem] = []
        for k in 0..<min(u.trees, Self.treeSlots.count) {
            items.append(GItem(x: Self.treeSlots[k].0, y: Self.treeSlots[k].1, kind: .tree, i: k, color: 0))
        }
        for k in 0..<min(u.flowerPatches, Self.patchAnchors.count) {
            items.append(GItem(x: Self.patchAnchors[k].0, y: Self.patchAnchors[k].1, kind: .patch, i: k, color: 0))
        }
        // Before the first patch unlocks (entries 1–4), show that many individual flowers.
        for k in 0..<min(u.singleFlowers, Self.singleSlots.count) {
            items.append(GItem(x: Self.singleSlots[k].0, y: Self.singleSlots[k].1, kind: .flower, i: k, color: k % GardenPalette.flowerVarieties.count))
        }
        if u.hasGardenDecor { items.append(GItem(x: Self.birdbath.0, y: Self.birdbath.1, kind: .birdbath, i: 0, color: 0)) }

        for it in items.sorted(by: { $0.y < $1.y }) {
            let p = camera.project(CGPoint(x: it.x, y: it.y), parallax: 1.0, size: size)
            let depth = max(0, min(1, it.y / 180))
            let m = 0.7 + depth * 0.7
            switch it.kind {
            case .tree:     drawTree(ctx, base: p, s: unit * 3.8 * m, light: light, sway: sway(it.x, unit * 0.9))
            case .flower:   drawFlower(ctx, base: p, s: unit * 1.6 * m, color: it.color, sway: sway(it.x, unit * 1.1))
            case .patch:    drawPatch(ctx, base: p, s: unit * 1.5 * m, seedIndex: it.i, sway: { sway($0, unit * 1.0) })
            case .birdbath: drawBirdbath(ctx, base: p, s: unit * 2.0 * m)
            }
        }
    }

    /// A simple stone birdbath — the first garden decoration (entry 45).
    private func drawBirdbath(_ ctx: GraphicsContext, base: CGPoint, s: CGFloat) {
        ctx.fill(Path(ellipseIn: CGRect(x: base.x - s * 0.5, y: base.y - s * 0.35, width: s, height: s * 0.4)),
                 with: .color(.black.opacity(0.12)))
        rect(ctx, base.x - s * 0.2, base.y - s * 1.6, s * 0.4, s * 1.4, GardenPalette.wallStone)          // pedestal
        rect(ctx, base.x - s * 0.7, base.y - s * 1.9, s * 1.4, s * 0.4, GardenPalette.wallStone)          // basin rim
        rect(ctx, base.x - s * 0.55, base.y - s * 1.82, s * 1.1, s * 0.22, GardenPalette.waterLight)       // water
    }

    private func drawCreatures(_ ctx: GraphicsContext, _ size: CGSize, _ camera: GardenCamera,
                               unit: CGFloat, unlocks u: GardenUnlocks, style: GardenStyle, time: Double) {
        let dim = style.ambientOpacity
        guard dim > 0.05 else { return }
        // Butterflies drift over the GARDEN ONLY (x ≥ 100), so the Home Area stays calm.
        for k in 0..<u.butterflies {
            let ph = Double(k) * 1.7 + 0.4
            let wx = CGFloat(110 + 42 * k) + CGFloat(sin(time * 0.5 + ph)) * 24
            let wy = 70 + CGFloat(k % 2) * 30 + CGFloat(cos(time * 0.7 + ph)) * 14
            let p = camera.project(CGPoint(x: wx, y: wy), parallax: 1.0, size: size)
            drawButterfly(ctx, at: p, s: unit * 1.0, flap: sin(time * 6 + ph),
                          color: GardenPalette.flowerVarieties[k % 5], alpha: dim)
        }
        // Fireflies drift softly over the garden.
        for k in 0..<u.fireflies {
            let ph = Double(k) * 0.9 + 1.1
            let wx = CGFloat(108 + 26 * k) + CGFloat(sin(time * 0.4 + ph)) * 22
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

    /// A grounding shadow that lengthens and leans away from the sun as the day progresses.
    private func groundShadow(_ ctx: GraphicsContext, base: CGPoint, halfW: CGFloat, light: GardenLighting, alpha: Double = 0.12) {
        let stretch = halfW * (1 + (light.shadowScale - 1) * 1.3)
        let cx = base.x + light.shadowDir * (stretch - halfW)
        let h = halfW * 0.55
        let a = alpha * (light.isNight ? 0.6 : 1.0)
        ctx.fill(Path(ellipseIn: CGRect(x: cx - stretch, y: base.y - h * 0.4, width: stretch * 2, height: h)),
                 with: .color(.black.opacity(a)))
    }

    private func drawHome(_ ctx: GraphicsContext, base: CGPoint, hs: CGFloat, light: GardenLighting) {
        groundShadow(ctx, base: base, halfW: hs * 4, light: light)
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
        // Warm interior light spilling from the windows at dusk/night — sells "someone's home".
        if light.windowGlow > 0.01 {
            let gc = CGPoint(x: base.x, y: base.y - wallH * 0.55)
            let gr = hs * 5
            ctx.fill(Path(ellipseIn: CGRect(x: gc.x - gr, y: gc.y - gr, width: gr * 2, height: gr * 2)),
                     with: .radialGradient(Gradient(colors: [GardenPalette.windowGlow.color.opacity(0.55 * light.windowGlow), .clear]),
                                           center: gc, startRadius: 0, endRadius: gr))
        }
    }

    private func drawTree(_ ctx: GraphicsContext, base: CGPoint, s: CGFloat, light: GardenLighting, sway: CGFloat = 0) {
        groundShadow(ctx, base: base, halfW: s * 1.3, light: light, alpha: 0.10)
        let trunkW = s * 0.7, trunkH = s * 2.2
        rect(ctx, base.x - trunkW / 2, base.y - trunkH, trunkW, trunkH, GardenPalette.soilDark)
        // The canopy leans with the wind (anchored at the trunk top) — the trunk stays put.
        let cx = base.x + sway
        let cy = base.y - trunkH - s
        let r = s * 1.7
        ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)), with: .color(GardenPalette.leafDark.color))
        ctx.fill(Path(ellipseIn: CGRect(x: cx - r * 0.8, y: cy - r * 1.05, width: r * 1.6, height: r * 1.6)), with: .color(GardenPalette.leafMid.color))
        ctx.fill(Path(ellipseIn: CGRect(x: cx - r * 0.45, y: cy - r * 1.1, width: r * 0.9, height: r * 0.9)), with: .color(GardenPalette.leafLight.color))
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

    private func drawFlower(_ ctx: GraphicsContext, base: CGPoint, s: CGFloat, color: Int, sway: CGFloat = 0) {
        let petal = GardenPalette.flowerVarieties[color % GardenPalette.flowerVarieties.count]
        ctx.fill(Path(ellipseIn: CGRect(x: base.x - s * 0.8, y: base.y - s * 0.2, width: s * 1.6, height: s * 0.4)), with: .color(.black.opacity(0.08)))
        let headY = base.y - 2.6 * s
        // The head leans with the wind; the base of the stem stays rooted.
        let hx = base.x + sway
        var stem = Path()
        stem.move(to: CGPoint(x: base.x - s * 0.25, y: base.y)); stem.addLine(to: CGPoint(x: base.x + s * 0.25, y: base.y))
        stem.addLine(to: CGPoint(x: hx + s * 0.25, y: headY));   stem.addLine(to: CGPoint(x: hx - s * 0.25, y: headY))
        stem.closeSubpath()
        ctx.fill(stem, with: .color(GardenPalette.stemLight.color))
        let hi = petal.lerp(to: GardenPalette.petalWhite, 0.3)
        rect(ctx, hx - s * 0.5, headY - s, s, s, hi)
        rect(ctx, hx - s * 1.5, headY, s, s, petal)
        rect(ctx, hx + s * 0.5, headY, s, s, petal)
        rect(ctx, hx - s * 0.5, headY + s, s, s, hi)
        rect(ctx, hx - s * 0.5, headY, s, s, GardenPalette.flowerCenter)
    }

    /// A composed cluster of a few flowers (one dominant colour) — a flower bed. Each head sways on
    /// its own phase via the passed-in `sway(x)` so the bed ripples in wind (still when calm).
    private func drawPatch(_ ctx: GraphicsContext, base: CGPoint, s: CGFloat, seedIndex: Int, sway: (CGFloat) -> CGFloat = { _ in 0 }) {
        var rng = SeededGenerator(seed: gardenCellSeed(worldSeed, seedIndex, 0xBED))
        let dominant = Int(rng.next() % UInt64(GardenPalette.flowerVarieties.count))
        let count = 12   // a full, obvious bed — not a sprinkle
        var pts: [(CGFloat, CGFloat, Int)] = []
        for _ in 0..<count {
            let dx = CGFloat(rng.double(in: -1, 1)) * s * 4.2
            let dy = CGFloat(rng.double(in: -1, 1)) * s * 1.8
            let col = rng.double(in: 0, 1) < 0.8 ? dominant : Int(rng.next() % UInt64(GardenPalette.flowerVarieties.count))
            pts.append((dx, dy, col))
        }
        for f in pts.sorted(by: { $0.1 < $1.1 }) {
            let fx = base.x + f.0
            drawFlower(ctx, base: CGPoint(x: fx, y: base.y + f.1), s: s, color: f.2, sway: sway(fx))
        }
    }

    private func drawStone(_ ctx: GraphicsContext, base: CGPoint, s: CGFloat) {
        ctx.fill(Path(ellipseIn: CGRect(x: base.x - s, y: base.y - s * 0.7, width: s * 2, height: s * 1.1)), with: .color(GardenPalette.mountainRock.color))
        ctx.fill(Path(ellipseIn: CGRect(x: base.x - s * 0.6, y: base.y - s * 0.7, width: s * 1.1, height: s * 0.6)), with: .color(GardenPalette.wallStone.color.opacity(0.6)))
    }

    private func drawFence(_ ctx: GraphicsContext, _ size: CGSize, _ camera: GardenCamera, unit: CGFloat) {
        let postW = unit * 0.7, postH = unit * 2.2
        for wx in stride(from: CGFloat(98), through: 244, by: 40) {   // borders the garden, not the home
            let p = camera.project(CGPoint(x: wx, y: 58), parallax: 1.0, size: size)
            rect(ctx, p.x - postW / 2, p.y - postH, postW, postH, GardenPalette.woodFence)
            let next = camera.project(CGPoint(x: wx + 40, y: 58), parallax: 1.0, size: size)
            rect(ctx, p.x, p.y - postH * 0.7, max(1, next.x - p.x), postH * 0.28, GardenPalette.woodFence.lerp(to: GardenPalette.soilDark, 0.1))
        }
    }

    // MARK: ZONE 3 — the lake (pond, lily pads, shimmer, a duck, a fish shadow)

    private func drawLake(_ ctx: GraphicsContext, _ size: CGSize, _ camera: GardenCamera, unit: CGFloat, unlocks u: GardenUnlocks, time: Double) {
        let c = camera.project(CGPoint(x: -158, y: 124), parallax: 1.0, size: size)
        let w = 138 * camera.zoom, h = 50 * camera.zoom
        // Water + a lighter inner pool.
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)), with: .color(GardenPalette.water.color))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - w * 0.38, y: c.y - h * 0.34, width: w * 0.76, height: h * 0.68)), with: .color(GardenPalette.waterLight.color.opacity(0.7)))
        // Gentle shimmer (the only ambient motion in this zone).
        for i in 0..<3 {
            let off = CGFloat(i) * h * 0.18 - h * 0.18
            let drift = CGFloat(sin(time * 0.8 + Double(i))) * w * 0.06
            rect(ctx, c.x - w * 0.22 + drift, c.y + off, w * 0.44, max(1, unit * 0.3), GardenPalette.waterLight, 0.8)
        }
        // Fish shadow gliding under the surface.
        let fx = c.x + CGFloat(sin(time * 0.5)) * w * 0.22
        ctx.fill(Path(ellipseIn: CGRect(x: fx - unit, y: c.y + h * 0.1, width: unit * 2, height: unit * 0.8)), with: .color(.black.opacity(0.12)))
        // Lily pads.
        for (dx, dy) in [(-0.28, 0.06), (0.18, -0.12), (0.30, 0.16)] as [(CGFloat, CGFloat)] {
            let lx = c.x + dx * w, ly = c.y + dy * h
            ctx.fill(Path(ellipseIn: CGRect(x: lx - unit * 0.9, y: ly - unit * 0.5, width: unit * 1.8, height: unit)), with: .color(GardenPalette.lilyPad.color))
        }
        // A calm little duck glides on the lake.
        do {
            let dx = c.x + CGFloat(sin(time * 0.25)) * w * 0.18
            let dy = c.y - h * 0.16
            ctx.fill(Path(ellipseIn: CGRect(x: dx - unit * 1.1, y: dy - unit * 0.5, width: unit * 2.2, height: unit * 1.1)), with: .color(GardenPalette.duckBody.color))
            ctx.fill(Path(ellipseIn: CGRect(x: dx - unit * 1.6, y: dy - unit * 1.1, width: unit, height: unit)), with: .color(GardenPalette.duckBody.color))
        }
    }

    // MARK: Home decorations

    private func drawBench(_ ctx: GraphicsContext, base: CGPoint, s: CGFloat) {
        ctx.fill(Path(ellipseIn: CGRect(x: base.x - s * 1.6, y: base.y - s * 0.2, width: s * 3.2, height: s * 0.5)), with: .color(.black.opacity(0.10)))
        rect(ctx, base.x - s * 1.4, base.y - s * 1.0, s * 2.8, s * 0.5, GardenPalette.woodFence)        // seat
        rect(ctx, base.x - s * 1.4, base.y - s * 2.0, s * 0.4, s * 1.1, GardenPalette.woodFence)        // back posts
        rect(ctx, base.x + s * 1.0, base.y - s * 2.0, s * 0.4, s * 1.1, GardenPalette.woodFence)
        rect(ctx, base.x - s * 1.4, base.y - s * 1.7, s * 2.8, s * 0.3, GardenPalette.woodFence)        // backrest
        rect(ctx, base.x - s * 1.2, base.y - s * 0.5, s * 0.35, s * 0.5, GardenPalette.woodFence.lerp(to: GardenPalette.soilDark, 0.2))   // legs
        rect(ctx, base.x + s * 0.85, base.y - s * 0.5, s * 0.35, s * 0.5, GardenPalette.woodFence.lerp(to: GardenPalette.soilDark, 0.2))
    }

    private func drawMailbox(_ ctx: GraphicsContext, base: CGPoint, s: CGFloat) {
        ctx.fill(Path(ellipseIn: CGRect(x: base.x - s, y: base.y - s * 0.2, width: s * 2, height: s * 0.4)), with: .color(.black.opacity(0.10)))
        rect(ctx, base.x - s * 0.18, base.y - s * 2.4, s * 0.36, s * 2.4, GardenPalette.soilDark)        // post
        rect(ctx, base.x - s * 0.8, base.y - s * 3.4, s * 1.6, s * 1.1, GardenPalette.roofRed)           // box
        rect(ctx, base.x - s * 0.8, base.y - s * 3.4, s * 0.4, s * 1.1, GardenPalette.roofRed.lerp(to: GardenPalette.petalWhite, 0.25)) // little flag
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
