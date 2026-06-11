import Foundation

/// Persists the user's reminder preferences. Separate from `GardenStore` so concerns stay clean.
/// Reuses the shared-container locator so it's testable against a temp directory.
protocol NotificationSettingsStore {
    func load() -> NotificationSettings
    func save(_ settings: NotificationSettings) throws
}

final class FileNotificationSettingsStore: NotificationSettingsStore {
    private let locator: SharedContainerLocating
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let filename = "NotificationSettings.json"

    init(locator: SharedContainerLocating = AppGroupContainerLocator()) {
        self.locator = locator
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> NotificationSettings {
        guard let url = try? locator.containerURL().appendingPathComponent(filename),
              let data = try? Data(contentsOf: url),
              let settings = try? decoder.decode(NotificationSettings.self, from: data)
        else { return .default }
        return settings
    }

    func save(_ settings: NotificationSettings) throws {
        let url = try locator.containerURL().appendingPathComponent(filename)
        try encoder.encode(settings).write(to: url, options: [.atomic])
    }
}
