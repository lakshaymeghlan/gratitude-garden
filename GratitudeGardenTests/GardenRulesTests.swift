import XCTest
@testable import GratitudeGarden

/// Tests for the forgiving rules engine. These are the spec, expressed as code: if a change
/// ever makes the garden punish the user, one of these should go red.
final class GardenRulesTests: XCTestCase {

    // A fixed gregorian/UTC calendar so results never depend on the machine's locale/timezone.
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// A date at noon on the given day, to stay clear of day boundaries.
    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    // MARK: - Grace window: missing one or two days does nothing

    func testLoggedTodayIsThriving() {
        let app = GardenRules.appearance(lastEntryDate: day(2026, 6, 11),
                                         now: day(2026, 6, 11), calendar: cal)
        XCTAssertEqual(app.vitality, .thriving)
        XCTAssertEqual(app.wiltLevel, 0)
    }

    func testYesterdaysEntryIsThriving_todayStillOpen() {
        // Logged yesterday; today is still open → 0 missed days.
        let app = GardenRules.appearance(lastEntryDate: day(2026, 6, 10),
                                         now: day(2026, 6, 11), calendar: cal)
        XCTAssertEqual(app.vitality, .thriving)
    }

    func testMissingOneDayDoesNothing() {
        // Last entry Mon, now Wed → Tue was missed (1 missed day). Still thriving.
        let app = GardenRules.appearance(lastEntryDate: day(2026, 6, 8),
                                         now: day(2026, 6, 10), calendar: cal)
        XCTAssertEqual(app.vitality, .thriving)
        XCTAssertEqual(app.wiltLevel, 0)
    }

    func testMissingTwoDaysDoesNothing() {
        // 2 missed days → still fully thriving (this is the last "free" day).
        let app = GardenRules.appearance(lastEntryDate: day(2026, 6, 8),
                                         now: day(2026, 6, 11), calendar: cal)
        XCTAssertEqual(app.vitality, .thriving)
        XCTAssertEqual(app.wiltLevel, 0)
    }

    // MARK: - The 3rd missed day: gentle, gradual drooping

    func testThirdMissedDayBeginsToDroop() {
        // 3 missed days → drooping begins at the gentlest level.
        let app = GardenRules.appearance(lastEntryDate: day(2026, 6, 8),
                                         now: day(2026, 6, 12), calendar: cal)
        XCTAssertEqual(app.vitality, .drooping)
        XCTAssertEqual(app.wiltLevel, 1)
    }

    func testDroopDeepensGraduallyOneStepPerDay() {
        let last = day(2026, 6, 1)
        // 4 missed days → wilt 2, 5 → wilt 3 (still drooping, deepening slowly).
        XCTAssertEqual(GardenRules.appearance(lastEntryDate: last, now: day(2026, 6, 6), calendar: cal).wiltLevel, 2)
        XCTAssertEqual(GardenRules.appearance(lastEntryDate: last, now: day(2026, 6, 7), calendar: cal).wiltLevel, 3)
        XCTAssertEqual(GardenRules.appearance(lastEntryDate: last, now: day(2026, 6, 7), calendar: cal).vitality, .drooping)
    }

    // MARK: - Long absence: dormant, never dead

    func testLongAbsenceGoesDormantNotDead() {
        // Three weeks away. The garden rests — but there is no "dead" state to reach.
        let app = GardenRules.appearance(lastEntryDate: day(2026, 6, 1),
                                         now: day(2026, 6, 22), calendar: cal)
        XCTAssertEqual(app.vitality, .dormant)
        XCTAssertEqual(app.wiltLevel, GardenRules.maxWiltLevel)
    }

    func testDormancyDoesNotGetWorseOverTime() {
        // Dormant after a month should look exactly the same as dormant after a year — it never
        // degrades further, so the user is never confronted with an ever-worsening garden.
        let last = day(2026, 1, 1)
        let aMonth = GardenRules.appearance(lastEntryDate: last, now: day(2026, 2, 1), calendar: cal)
        let aYear  = GardenRules.appearance(lastEntryDate: last, now: day(2027, 1, 1), calendar: cal)
        XCTAssertEqual(aMonth, aYear)
    }

    // MARK: - Return & revive

