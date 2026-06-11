import SwiftUI

/// Plain-language privacy statement. Gratitude Garden is fully local — this screen simply tells the
/// truth about that.
struct PrivacyView: View {
    var body: some View {
        List {
            Section {
                Text("Gratitude Garden keeps everything on your device. Your entries are yours alone.")
                    .font(.subheadline)
            }
            Section("What this means") {
                label("No account", "You don't sign in. There's nothing to sign in to.")
                label("No backend", "Your entries are never uploaded. They live in the app's private storage on this device.")
                label("No tracking", "There is no analytics, no advertising, and no third-party SDKs watching what you do.")
                label("You're in control", "Export your journal whenever you like, or reset the garden to start fresh — both from Settings.")
            }
            Section {
                Text("Because everything is local, deleting the app removes your entries from this device. Export first if you'd like to keep them.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func label(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(body).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack { PrivacyView() }
}
