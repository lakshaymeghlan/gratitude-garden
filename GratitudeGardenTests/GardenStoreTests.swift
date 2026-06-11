import XCTest
@testable import GratitudeGarden

/// Tests for the shared persistence layer. They run against a real `FileGardenStore` pointed at a
/// throwaway temp directory, so they exercise the actual JSON read/write path without needing the
/// App Group entitlement or a simulator.
final class GardenStoreTests: XCTestCase {
    private var tempDir: URL!
    private var locator: SharedContainerLocating!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        locator = FixedURLLocator(url: tempDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testLoadReturnsDefaultsWhenNothingSaved() {
        let store = FileGardenStore(locator: locator)
        XCTAssertEqual(store.loadGarden(), .empty)
        XCTAssertTrue(store.loadEntries().isEmpty)
    }

    func testGardenRoundTrips() throws {
        let store = FileGardenStore(locator: locator)
        var state = GardenState.empty
        state.totalEntries = 7
        state.consecutiveDayCount = 3
        state.growthStage = .seedling
        state.lastEntryWasRevival = true
        state.lastEntryDate = Date(timeIntervalSince1970: 1_700_000_000)
        try store.save(state)
        XCTAssertEqual(store.loadGarden(), state)
    }

    func testEntriesRoundTrip() throws {
        let store = FileGardenStore(locator: locator)
        let entries = [
            Entry(date: Date(timeIntervalSince1970: 1_700_000_000), text: "the sun", kind: .gratitude),
            Entry(date: Date(timeIntervalSince1970: 1_700_100_000), text: "got out of bed", kind: .gotThrough),
        ]
        try store.save(entries)
        XCTAssertEqual(store.loadEntries(), entries)
    }

    /// A separate store instance over the same container stands in for the widget process.
    func testAppWriteIsVisibleToWidgetReader() throws {
        let appStore = FileGardenStore(locator: locator)
        var state = GardenState.empty
        state.growthStage = .blooming
        try appStore.save(state)
        try appStore.save([Entry(date: Date(), text: "hi", kind: .lookingForwardTo)])

        let widgetStore = FileGardenStore(locator: locator)
        XCTAssertEqual(widgetStore.loadGarden().growthStage, .blooming)
        XCTAssertEqual(widgetStore.loadEntries().count, 1)
    }

    func testUnreachableContainerDegradesGracefully() {
        let store = FileGardenStore(locator: FailingLocator())
        XCTAssertEqual(store.loadGarden(), .empty)
        XCTAssertTrue(store.loadEntries().isEmpty)
        XCTAssertNil(store.sharedStoragePath())
        XCTAssertThrowsError(try store.save(GardenState.empty))
    }

    // MARK: Migration / resilient decoding

    func testLegacyGardenStateWithoutNewFieldsStillDecodes() throws {
        // Phase 1-shaped JSON: no `lastEntryWasRevival`, no `lastEntryDate`.
        let legacy = #"{ "consecutiveDayCount": 2, "growthStage": 1, "totalEntries": 3 }"#
        try legacy.data(using: .utf8)!.write(to: tempDir.appendingPathComponent("GardenState.json"))

        let state = FileGardenStore(locator: locator).loadGarden()
        XCTAssertEqual(state.totalEntries, 3)
        XCTAssertEqual(state.growthStage, .sprout)
        XCTAssertFalse(state.lastEntryWasRevival, "Missing field should default, not crash")
        XCTAssertNil(state.lastEntryDate)
    }

    func testLegacySoftEntryKindMigratesToGotThrough() throws {
        let legacy = #"[{ "id": "00000000-0000-0000-0000-000000000001", "date": "2026-01-01T12:00:00Z", "kind": "soft", "text": "made it through" }]"#
        try legacy.data(using: .utf8)!.write(to: tempDir.appendingPathComponent("Entries.json"))

        let entries = FileGardenStore(locator: locator).loadEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.kind, .gotThrough, "Legacy 'soft' should migrate to .gotThrough")
    }
}

// MARK: - Test doubles

struct FixedURLLocator: SharedContainerLocating {
    let url: URL
    func containerURL() throws -> URL { url }
}

struct FailingLocator: SharedContainerLocating {
    func containerURL() throws -> URL {
        throw SharedContainerError.appGroupUnavailable(identifier: "test.failing")
    }
}

final class WidgetReloadingSpy: WidgetReloading {
    private(set) var reloadCount = 0
    func reloadGardenWidget() { reloadCount += 1 }
}
