import XCTest
@testable import GratitudeGarden

/// Tests for the end-to-end daily loop: logging through `GardenJournal`, the resulting
/// `GardenState` transitions via the rules engine, revival, and relaunch persistence.
/// All time is injected via a fixed UTC calendar + explicit dates, so nothing depends on the clock.
final class GardenJournalTests: XCTestCase {
    private var tempDir: URL!
    private var store: FileGardenStore!
    private var journal: GardenJournal!

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = FileGardenStore(locator: FixedURLLocator(url: tempDir))
        journal = GardenJournal(store: store, calendar: cal)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: Saving entries

    func testSavingEntryPersistsItAndAdvancesGarden() throws {
        let result = try journal.log(text: "  the morning light  ", kind: .gratitude, on: day(2026, 6, 1))

        XCTAssertEqual(journal.allEntries().count, 1)
        XCTAssertEqual(journal.allEntries().first?.text, "the morning light", "Text should be trimmed")
        XCTAssertEqual(result.garden.totalEntries, 1)
        XCTAssertEqual(result.garden.consecutiveDayCount, 1)
        XCTAssertEqual(result.garden.growthStage, .sprout)
        XCTAssertFalse(result.didRevive, "First-ever entry is not a revival")
    }

    func testEntriesReturnedNewestFirst() throws {
        try journal.log(text: "older", kind: .gratitude, on: day(2026, 6, 1))
        try journal.log(text: "newer", kind: .gotThrough, on: day(2026, 6, 2))
        XCTAssertEqual(journal.allEntries().map(\.text), ["newer", "older"])
    }

    // MARK: Consecutive logging

    func testConsecutiveLoggingGrowsStreak() throws {
        try journal.log(text: "a", kind: .gratitude, on: day(2026, 6, 1))
        try journal.log(text: "b", kind: .gratitude, on: day(2026, 6, 2))
        let r = try journal.log(text: "c", kind: .gratitude, on: day(2026, 6, 3))
        XCTAssertEqual(r.garden.consecutiveDayCount, 3)
        XCTAssertEqual(r.garden.totalEntries, 3)
    }

    func testSecondEntrySameDayDoesNotInflateGrowthButIsJournaled() throws {
        try journal.log(text: "morning", kind: .gratitude, on: day(2026, 6, 1, 9))
        let r = try journal.log(text: "evening", kind: .lookingForwardTo, on: day(2026, 6, 1, 21))
        XCTAssertEqual(r.garden.totalEntries, 1, "Growth counts distinct days, not raw entries")
        XCTAssertEqual(journal.allEntries().count, 2, "But both entries are kept in the journal")
    }

    // MARK: Missing days (forgiving thresholds, via the snapshot the UI reads)

    func testMissingOneDayStaysThriving() throws {
        try journal.log(text: "a", kind: .gratitude, on: day(2026, 6, 1))
        // 1 missed day (logged 6/1, now 6/3).
        XCTAssertEqual(journal.snapshot(now: day(2026, 6, 3)).vitality, .thriving)
    }

    func testMissingTwoDaysStaysThriving() throws {
        try journal.log(text: "a", kind: .gratitude, on: day(2026, 6, 1))
        // 2 missed days.
        XCTAssertEqual(journal.snapshot(now: day(2026, 6, 4)).vitality, .thriving)
    }

    func testMissingThreeDaysBeginsToDroop() throws {
        try journal.log(text: "a", kind: .gratitude, on: day(2026, 6, 1))
        // 3 missed days → gentle droop begins.
        let snap = journal.snapshot(now: day(2026, 6, 5))
        XCTAssertEqual(snap.vitality, .drooping)
        XCTAssertEqual(snap.wiltLevel, 1)
    }

    func testDormancyAfterLongAbsence() throws {
        try journal.log(text: "a", kind: .gratitude, on: day(2026, 6, 1))
        XCTAssertEqual(journal.snapshot(now: day(2026, 6, 30)).vitality, .dormant)
    }

    // MARK: Revival

