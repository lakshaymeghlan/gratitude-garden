import Foundation

/// User-facing app preferences (distinct from notification settings). Resilient decoding so adding
/// fields never breaks saved data.
struct AppPreferences: Codable, Equatable {
    var hasCompletedOnboarding: Bool
    /// Sound is **off by default** and fully user-controllable (per product requirement).
    var soundEnabled: Bool
    /// Subtle haptics on by default; can be turned off.
    var hapticsEnabled: Bool

    init(hasCompletedOnboarding: Bool, soundEnabled: Bool, hapticsEnabled: Bool) {
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.soundEnabled = soundEnabled
        self.hapticsEnabled = hapticsEnabled
    }

    static let `default` = AppPreferences(hasCompletedOnboarding: false, soundEnabled: false, hapticsEnabled: true)

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        soundEnabled           = try c.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? false
        hapticsEnabled         = try c.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? true
    }
}

protocol AppPreferencesStore {
    func load() -> AppPreferences
    func save(_ preferences: AppPreferences) throws
}

final class FileAppPreferencesStore: AppPreferencesStore {
    private let locator: SharedContainerLocating
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let filename = "AppPreferences.json"

    init(locator: SharedContainerLocating = AppGroupContainerLocator()) {
        self.locator = locator
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> AppPreferences {
        guard let url = try? locator.containerURL().appendingPathComponent(filename),
              let data = try? Data(contentsOf: url),
              let prefs = try? decoder.decode(AppPreferences.self, from: data)
        else { return .default }
        return prefs
    }

    func save(_ preferences: AppPreferences) throws {
        let url = try locator.containerURL().appendingPathComponent(filename)
        try encoder.encode(preferences).write(to: url, options: [.atomic])
    }
}
