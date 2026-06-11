import Foundation

/// The shared persistence layer. Both the app and the widget read/write through this interface,
/// so there is exactly one source of truth living in the App Group container.
///
/// It is a protocol so callers depend on the abstraction: the app and widget get `FileGardenStore`,
/// tests get the same `FileGardenStore` aimed at a temp directory, and a future phase could swap
/// the backing store (e.g. SQLite for a large journal) without touching any call site.
///
/// Garden and entries are stored in **separate files** on purpose: the widget only needs the small
/// `GardenState`, so it never has to load (and decode) the whole journal.
protocol GardenStore {
    /// Loads the persisted garden, or `.empty` if nothing has been saved yet (a fresh seed).
    func loadGarden() -> GardenState
    /// Persists the garden atomically to the shared container.
    func save(_ garden: GardenState) throws

    /// Loads all journal entries, or `[]` if none have been saved.
    func loadEntries() -> [Entry]
    /// Persists the journal atomically to the shared container.
    func save(_ entries: [Entry]) throws

    /// Human-readable path of the shared container, or `nil` if it can't be reached. Used only to
    /// surface a diagnostic in the UI so you can confirm the bridge is live.
    func sharedStoragePath() -> String?
}

/// File-backed implementation: stores each value as a JSON file inside the App Group container.
///
/// Chosen over `UserDefaults(suiteName:)` because it scales cleanly to the growing entries journal,
/// writes atomically, and is decoupled from UserDefaults' cross-process caching quirks. Reads are
/// tolerant: a missing or unreadable file yields the default value rather than throwing, so the app
/// and widget never crash on first launch.
final class FileGardenStore: GardenStore {
    private let locator: SharedContainerLocating
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private let gardenFilename = "GardenState.json"
    private let entriesFilename = "Entries.json"

    init(locator: SharedContainerLocating = AppGroupContainerLocator()) {
        self.locator = locator

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601          // explicit + stable across OS versions
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    // MARK: Garden

    func loadGarden() -> GardenState {
        readValue(GardenState.self, from: gardenFilename) ?? .empty
    }

    func save(_ garden: GardenState) throws {
        try write(garden, to: gardenFilename)
    }

    // MARK: Entries (journal)

    func loadEntries() -> [Entry] {
        readValue([Entry].self, from: entriesFilename) ?? []
    }

    func save(_ entries: [Entry]) throws {
        try write(entries, to: entriesFilename)
    }

    func sharedStoragePath() -> String? {
        (try? locator.containerURL())?.path
    }

    // MARK: File IO

    private func fileURL(_ name: String) throws -> URL {
        try locator.containerURL().appendingPathComponent(name, isDirectory: false)
    }

    /// Reads a value, tolerating a **missing** file (returns nil → caller uses a safe default) and
    /// **quarantining a corrupt** one (moves it aside so we never get stuck failing on the same bad
    /// bytes, and the data is preserved for possible manual recovery). Higher layers can then rebuild
    /// from the journal, so a corrupt file never costs the user their progress.
    private func readValue<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let url = try? fileURL(name), let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            quarantineCorruptFile(at: url)
            return nil
        }
    }

    private func quarantineCorruptFile(at url: URL) {
        let quarantined = url.appendingPathExtension("corrupt")
        try? FileManager.default.removeItem(at: quarantined)
        try? FileManager.default.moveItem(at: url, to: quarantined)
    }

    private func write<T: Encodable>(_ value: T, to name: String) throws {
        let data = try encoder.encode(value)
        try data.write(to: try fileURL(name), options: [.atomic])
    }
}