    func testReturningAfterDormancyRevivesAndFlagsWelcomeBack() throws {
        try journal.log(text: "first", kind: .gratitude, on: day(2026, 1, 1))
        // Long gap → dormant by June. Returning revives.
        let r = try journal.log(text: "i'm back", kind: .gotThrough, on: day(2026, 6, 1))
        XCTAssertTrue(r.didRevive)
        XCTAssertTrue(r.garden.lastEntryWasRevival, "Revival must persist on the state")

        // Snapshot on the day of return surfaces the welcome-back moment...
        XCTAssertTrue(journal.snapshot(now: day(2026, 6, 1)).isReviving)
        XCTAssertEqual(journal.snapshot(now: day(2026, 6, 1)).vitality, .thriving, "And the garden is healthy again")
        // ...but not on later days.
        XCTAssertFalse(journal.snapshot(now: day(2026, 6, 2)).isReviving)
    }

    func testLoggingWhileThrivingIsNotARevival() throws {
        try journal.log(text: "a", kind: .gratitude, on: day(2026, 6, 1))
        let r = try journal.log(text: "b", kind: .gratitude, on: day(2026, 6, 2))
        XCTAssertFalse(r.didRevive)
        XCTAssertFalse(r.garden.lastEntryWasRevival)
    }

    func testGrowthNeverDropsAcrossAGap() throws {
        // Build up growth, then take a long break and return.
        for d in 1...8 { try journal.log(text: "day \(d)", kind: .gratitude, on: day(2026, 6, d)) }
        let beforeGap = journal.currentGarden().growthStage
        XCTAssertEqual(beforeGap, .budding)

        let r = try journal.log(text: "returned", kind: .gotThrough, on: day(2026, 8, 1))
        XCTAssertGreaterThanOrEqual(r.garden.growthStage, beforeGap, "Growth must never regress after a gap")
        XCTAssertEqual(r.garden.consecutiveDayCount, 1, "Streak gently restarts")
    }

    // MARK: Relaunch persistence

    func testStatePersistsAcrossRelaunch() throws {
        try journal.log(text: "a", kind: .gratitude, on: day(2026, 6, 1))
        try journal.log(text: "b", kind: .gratitude, on: day(2026, 6, 2))

        // Simulate relaunch: brand-new store + journal over the same container.
        let freshStore = FileGardenStore(locator: FixedURLLocator(url: tempDir))
        let freshJournal = GardenJournal(store: freshStore, calendar: cal)

        XCTAssertEqual(freshJournal.currentGarden().totalEntries, 2)
        XCTAssertEqual(freshJournal.currentGarden().consecutiveDayCount, 2)
        XCTAssertEqual(freshJournal.allEntries().count, 2)
    }
}

/// Verifies the view model routes saves through the journal AND reloads the widget.
@MainActor
final class GardenViewModelTests: XCTestCase {
    func testSaveUpdatesSnapshotAndTriggersWidgetReload() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = FileGardenStore(locator: FixedURLLocator(url: dir))
        let journal = GardenJournal(store: store)
        let spy = WidgetReloadingSpy()
        let vm = GardenViewModel(journal: journal, widgetReloader: spy, now: { Date() })

        XCTAssertEqual(vm.snapshot.totalEntries, 0)

        let outcome = vm.save(text: "the rain", kind: .gratitude)

        XCTAssertNotNil(outcome, "A successful save returns an outcome")
        XCTAssertEqual(vm.snapshot.totalEntries, 1, "Snapshot should reflect the new entry")
        XCTAssertEqual(vm.entries.count, 1)
        XCTAssertEqual(spy.reloadCount, 1, "A successful save must reload the widget exactly once")
    }

    func testEmptyTextIsRejectedAndDoesNotReload() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let vm = GardenViewModel(journal: GardenJournal(store: FileGardenStore(locator: FixedURLLocator(url: dir))),
                                 widgetReloader: WidgetReloadingSpy(),
                                 now: { Date() })
        XCTAssertNil(vm.save(text: "   ", kind: .gratitude))
        XCTAssertEqual(vm.entries.count, 0)
    }
}
