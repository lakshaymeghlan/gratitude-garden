import SwiftUI

/// The daily entry composer: pick a kind, write something, save.
///
/// The three kinds are equal, deliberately. Nothing here pressures the user toward "gratitude" on a
/// hard day — "Got through" and "Looking forward to" are first-class, so a bad day never demands a
/// feeling they don't have. The prompt updates to match the chosen kind.
struct EntryComposerView: View {
    /// Called with the trimmed text + kind when the user taps Save. The parent persists and
    /// dismisses on success.
    let onSave: (String, EntryKind) -> Void

    @State private var kind: EntryKind = .gratitude
    @State private var text: String = ""
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

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

                    TextField("Take your time…", text: $text, axis: .vertical)
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
                    Button("Save") { onSave(text, kind) }
                        .disabled(!canSave)
                }
            }
            .onAppear { isFocused = true }
        }
    }
}

#Preview {
    EntryComposerView { _, _ in }
}
