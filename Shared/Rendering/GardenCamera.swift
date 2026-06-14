import CoreGraphics

/// A real camera over an effectively-infinite world. The renderer projects **world coordinates**
/// through this camera to screen, rather than drawing in screen space — so panning/zooming reveal
/// more of the world, and there are no fixed scene edges.
///
/// World space: `x` extends infinitely (the meadow runs forever left/right). `y` = 0 is the horizon;
/// y < 0 is sky/up (mountains), y > 0 is the ground/foreground. Vertical movement is clamped so the
/// horizon stays framed; horizontal movement is free.
struct GardenCamera: Equatable {
    /// World point the camera is centered on (screen center maps near here).
    var position: CGPoint
    /// Scale factor. 1 = default; >1 zoom in (bigger), <1 zoom out (more world visible).
    var zoom: CGFloat

    static let minZoom: CGFloat = 0.85
    static let maxZoom: CGFloat = 2.2
    /// Centered on the home, framed so the home + garden fill the screen (intimate, not a vast vista).
    static let `default` = GardenCamera(position: CGPoint(x: 0, y: 70), zoom: 1.0)

    /// Fraction of screen height where the world horizon (y = 0, at camera.y = 0) sits.
    static let horizonFraction: CGFloat = 0.48

    func clampedZoom() -> CGFloat { min(max(zoom, Self.minZoom), Self.maxZoom) }

    /// Keeps the view intimate: small zoom range and a **bounded** pan, so you can look around your
    /// garden a little but never wander off into empty landscape. The garden stays the focus.
    func clamped() -> GardenCamera {
        GardenCamera(position: CGPoint(x: min(max(position.x, -150), 150),
                                       y: min(max(position.y, 10), 130)),
                     zoom: clampedZoom())
    }

    /// Projects a world point to screen, with a per-layer horizontal `parallax` (1 = foreground,
    /// smaller = further back, moves less while panning). Vertical has no parallax so every layer
    /// shares one horizon.
    func project(_ world: CGPoint, parallax: CGFloat, size: CGSize) -> CGPoint {
        CGPoint(x: (world.x - position.x * parallax) * zoom + size.width / 2,
                y: (world.y - position.y) * zoom + size.height * Self.horizonFraction)
    }

    /// The world-X interval visible for a given parallax layer (plus a margin), so the renderer can
    /// cull to only the chunks on screen.
    func visibleWorldX(parallax: CGFloat, size: CGSize, margin: CGFloat) -> (min: CGFloat, max: CGFloat) {
        let center = position.x * parallax
        let half = (size.width / 2) / zoom + margin
        return (center - half, center + half)
    }

    /// Screen-Y of the horizon (world y = 0).
    func horizonScreenY(size: CGSize) -> CGFloat {
        (0 - position.y) * zoom + size.height * Self.horizonFraction
    }
}

/// Deterministic per-chunk seed. The world is divided into fixed-width cells along X; each cell's
/// contents are generated from its index + a world seed, so the world is infinite, reproducible
/// (same on app and widget), and stable as you pan back and forth.
@inline(__always)
func gardenCellSeed(_ base: UInt64, _ cell: Int, _ salt: UInt64) -> UInt64 {
    var h = base ^ salt
    h = (h ^ UInt64(bitPattern: Int64(cell))) &* 1099511628211
    h = (h ^ (h >> 29)) &* 0xBF58476D1CE4E5B9
    return h == 0 ? 0x9E3779B97F4A7C15 : h
}
