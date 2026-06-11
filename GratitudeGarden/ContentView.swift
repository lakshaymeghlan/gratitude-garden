import SwiftUI

/// Garden home screen. The garden itself is the real pixel-art `GardenSceneView`; everything else is
/// warm text. No SF Symbols, no emoji — the scene carries all the visual weight.
struct ContentView: View {
    @State private var viewModel: GardenViewModel
    @State private var showingReminders = false
    @Environment(AppRouter.self) private var router
    @Environment(NotificationManager.self) private var notifications
    @Environment(\.scenePhase) private var scenePhase

    init(viewModel: GardenViewModel = GardenViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    private var snapshot: GardenSnapshot { viewModel.snapshot }

    var body: some View {
        @Bindable var router = router
        return NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    GardenSceneView(snapshot: snapshot)
                        .aspectRatio(1.1, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22)
                                .strokeBorder(.black.opacity(0.06), lineWidth: 1))

                    stateText
                    statsRow
                    recentEntries
                }
                .padding()
            }
            .navigationTitle("Gratitude Garden")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reminders") { showingReminders = true }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add") { router.requestCompose() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    router.requestCompose()
                } label: {
                    Text("Tend your garden")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
            .sheet(isPresented: $router.isComposing) {
                EntryComposerView { text, kind in
                    if viewModel.save(text: text, kind: kind) {
                        router.isComposing = false
                        // State changed → reschedule (today is now tended, so we won't ping today).
                        Task { await notifications.refreshSchedule() }
                    }
                }
            }
            .sheet(isPresented: $showingReminders) {
                NavigationStack { NotificationSettingsView() }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    viewModel.refresh()
                    Task { await notifications.onForeground() }
                }
            }
        }
    }

    // MARK: Sections

    private var stateText: some View {
        VStack(spacing: 4) {
            Text(GardenCopy.vitalityTitle(snapshot.vitality, isReviving: viewModel.showWelcomeBack))
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(GardenCopy.vitalitySubtitle(snapshot.vitality, isReviving: viewModel.showWelcomeBack))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut, value: viewModel.showWelcomeBack)
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            statChip(value: GardenCopy.growthTitle(snapshot.growthStage), label: "Growth")
            statChip(value: lastEntryText, label: "Last entry")
            statChip(value: "\(snapshot.totalEntries)",
                     label: snapshot.totalEntries == 1 ? "Day tended" : "Days tended")
        }
    }

    private func statChip(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 14))
    }

    private var recentEntries: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            if viewModel.entries.isEmpty {
                Text(GardenCopy.emptyJournalPrompt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(viewModel.entries.prefix(5)) { entry in
                    entryRow(entry)
                }
            }
        }
    }

    private func entryRow(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(GardenCopy.kindLabel(entry.kind))
                .font(.caption).foregroundStyle(.secondary)
            Text(entry.text).font(.body)
            Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var lastEntryText: String {
        guard let date = snapshot.lastEntryDate else { return "—" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

#Preview {
    ContentView()
        .environment(AppRouter())
        .environment(NotificationManager())
}
