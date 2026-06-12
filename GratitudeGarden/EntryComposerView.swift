import SwiftUI

/// The daily entry composer: choose one or more kinds, write something for each, save.
///
/// The three kinds are equal, deliberately. Nothing here pressures the user toward "gratitude" on a
/// hard day — "Got through" and "Looking forward to" are first-class, so a bad day never demands a
/// feeling they don't have. Each kind keeps its **own** text, so switching segments never overwrites
/// what you typed; Save logs every non-empty draft as a separate entry.
struct EntryComposerView: View {
    /// Called with every non-empty draft when the user taps Save. The parent persists each and
    /// dismisses on success.
    let onSave: ([(kind: EntryKind, text: String)]) -> Void

    @State private var kind: EntryKind = .gratitude
    /// Independent text per kind — keyed so the three segments never share a value.
    @State private var texts: [EntryKind: String] = [:]
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    private func text(for kind: EntryKind) -> String { texts[kind] ?? "" }

    private var drafts: [(kind: EntryKind, text: String)] {
        EntryKind.allCases.compactMap { kind in
            let trimmed = text(for: kind).trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : (kind, trimmed)
        }
    }

    private var canSave: Bool { !drafts.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $kind) {
                        ForEach(EntryKind.allCases) { kind in
                            Text(GardenCopy.kindLabel(kind)).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Text(GardenCopy.prompt(kind))
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .listRowBackground(Color.clear)

                    TextField("Take your time…",
                              text: Binding(get: { text(for: kind) },
                                            set: { texts[kind] = $0 }),
                              axis: .vertical)
                        .lineLimit(4...10)
                        .focused($isFocused)
                }
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(drafts) }
                        .disabled(!canSave)
                }
            }
            .onAppear { isFocused = true }
        }
    }
}

#Preview {
    EntryComposerView { _ in }
}
