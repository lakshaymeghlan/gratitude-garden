import Foundation

/// Warm, supportive copy + SF Symbol names for the garden's states.
///
/// Lives in `Shared/` (plain strings, no SwiftUI) so the app and the Phase 4 widget speak with one
/// gentle voice. **The forgiving tone is enforced here** — every string is an invitation, never an
/// accusation. There is intentionally no "you missed", "streak lost", "inactive", or "dead".
enum GardenCopy {

    // MARK: Garden vitality

    /// Headline for the garden's current state. Revival takes priority over vitality.
    static func vitalityTitle(_ vitality: Vitality, isReviving: Bool) -> String {
        if isReviving { return "Welcome back" }
        switch vitality {
        case .thriving: return "Your garden is thriving"
        case .drooping: return "Your garden is waiting for you"
        case .dormant:  return "Dormant and ready to bloom again"
        }
    }

    /// Gentle supporting line.
    static func vitalitySubtitle(_ vitality: Vitality, isReviving: Bool) -> String {
        if isReviving { return "One small thing brought it back to life. 🌿" }
        switch vitality {
        case .thriving: return "Thank you for tending it today."
        case .drooping: return "Whenever you're ready — there's no rush."
        case .dormant:  return "It's been resting, and it remembers you. Any moment you return, it begins again."
        }
    }

    /// Very short status for the widget, where space is tight and the garden is the hero.
    static func widgetShort(_ vitality: Vitality, isReviving: Bool) -> String {
        if isReviving { return "Welcome back" }
        switch vitality {
        case .thriving: return "Thriving"
        case .drooping: return "Waiting for you"
        case .dormant:  return "Ready to bloom again"
        }
    }

    // MARK: Growth stage

    static func growthTitle(_ stage: GrowthStage) -> String {
        switch stage {
        case .seed:        return "Seed"
        case .sprout:      return "Sprout"
        case .seedling:    return "Seedling"
        case .budding:     return "Budding"
        case .blooming:    return "Blooming"
        case .flourishing: return "Flourishing"
        }
    }

    /// A full spoken description of the garden for VoiceOver — the pixel art is decorative, so this
    /// is how non-visual users perceive the garden's state.
    static func accessibilityDescription(growth: GrowthStage,
                                         vitality: Vitality,
                                         isReviving: Bool,
                                         lastEntry: Date?) -> String {
        var parts: [String] = []
        parts.append(isReviving ? "Welcome back. Your garden is coming back to life."
                                : vitalityTitle(vitality, isReviving: false) + ".")
        parts.append("Growth stage: \(growthTitle(growth).lowercased()).")
        if let lastEntry {
            parts.append("Last tended \(lastEntry.formatted(date: .abbreviated, time: .omitted)).")
        } else {
            parts.append("Not tended yet.")
        }
        return parts.joined(separator: " ")
    }

    // MARK: Entry kinds — prompts & labels

    /// The supportive prompt shown while composing each kind of entry.
    static func prompt(_ kind: EntryKind) -> String {
        switch kind {
        case .gratitude:        return "What are you grateful for today?"
        case .gotThrough:       return "What did you get through today?"
        case .lookingForwardTo: return "What are you looking forward to?"
        }
    }

    /// Short label for pickers and journal rows.
    static func kindLabel(_ kind: EntryKind) -> String {
        switch kind {
        case .gratitude:        return "Grateful for"
        case .gotThrough:       return "Got through"
        case .lookingForwardTo: return "Looking forward to"
        }
    }

    // MARK: Empty / first-run

    static let emptyJournalPrompt = "Your garden is ready for its first seed. What's one small thing today?"
}
