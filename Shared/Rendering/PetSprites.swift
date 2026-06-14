import SwiftUI

/// Which pose to show. The scene maps `PetState` → a frame (resting→idle, play 0→happy, play 1→walk).
enum PetFrame { case idle, walk, sleep, happy }

/// Hand-authored, original pixel-art companions — side profile, chunky, readable at small size, with
/// a **unique silhouette per animal**. The **last row is always the feet**, so when the sprite is
/// anchored bottom-center on the ground the animal stands on it (never floats).
enum PetSprites {

    static func sprite(_ type: PetType, _ frame: PetFrame) -> PixelSprite {
        if frame == .sleep {
            // Reuse the idle silhouette but close the eyes (E → body) so any animal reads as asleep.
            let closed = rows(type, .idle).map { $0.replacingOccurrences(of: "E", with: "B") }
            return PixelSprite(closed, legend: legend(type))
        }
        return PixelSprite(rows(type, frame), legend: legend(type))
    }

    // B body · D dark accent (ears/mane/spots/hooves/horns) · L light belly · E eye · W bright wool
    private static func legend(_ t: PetType) -> [Character: RGB] {
        [
            "B": t.bodyColor,
            "D": t.accentColor,
            "L": t.bodyColor.lerp(to: RGB(r: 255, g: 255, b: 255), 0.30),
            "E": RGB(r: 40, g: 34, b: 32),
            "W": t.bodyColor.lerp(to: RGB(r: 255, g: 255, b: 255), 0.55),
        ]
    }

    private static func rows(_ t: PetType, _ f: PetFrame) -> [String] {
        switch t {
        case .cat:   return cat()
        case .dog:   return dog(f)
        case .sheep: return sheep()
        case .cow:   return cow(f)
        case .horse: return horse(f)
        case .goat:  return goat()
        }
    }

    // Cat — sitting, pointy ears, tail (bottom row = paws)
    private static func cat() -> [String] {
        [
            "..D.....D.....",
            "..DB...DB.....",
            "..BBB.BBB.....",
            "..BBBBBBB....B",
            "..BEBBBBB...BB",
            "...BBBBBB..BB.",
            "...BBBBBBBBB..",
            "..BBBBBBBBBB..",
            "..BBBBBBBBBB..",
            "..BBBBBBBBBB..",
            "..LLBBBBBBLL..",
        ]
    }

    // Dog — floppy ears, snout, upright tail (bottom row = paws)
    private static func dog(_ f: PetFrame) -> [String] {
        let legs = (f == .walk) ? "...BBB...BBB.." : "..BB.BB..BB.BB"
        return [
            "..BBB.......B.",
            ".BBBBB.....BB.",
            "DDBBBB....BBB.",
            "DDBEBBBBBBBB..",
            "DBBBBBBBBBBBB.",
            "..BBBBBBBBBBB.",
            "..BBBBBBBBBBB.",
            legs,
            "..DD.DD..DD.DD",
        ]
    }

    // Sheep — fluffy bumpy body, small dark face (bottom row = legs)
    private static func sheep() -> [String] {
        [
            "...WW.WW.WW...",
            "..WWWWWWWWWW..",
            ".WWWWWWWWWWWW.",
            "DDWWWWWWWWWWW.",
            "DDWWWWWWWWWWW.",
            ".WWWWWWWWWWWW.",
            "..WWWWWWWWWW..",
            "...D..D.D..D..",
            "...D..D.D..D..",
        ]
    }

    // Cow — large body, spots, small horns (bottom row = hooves)
    private static func cow(_ f: PetFrame) -> [String] {
        let legs = (f == .walk) ? "...BB.....BB.." : "..B.BB...BB.B."
        return [
            "..D........D..",
            ".BBB..........",
            ".BBBB.........",
            ".BEBBBBBBBBBB.",
            ".BBBBDDBBBBBB.",
            ".BBBBBBBBBDDB.",
            ".BBBBBBBBBBBB.",
            ".BBBBBBBBBBBB.",
            legs,
            "..D.DD...DD.D.",
        ]
    }

    // Horse — long body, mane along neck/back, long legs (bottom row = hooves)
    private static func horse(_ f: PetFrame) -> [String] {
        let legs = (f == .walk) ? "...B..BB.B..B." : "...B..B..B..B."
        return [
            "...DD.........",
            "..BBDD........",
            "..BBBDDD......",
            "..BBBBBDDDD...",
            "...BBBBBBBBBD.",
            "...BBBBBBBBBD.",
            "...BBBBBBBBBB.",
            legs,
            "...B..B..B..B.",
            "...D..D..D..D.",
        ]
    }

    // Goat — small horns swept back, beard, short legs (bottom row = hooves)
    private static func goat() -> [String] {
        [
            "....DD........",
            "...DD.........",
            "..BBBB......B.",
            "..BBBBB....BB.",
            ".BEBBBBBBBBBB.",
            ".DBBBBBBBBBBB.",
            ".DBBBBBBBBBBB.",
            "..BB.BB.BB.BB.",
            "..DD.DD.DD.DD.",
        ]
    }
}
