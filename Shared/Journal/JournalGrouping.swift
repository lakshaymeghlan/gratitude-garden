import Foundation

/// A day's worth of journal entries, for the history view.
struct JournalDaySection: Identifiable, Equatable {
    /// Start-of-day, doubles as a stable identity.
    let day: Date
    let entries: [Entry]
    var id: Date { day }
}

/// Pure grouping/search logic for the journal history view — kept out of the view so it's testable.
enum JournalGrouping {
    /// Groups entries by calendar day (newest day first; newest entry first within a day) and
    /// optionally filters by a case-insensitive text query.
    static func sections(from entries: [Entry],
                         query: String = "",
                         calendar: Calendar = .current) -> [JournalDaySection] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = trimmed.isEmpty
            ? entries
            : entries.filter { $0.text.localizedCaseInsensitiveContains(trimmed) }

        let grouped = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in
            JournalDaySection(day: day, entries: grouped[day]!.sorted { $0.date > $1.date })
        }
    }
}
