import XCTest
@testable import GratitudeGarden

/// Edge-case hardening: the user must never be unfairly penalized by a technical issue.
final class EdgeCaseTests: XCTestCase {

    private func calendar(_ tz: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: tz)!
        return c
    }

    private func day(_ cal: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func testDeviceClockMovedBackwardsDoesNotPenalize() {
        let cal = calendar("UTC")
        let app = GardenRules.appearance(lastEntryDate: day(cal, 2026, 6, 11),
                                         now: day(cal, 2026, 6, 8), calendar: cal)
        XCTAssertEqual(app.vitality, .thriving)
        XCTAssertEqual(app.wiltLevel, 0)
    }

    func testDaylightSavingTransitionDoesNotMiscountDays() {
        // US DST began 2026-03-08. Logging the day before and checking the day after must read as
        // exactly one calendar day apart (no off-by-one penalty from the 23-hour day).
        let cal = calendar("America/New_York")
        let days = GardenRules.daysBetween(day(cal, 2026, 3, 7), day(cal, 2026, 3, 9), calendar: cal)
        XCTAssertEqual(days, 2)
        // Two days later is still inside the grace window → thriving.
        XCTAssertEqual(GardenRules.appearance(lastEntryDate: day(cal, 2026, 3, 7),
                                              now: day(cal, 2026, 3, 9), calendar: cal).vitality, .thriving)
    }

    func testTimeZoneTravelStaysWithinGrace() {
        // Log at noon UTC, then evaluate "now" a day later in a far-west zone. Should still be within
        // grace, never an extra penalized day.
        let utc = calendar("UTC")
        let last = day(utc, 2026, 6, 11)
        let honolulu = calendar("Pacific/Honolulu")
        let now = day(honolulu, 2026, 6, 12, 8)
        let app = GardenRules.appearance(lastEntryDate: last, now: now, calendar: honolulu)
        XCTAssertEqual(app.vitality, .thriving)
    }

    func testReinstallStartsFreshWithoutCrashing() throws {
        // A fresh container (as after a reinstall) just reads as an empty seed — no crash, no penalty.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileGardenStore(locator: FixedURLLocator(url: dir))
        XCTAssertEqual(store.loadGarden(), .empty)
        XCTAssertTrue(store.loadEntries().isEmpty)
    }
}

/// Corrupt-storage recovery: progress is never lost to a bad file.
final class StorageRecoveryTests: XCTestCase {

    private func freshDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testCorruptGardenFileIsQuarantinedAndReadsDefault() throws {
        let dir = try freshDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let gardenURL = dir.appendingPathComponent("GardenState.json")
        try Data("{ this is not json ".utf8).write(to: gardenURL)

        let store = FileGardenStore(locator: FixedURLLocator(url: dir))
        XCTAssertEqual(store.loadGarden(), .empty, "Corrupt file must not crash; reads default")
        XCTAssertFalse(FileManager.default.fileExists(atPath: gardenURL.path), "Corrupt file moved aside")
        XCTAssertTrue(FileManager.default.fileExists(atPath: gardenURL.appendingPathExtension("corrupt").path))
    }

    func testJournalRebuildsLostGardenFromEntries() throws {
        let cal = Calendar(identifier: .gregorian)
        let dir = try freshDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileGardenStore(locator: FixedURLLocator(url: dir))

        // Save entries across several distinct days, but leave the garden file "lost" (empty).
        let base = cal.startOfDay(for: Date())
        let entries = (0..<5).map { i in
            Entry(date: cal.date(byAdding: .day, value: -i, to: base)!, text: "day \(i)", kind: .gratitude)
        }
        try store.save(entries)
        XCTAssertEqual(store.loadGarden(), .empty, "Garden state is lost…")

        let journal = GardenJournal(store: store)
        XCTAssertTrue(journal.repair(), "…so repair should rebuild it")
        let rebuilt = store.loadGarden()
        XCTAssertEqual(rebuilt.totalEntries, 5, "Growth reconstructed from the journal — progress not lost")
        XCTAssertGreaterThan(rebuilt.growthStage, .seed)
    }

