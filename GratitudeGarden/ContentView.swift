import SwiftUI

/// Home = the living world, full-bleed, with minimal glass controls floating above it. The garden is
/// the experience; the interface is secondary. "I am visiting my world," not "I'm opening an app."
struct ContentView: View {
    @State private var viewModel = GardenViewModel()
    @State private var showingJournal = false
    @State private var showingSettings = false

    @Environment(AppRouter.self) private var router
    @Environment(NotificationManager.self) private var notifications
    @Environment(AppPreferencesModel.self) private var preferences
    @Environment(\.scenePhase) private var scenePhase

    private let haptics: HapticsPlaying = SystemHaptics()
    private let sound: SoundPlaying = SystemSoundPlayer()

    private var snapshot: GardenSnapshot { viewModel.snapshot }

    var body: some View {
        @Bindable var router = router

        return ZStack {
            // The world — edge to edge, behind everything, explorable.
            GardenSceneView(snapshot: snapshot, homeStyle: preferences.homeStyle)
                .ignoresSafeArea()

            // Gentle scrims top & bottom so glass controls and text stay legible over bright meadows.
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.20), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 140)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.28)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 240)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Floating glass interface (stays within the safe area).
            VStack(spacing: 10) {
                HStack {
                    glassPill("Journal") { showingJournal = true }
                    Spacer()
                    glassPill("Settings") { showingSettings = true }
                }
                Spacer()
                statusPanel
                tendButton
            }
            .padding(.horizontal)
            .padding(.bottom, 6)
        }
        .sheet(isPresented: $router.isComposing) {
            EntryComposerView { drafts in
                var lastOutcome: EntrySaveOutcome?
                for draft in drafts {
                    if let outcome = viewModel.save(text: draft.text, kind: draft.kind) { lastOutcome = outcome }
                }
                if let outcome = lastOutcome {
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
            NavigationStack { SettingsView(entries: viewModel.entries) { viewModel.resetGarden() } }
        }
        .fullScreenCover(
            isPresented: Binding(get: { !preferences.hasCompletedOnboarding }, set: { _ in }),
            onDismiss: { router.requestCompose() }
        ) {
            OnboardingView { home in
                preferences.setHomeStyle(home)
                preferences.completeOnboarding()
            }
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

    // MARK: Floating glass controls

    private func glassPill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
        }
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }

    private var statusPanel: some View {
        VStack(spacing: 3) {
            Text(GardenCopy.vitalityTitle(snapshot.vitality, isReviving: viewModel.showWelcomeBack))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text("\(GardenCopy.growthTitle(snapshot.growthStage)) · \(snapshot.totalEntries) "
                 + (snapshot.totalEntries == 1 ? "day" : "days"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .animation(.easeInOut, value: viewModel.showWelcomeBack)
        .accessibilityElement(children: .combine)
    }

    private var tendButton: some View {
        Button { router.requestCompose() } label: {
            Text("Tend your garden")
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
        }
        .background {
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(Color.green.opacity(0.18))
            }
        }
        .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
        .padding(.top, 4)
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
}

#Preview {
    ContentView()
        .environment(AppRouter())
        .environment(NotificationManager())
        .environment(AppPreferencesModel())
}
