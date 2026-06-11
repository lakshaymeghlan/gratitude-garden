import Foundation

/// Produces a plain-text export of the journal — everything stays on-device; the user shares it via
/// the system share sheet if and when *they* choose to. Pure + testable.
enum JournalExport {
    static func plainText(_ entries: [Entry], calendar: Calendar = .current) -> String {
        guard !entries.isEmpty else {
            return "Gratitude Garden\n\nYour journal is empty for now."
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateStyle = .full
        formatter.timeStyle = .none

        var lines = ["Gratitude Garden — your journal", ""]
        let sections = JournalGrouping.sections(from: entries, calendar: calendar)
        for section in sections {
            lines.append(formatter.string(from: section.day))
            for entry in section.entries {
                lines.append("  • [\(label(entry.kind))] \(entry.text)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func label(_ kind: EntryKind) -> String {
        switch kind {
        case .gratitude:        return "Grateful for"
        case .gotThrough:       return "Got through"
        case .lookingForwardTo: return "Looking forward to"
        }
    }
}
