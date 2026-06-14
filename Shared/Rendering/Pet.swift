import SwiftUI

/// How the companion is posed this frame — small, calm amplitudes (cozy, never hyperactive). The
/// sprite supplies the look; the pose nudges its position for a little life.
struct PetPose {
    var moveX: CGFloat = 0      // gentle lateral drift (s units)
    var hopY: CGFloat = 0       // hop height (s units)
    var bobY: CGFloat = 0       // breathing / idle bob (s units)
    var eyesOpen: Bool = false
}

enum Pet {

    /// The pet **always** lives in the Home Area, on a dedicated, clearly-spaced patch of lawn in
    /// front-left of the house — never overlapping flowers, trees, the path, the lake, or the house.
    /// Fixed (not stage-dependent) so it stays readable however dense the garden becomes.
    static func restSpot(_ u: GardenUnlocks) -> CGPoint {
        CGPoint(x: -44, y: 130)
    }

    /// Pose for the current state + time. Resting = breathing + a barely-there wander. Playing = a
    /// gentle bounce (variant 0) or a gentle walk (variant 1).
    static func pose(_ type: PetType, _ state: PetState, time: Double) -> PetPose {
        var p = PetPose()
        switch state {
        case .resting:
            p.bobY = 0.16 * CGFloat(sin(time * 0.9))
            p.moveX = 0.5 * CGFloat(sin(time * 0.22))   // very slow idle wander
            p.eyesOpen = false
        case .playing(let v):
            p.eyesOpen = true
            if v == 0 {                                  // happy: bounce in place
                p.hopY = 0.5 * CGFloat(abs(sin(time * 3.2)))
            } else {                                     // walk: drift gently
                p.moveX = 2.0 * CGFloat(sin(time * 1.4))
                p.hopY = 0.18 * CGFloat(abs(sin(time * 5)))
            }
        }
        return p
    }

    static func frame(for state: PetState) -> PetFrame {
        switch state {
        case .resting:        return .idle
        case .playing(let v): return v == 0 ? .happy : .walk
        }
    }

    static func accessibility(_ type: PetType, state: PetState, home: HomeStyle) -> String {
        switch state {
        case .playing:
            return "Your companion \(type.displayName.lowercased()) is happily exploring the garden."
        case .resting:
            return "Your companion \(type.displayName.lowercased()) is resting near your \(home.displayName.lowercased())."
        }
    }

    // MARK: Drawing — pixel-art sprite (crisp, integer-scaled). Only the frame + position animate.

    static func draw(_ ctx: GraphicsContext, type: PetType, base: CGPoint, s: CGFloat, frame: PetFrame, pose: PetPose) {
        let sprite = PetSprites.sprite(type, frame)

        // Grounding shadow (shrinks a touch on a hop).
        let shW = s * 3.0 * (1 - min(0.3, pose.hopY * 0.3))
        ctx.fill(Path(ellipseIn: CGRect(x: base.x - shW / 2, y: base.y - s * 0.18, width: shW, height: s * 0.4)),
                 with: .color(.black.opacity(0.12)))

        // Integer scale so the pixels stay crisp; sized to read clearly without being large.
        let targetHeight = s * 2.8
        let scale = max(2, (targetHeight / CGFloat(max(1, sprite.height))).rounded())
        let bottom = CGPoint(x: base.x + pose.moveX * s, y: base.y - (pose.hopY + pose.bobY) * s)
        sprite.draw(into: ctx, scale: scale, bottomCenter: bottom)
    }
}
