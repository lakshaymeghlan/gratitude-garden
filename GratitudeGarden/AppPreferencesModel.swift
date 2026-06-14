import Foundation
import Observation

/// Observable wrapper around `AppPreferences` persistence, injected via the environment so any view
/// can read/toggle sound, haptics, and onboarding completion.
@MainActor
@Observable
final class AppPreferencesModel {
    private let store: AppPreferencesStore
    private(set) var preferences: AppPreferences

    init(store: AppPreferencesStore = FileAppPreferencesStore()) {
        self.store = store
        self.preferences = store.load()
    }

    var hasCompletedOnboarding: Bool { preferences.hasCompletedOnboarding }
    var soundEnabled: Bool { preferences.soundEnabled }
    var hapticsEnabled: Bool { preferences.hapticsEnabled }
    var homeStyle: HomeStyle { preferences.homeStyle }
    var petType: PetType { preferences.petType }

    func completeOnboarding() { mutate { $0.hasCompletedOnboarding = true } }
    func setSoundEnabled(_ on: Bool) { mutate { $0.soundEnabled = on } }
    func setHapticsEnabled(_ on: Bool) { mutate { $0.hapticsEnabled = on } }
    func setHomeStyle(_ style: HomeStyle) { mutate { $0.homeStyle = style } }
    func setPetType(_ type: PetType) { mutate { $0.petType = type } }

    private func mutate(_ change: (inout AppPreferences) -> Void) {
        change(&preferences)
        try? store.save(preferences)
    }
}
