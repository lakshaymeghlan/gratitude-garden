import SwiftUI

/// A calm, reflective history of everything the user has logged — grouped by day, searchable.
/// Reading-only; the tone is gentle and unhurried, never a productivity ledger.
struct JournalView: View {
    let entries: [Entry]

    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var sections: [JournalDaySection] {
        JournalGrouping.sections(from: entries, query: query)
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                emptyState(title: "Your journal is waiting",
                           message: "Whenever you tend your garden, your moments will gather here.")
            } else if sections.isEmpty {
                emptyState(title: "Nothing matches",
                           message: "Try a different word — every moment you've logged is still here.")
            } else {
                List {
                    ForEach(sections) { section in
                        Section(header: Text(section.day.formatted(date: .complete, time: .omitted))) {
                            ForEach(section.entries) { entry in
                                row(entry)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Journal")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search your moments")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func row(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(GardenCopy.kindLabel(entry.kind))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(entry.text)
                .font(.body)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(GardenCopy.kindLabel(entry.kind)): \(entry.text)")
    }

    private func emptyState(title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Text(title).font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NavigationStack {
        JournalView(entries: [
            Entry(date: .now, text: "the smell of rain", kind: .gratitude),
            Entry(date: .now.addingTimeInterval(-90_000), text: "got out of bed", kind: .gotThrough),
        ])
    }
}