    func testReturningAfterDroopRevivesAndBecomesThrivingAgain() {
        // Garden was drooping (5 days away), then the user logs an entry.
        var state = GardenState.empty
        state.lastEntryDate = day(2026, 6, 6)   // -> drooping by 2026-06-11
        state.totalEntries = 3
        state.growthStage = .sprout

        let result = GardenRules.applyingEntry(on: day(2026, 6, 11), to: state, calendar: cal)
        XCTAssertTrue(result.didRevive, "Returning after a droop should trigger a welcome-back moment")

        // And the garden is immediately healthy again.
        let after = GardenRules.appearance(lastEntryDate: result.state.lastEntryDate,
                                           now: day(2026, 6, 11), calendar: cal)
        XCTAssertEqual(after.vitality, .thriving)
    }

    func testReturningFromDormantRevives() {
        var state = GardenState.empty
        state.lastEntryDate = day(2026, 1, 1)   // dormant by June
        state.totalEntries = 10
        state.growthStage = .budding

        let result = GardenRules.applyingEntry(on: day(2026, 6, 11), to: state, calendar: cal)
        XCTAssertTrue(result.didRevive)
        // Growth survives the long absence completely intact.
        XCTAssertGreaterThanOrEqual(result.state.growthStage, .budding)
    }

    func testLoggingWhileAlreadyThrivingIsNotARevival() {
        var state = GardenState.empty
        state.lastEntryDate = day(2026, 6, 10)  // thriving
        let result = GardenRules.applyingEntry(on: day(2026, 6, 11), to: state, calendar: cal)
        XCTAssertFalse(result.didRevive)
    }

    // MARK: - Streaks & growth (progress is never lost)

    func testConsecutiveDayContinuesStreak() {
        var state = GardenState.empty
        state.lastEntryDate = day(2026, 6, 10)
        state.consecutiveDayCount = 4
        let result = GardenRules.applyingEntry(on: day(2026, 6, 11), to: state, calendar: cal)
        XCTAssertEqual(result.state.consecutiveDayCount, 5)
    }

    func testGapRestartsStreakButGrowthNeverDrops() {
        var state = GardenState.empty
        state.lastEntryDate = day(2026, 6, 1)
        state.consecutiveDayCount = 9
        state.totalEntries = 9
        state.growthStage = .budding   // earned earlier

        let result = GardenRules.applyingEntry(on: day(2026, 6, 11), to: state, calendar: cal)
        XCTAssertEqual(result.state.consecutiveDayCount, 1, "Streak restarts gently after a gap")
        XCTAssertEqual(result.state.growthStage, .budding, "Growth must never drop after a gap")
        XCTAssertEqual(result.state.totalEntries, 10)
    }

    func testSameDayEntryIsIdempotent() {
        var state = GardenState.empty
        state.lastEntryDate = day(2026, 6, 11)
        state.consecutiveDayCount = 3
        state.totalEntries = 3
        let result = GardenRules.applyingEntry(on: day(2026, 6, 11, hour: 20), to: state, calendar: cal)
        XCTAssertEqual(result.state.totalEntries, 3, "Logging again the same day must not double-count")
        XCTAssertEqual(result.state.consecutiveDayCount, 3)
        XCTAssertFalse(result.didRevive)
    }

    func testGrowthStageThresholds() {
        XCTAssertEqual(GrowthStage.stage(forTotalEntries: 0), .seed)
        XCTAssertEqual(GrowthStage.stage(forTotalEntries: 1), .sprout)
        XCTAssertEqual(GrowthStage.stage(forTotalEntries: 4), .seedling)
        XCTAssertEqual(GrowthStage.stage(forTotalEntries: 8), .budding)
        XCTAssertEqual(GrowthStage.stage(forTotalEntries: 15), .blooming)
        XCTAssertEqual(GrowthStage.stage(forTotalEntries: 100), .flourishing)
    }

    // MARK: - Brand-new garden & clock changes (never penalize)

    func testBrandNewGardenIsThriving() {
        let app = GardenRules.appearance(lastEntryDate: nil, now: day(2026, 6, 11), calendar: cal)
        XCTAssertEqual(app.vitality, .thriving)
    }

    func testClockMovingBackwardsDoesNotPenalize() {
        // "now" is *before* the last entry (device date moved back / timezone shift).
        let app = GardenRules.appearance(lastEntryDate: day(2026, 6, 11),
                                         now: day(2026, 6, 8), calendar: cal)
        XCTAssertEqual(app.vitality, .thriving)
        XCTAssertEqual(app.wiltLevel, 0)
        XCTAssertEqual(GardenRules.daysBetween(day(2026, 6, 11), day(2026, 6, 8), calendar: cal), 0)
    }
}
