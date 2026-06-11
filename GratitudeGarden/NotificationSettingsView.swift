import SwiftUI
import UIKit

/// The reminders settings screen. All behavior delegates to `NotificationManager`; this view only
/// presents state and forwards intents. Tone here is part of the product — reminders are framed as
/// optional and kind, never as an obligation.
struct NotificationSettingsView: View {
    @Environment(NotificationManager.self) private var manager
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                Toggle("Daily reminder", isOn: Binding(
                    get: { manager.settings.isEnabled },
                    set: { newValue in Task { await manager.setEnabled(newValue) } }))
            } footer: {
                Text("Optional and gentle. Turn it off anytime — your garden never minds.")
            }

            if manager.settings.isEnabled {
                Section("Reminder time") {
                    DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                }

                if manager.authorizationStatus.allowsScheduling, let next = manager.nextReminder {
                    Section("Next reminder") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(next.date.formatted(date: .complete, time: .shortened))
                                .font(.subheadline)
                            Text("“\(next.title) — \(next.body)”")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if manager.authorizationStatus == .denied {
                Section {
                    Text("Notifications are turned off in iOS Settings, so reminders can't be sent yet.")
                        .font(.subheadline)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                } header: {
                    Text("Permission")
                }
            }
        }
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .task { await manager.onForeground() }
    }

    /// Bridges the stored hour/minute to a `Date` the picker can edit (date part is irrelevant).
    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                var comps = DateComponents()
                comps.hour = manager.settings.hour
                comps.minute = manager.settings.minute
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                Task { await manager.setReminderTime(hour: comps.hour ?? 20, minute: comps.minute ?? 0) }
            })
    }
}
