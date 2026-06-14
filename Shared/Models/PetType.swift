import Foundation

/// The user's chosen companion — a permanent, happy resident of the garden. Not a responsibility:
/// no feeding, no health, no streaks, no chores. It simply shares the space.
enum PetType: String, Codable, CaseIterable, Identifiable {
    case cat, dog, cow, goat, sheep, horse

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cat: return "Cat"
        case .dog: return "Dog"
        case .cow: return "Cow"
        case .goat: return "Goat"
        case .sheep: return "Sheep"
        case .horse: return "Horse"
        }
    }

    /// Main body colour.
    var bodyColor: RGB {
        switch self {
        case .cat:   return RGB(r: 228, g: 168, b: 110)
        case .dog:   return RGB(r: 182, g: 142, b: 98)
        case .cow:   return RGB(r: 244, g: 242, b: 236)
        case .goat:  return RGB(r: 206, g: 192, b: 162)
        case .sheep: return RGB(r: 240, g: 238, b: 230)
        case .horse: return RGB(r: 150, g: 110, b: 78)
        }
    }

    /// Secondary colour (ears, spots, mane, hooves).
    var accentColor: RGB {
        switch self {
        case .cat:   return RGB(r: 198, g: 138, b: 84)
        case .dog:   return RGB(r: 120, g: 88,  b: 58)
        case .cow:   return RGB(r: 70,  g: 64,  b: 60)
        case .goat:  return RGB(r: 150, g: 138, b: 110)
        case .sheep: return RGB(r: 80,  g: 74,  b: 70)
        case .horse: return RGB(r: 70,  g: 52,  b: 38)
        }
    }
}

/// What the companion is doing right now. Resting is the calm default; tapping plays one of two
/// gentle animations, then it settles back. (No "sick / hungry / sad" states ever exist.)
enum PetState: Equatable {
    case resting
    case playing(Int)   // 0 or 1 — the two tap animations
}
