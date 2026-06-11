import SwiftUI

/// The settings hub: reminders, sound, haptics, accessibility notes, privacy, version, export, and
/// reset (behind a confirmation). Reset and export are passed in as the garden's owner handles them.
struct SettingsView: View {
    let entries: [Entry]
    let onReset: () -> Void

    @Environment(AppPreferencesModel.self) private var preferences
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingReset = false

    var body: some View {
        @Bindable var prefs = preferences

        Form {
            Section("Reminders") {
                NavigationLink("Daily reminder") { NotificationSettingsView() }
            }

            Section {
                Toggle("Sound", isOn: Binding(
                    get: { preferences.soundEnabled },
                    set: { preferences.setSoundEnabled($0) }))
                Toggle("Haptics", isOn: Binding(
                    get: { preferences.hapticsEnabled },
                    set: { preferences.setHapticsEnabled($0) }))
            } header: {
                Text("Feedback")
            } footer: {
                Text("Sound is off by default and stays gentle. Haptics are subtle — only at meaningful moments.")
            }

            Section("Accessibility") {
                Text("The garden fully supports VoiceOver, Dynamic Type, and Reduced Motion. "
                     + "When Reduced Motion is on, the garden holds a calm, still frame.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Your data") {
                ShareLink(item: JournalExport.plainText(entries)) {
                    Text("Export journal")
                }
                .disabled(entries.isEmpty)

                NavigationLink("Privacy") { PrivacyView() }

                Button("Reset garden", role: .destructive) { confirmingReset = true }
            }

            Section {
                LabeledContent("Version", value: appVersion)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .alert("Reset garden?", isPresented: $confirmingReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { onReset() }
        } message: {
            Text("This clears your garden and every journal entry on this device. This can't be undone — "
                 + "you may want to export your journal first.")
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

#Preview {
    NavigationStack {
        SettingsView(entries: [], onReset: {})
            .environment(AppPreferencesModel())
            .environment(NotificationManager())
    }
}
