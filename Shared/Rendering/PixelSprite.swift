import SwiftUI

/// A hand-authored pixel-art sprite, expressed as an ASCII grid + a legend mapping each character
/// to a palette color. `'.'` (and any char missing from the legend) is transparent.
///
/// Why ASCII grids: they're readable and editable directly in code, version-control-friendly, and
/// — critically — they render as **vector rectangles** (not a scaled bitmap), so there is no image
/// interpolation and the result is perfectly crisp at any integer scale. This is the procedural art
/// that ships today; commissioned bitmap art swaps in behind `GardenArtProvider` later without
/// touching any rendering code.
struct PixelSprite {
    let rows: [String]
    let legend: [Character: RGB]
    let width: Int
    let height: Int

    init(_ rows: [String], legend: [Character: RGB]) {
        let w = rows.map(\.count).max() ?? 0
        // Right-pad short rows so column indices line up regardless of trailing transparency.
        self.rows = rows.map { $0.count == w ? $0 : $0 + String(repeating: ".", count: w - $0.count) }
        self.legend = legend
        self.width = w
        self.height = rows.count
    }
}

/// Anything the scene can draw for a plant. Both `PixelSprite` (today) and a future image-backed
/// type conform, so the renderer is agnostic to *how* the art is produced — the swap seam.
protocol GardenDrawable {
    var pixelWidth: Int { get }
    var pixelHeight: Int { get }
    /// Draws into `context` at the given integer `scale`, with the sprite's **bottom-center**
    /// placed at `bottomCenter` (so plants are anchored at their base for sway/droop rotation).
    func draw(into context: GraphicsContext, scale: CGFloat, bottomCenter: CGPoint)
}

extension PixelSprite: GardenDrawable {
    var pixelWidth: Int { width }
    var pixelHeight: Int { height }

    func draw(into context: GraphicsContext, scale: CGFloat, bottomCenter: CGPoint) {
        let originX = bottomCenter.x - CGFloat(width) * scale / 2
        let originY = bottomCenter.y - CGFloat(height) * scale
        for (r, row) in rows.enumerated() {
            for (c, ch) in row.enumerated() {
                guard let rgb = legend[ch] else { continue }
                let rect = CGRect(x: originX + CGFloat(c) * scale,
                                  y: originY + CGFloat(r) * scale,
                                  width: scale, height: scale)
                context.fill(Path(rect), with: .color(rgb.color))
            }
        }
    }
}

/// Standalone crisp renderer for a single sprite — used by the preview gallery and handy for
/// eyeballing commissioned art. Integer scaling guarantees no blur.
struct PixelSpriteView: View {
    let sprite: PixelSprite

    var body: some View {
        Canvas { context, size in
            guard sprite.width > 0, sprite.height > 0 else { return }
            let scale = max(1, floor(min(size.width / CGFloat(sprite.width),
                                         size.height / CGFloat(sprite.height))))
            let bottomCenter = CGPoint(x: (size.width / 2).rounded(),
                                       y: (size.height / 2 + CGFloat(sprite.height) * scale / 2).rounded())
            sprite.draw(into: context, scale: scale, bottomCenter: bottomCenter)
        }
    }
}