    func testRebuildFromEntriesIsOrderIndependentForGrowth() {
        let cal = Calendar(identifier: .gregorian)
        let base = cal.startOfDay(for: Date())
        let entries = (0..<4).map { i in
            Entry(date: cal.date(byAdding: .day, value: -i, to: base)!, text: "x", kind: .gratitude)
        }
        let a = GardenRules.rebuild(fromEntries: entries, calendar: cal)
        let b = GardenRules.rebuild(fromEntries: entries.reversed(), calendar: cal)
        XCTAssertEqual(a.totalEntries, b.totalEntries)
        XCTAssertEqual(a.growthStage, b.growthStage)
    }

    func testResetClearsEverything() throws {
        let dir = try freshDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileGardenStore(locator: FixedURLLocator(url: dir))
        try store.save([Entry(date: .now, text: "hi", kind: .gratitude)])
        var g = GardenState.empty; g.totalEntries = 3; try store.save(g)

        try GardenJournal(store: store).reset()
        XCTAssertEqual(store.loadGarden(), .empty)
        XCTAssertTrue(store.loadEntries().isEmpty)
    }
}

/// Journal history grouping/search + export.
final class JournalHistoryTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func testGroupsByDayNewestFirst() {
        let entries = [
            Entry(date: at(2026, 6, 10, 9), text: "a", kind: .gratitude),
            Entry(date: at(2026, 6, 11, 9), text: "b", kind: .gotThrough),
            Entry(date: at(2026, 6, 11, 20), text: "c", kind: .lookingForwardTo),
        ]
        let sections = JournalGrouping.sections(from: entries, calendar: cal)
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections.first?.entries.map(\.text), ["c", "b"], "Newest day first, newest entry first")
        XCTAssertEqual(sections.last?.entries.map(\.text), ["a"])
    }

    func testSearchFiltersCaseInsensitively() {
        let entries = [
            Entry(date: at(2026, 6, 11, 9), text: "The Sunrise", kind: .gratitude),
            Entry(date: at(2026, 6, 11, 10), text: "coffee", kind: .gratitude),
        ]
        let sections = JournalGrouping.sections(from: entries, query: "sun", calendar: cal)
        XCTAssertEqual(sections.flatMap { $0.entries }.map(\.text), ["The Sunrise"])
    }

    func testExportIncludesAllEntriesAndIsNonEmpty() {
        let entries = [Entry(date: at(2026, 6, 11, 9), text: "the rain", kind: .gratitude)]
        let text = JournalExport.plainText(entries, calendar: cal)
        XCTAssertTrue(text.contains("the rain"))
        XCTAssertTrue(text.contains("Grateful for"))
        XCTAssertFalse(JournalExport.plainText([], calendar: cal).isEmpty, "Empty export still produces friendly text")
    }
}

/// Accessibility & preferences logic.
final class Phase6SupportTests: XCTestCase {
    func testAccessibilityDescriptionDescribesState() {
        let desc = GardenCopy.accessibilityDescription(growth: .blooming, vitality: .drooping,
                                                       isReviving: false, lastEntry: nil)
        XCTAssertTrue(desc.contains("waiting for you"))
        XCTAssertTrue(desc.lowercased().contains("blooming"))
        XCTAssertTrue(desc.contains("Not tended yet"))
    }

    func testRevivalAccessibilityIsWarm() {
        let desc = GardenCopy.accessibilityDescription(growth: .blooming, vitality: .thriving,
                                                       isReviving: true, lastEntry: Date())
        XCTAssertTrue(desc.contains("Welcome back"))
    }

    func testPreferencesDefaultsAreForgiving() {
        XCTAssertFalse(AppPreferences.default.hasCompletedOnboarding)
        XCTAssertFalse(AppPreferences.default.soundEnabled, "Sound is off by default")
        XCTAssertTrue(AppPreferences.default.hapticsEnabled)
    }

    func testPreferencesRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileAppPreferencesStore(locator: FixedURLLocator(url: dir))
        var p = AppPreferences.default; p.soundEnabled = true; p.hasCompletedOnboarding = true
        try store.save(p)
        XCTAssertEqual(FileAppPreferencesStore(locator: FixedURLLocator(url: dir)).load(), p)
    }
}
