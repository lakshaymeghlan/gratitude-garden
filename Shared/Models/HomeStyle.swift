import Foundation

/// The one home the user picks at onboarding. It's the permanent emotional center of the world; the
/// garden grows around it. Stored in `AppPreferences` (a one-time, durable choice).
enum HomeStyle: String, Codable, CaseIterable, Identifiable {
    case cottage
    case japanese
    case cabin
    case wizard

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cottage:  return "Cozy Cottage"
        case .japanese: return "Japanese House"
        case .cabin:    return "Forest Cabin"
        case .wizard:   return "Wizard Hut"
        }
    }

    var blurb: String {
        switch self {
        case .cottage:  return "Warm and welcoming."
        case .japanese: return "Calm and quiet."
        case .cabin:    return "Snug among the trees."
        case .wizard:   return "A little bit magical."
        }
    }
}
