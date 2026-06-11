import Foundation

/// What kind of thing the user logged today.
///
/// Forgiving design: there is no "wrong" entry. On good days people log gratitude; on hard days
/// they can name something they *got through*, or something they're *looking forward to* — so a
/// bad day never demands a feeling they don't have.
enum EntryKind: String, Codable, CaseIterable, Identifiable {
    case gratitude
    case gotThrough
    case lookingForwardTo

    var id: String { rawValue }

    /// Tolerant decoding so old saved data never fails to load. Phases 0–1 used a single `soft`
    /// case for "anything that got you through" — that migrates to `.gotThrough`. Any unknown raw
    /// value falls back to `.gratitude` (a safe, forgiving default) rather than throwing.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "gratitude":        self = .gratitude
        case "gotThrough":       self = .gotThrough
        case "lookingForwardTo": self = .lookingForwardTo
        case "soft":             self = .gotThrough   // legacy migration
        default:                 self = .gratitude    // forgiving fallback
        }
    }
}

/// A single journal entry.
struct Entry: Identifiable, Codable, Equatable {
    let id: UUID
    /// The moment the entry was made. (The rules engine normalizes to start-of-day itself.)
    let date: Date
    let text: String
    let kind: EntryKind

    init(id: UUID = UUID(), date: Date, text: String, kind: EntryKind) {
        self.id = id
        self.date = date
        self.text = text
        self.kind = kind
    }
}
