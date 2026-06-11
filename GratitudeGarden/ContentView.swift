import SwiftUI

/// Garden home screen. The pixel-art `GardenSceneView` is the hero; everything else is warm text.
struct ContentView: View {
    @State private var viewModel: GardenViewModel
    @State private var showingJournal = false
    @State private var showingSettings = false

    @Environment(AppRouter.self) private var router
    @Environment(NotificationManager.self) private var notifications
    @Environment(AppPreferencesModel.self) private var preferences
    @Environment(\.scenePhase) private var scenePhase

    private let haptics: HapticsPlaying = SystemHaptics()
    private let sound: SoundPlaying = SystemSoundPlayer()

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
                        .overlay(RoundedRectangle(cornerRadius: 22)
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
                    Button("Journal") { showingJournal = true }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Settings") { showingSettings = true }
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
                    if let outcome = viewModel.save(text: text, kind: kind) {
                        router.isComposing = false
                        playFeedback(for: outcome)
                        Task { await notifications.refreshSchedule() }
                    }
                }
            }
            .sheet(isPresented: $showingJournal) {
                NavigationStack { JournalView(entries: viewModel.entries) }
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    SettingsView(entries: viewModel.entries) { viewModel.resetGarden() }
                }
            }
            .fullScreenCover(
                isPresented: Binding(get: { !preferences.hasCompletedOnboarding }, set: { _ in }),
                onDismiss: { router.requestCompose() }   // lead straight into the first entry
            ) {
                OnboardingView { preferences.completeOnboarding() }
            }
            .task {
                viewModel.onAppear()
                await notifications.onForeground()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    viewModel.refresh()
                    Task { await notifications.onForeground() }
                }
            }
        }
    }

    // MARK: Feedback

    private func playFeedback(for outcome: EntrySaveOutcome) {
        if preferences.hapticsEnabled {
            if outcome.didRevive { haptics.revival() }
            else if outcome.reachedFirstBloom { haptics.firstBloom() }
            else { haptics.entrySaved() }
        }
        if preferences.soundEnabled {
            sound.play(outcome.didRevive ? .revival : .entry)
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
        .accessibilityElement(children: .combine)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private var recentEntries: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent").font(.headline)
                Spacer()
                if !viewModel.entries.isEmpty {
                    Button("See all") { showingJournal = true }
                        .font(.subheadline)
                }
            }

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
        .accessibilityElement(children: .combine)
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
        .environment(AppPreferencesModel())
}
