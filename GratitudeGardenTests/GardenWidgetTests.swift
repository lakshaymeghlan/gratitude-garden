import XCTest
@testable import GratitudeGarden

/// Tests for the widget's pure logic: timeline planning (so the garden ages over time), deep-link
/// generation/parsing, and the short widget copy. All time is injected via a fixed UTC calendar.
final class GardenWidgetTests: XCTestCase {

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func state(lastEntry: Date?, revival: Bool = false) -> GardenState {
        GardenState(lastEntryDate: lastEntry.map { cal.startOfDay(for: $0) },
                    consecutiveDayCount: 1, totalEntries: 5, growthStage: .blooming,
                    lastEntryWasRevival: revival)
    }

    // MARK: Timeline generation

    func testNewGardenProducesSingleThrivingEntry() {
        let plan = GardenTimelinePlanner.plan(state: .empty, now: day(2026, 6, 11), calendar: cal)
        XCTAssertEqual(plan.moments.count, 1)
        XCTAssertEqual(plan.moments.first?.snapshot.vitality, .thriving)
    }

    func testTimelineAgesFromThrivingThroughDroopingToDormant() {
        // Logged today; the plan should carry the garden through its decay without the app.
        let plan = GardenTimelinePlanner.plan(state: state(lastEntry: day(2026, 6, 11)),
                                              now: day(2026, 6, 11), calendar: cal)
        let vitalities = plan.moments.map(\.snapshot.vitality)
        XCTAssertEqual(vitalities.first, .thriving, "Starts thriving today")
        XCTAssertTrue(vitalities.contains(.drooping), "Ages into drooping")
        XCTAssertEqual(vitalities.last, .dormant, "And finally settles dormant")
    }

    func testTransitionsLandOnStartOfDay() {
        let plan = GardenTimelinePlanner.plan(state: state(lastEntry: day(2026, 6, 11)),
                                              now: day(2026, 6, 11), calendar: cal)
        // Every projected (non-now) moment is exactly a day boundary.
        for moment in plan.moments.dropFirst() {
            XCTAssertEqual(moment.date, cal.startOfDay(for: moment.date), "Entries should be at start-of-day")
        }
    }

    func testDuplicateThrivingDaysAreCollapsed() {
        // Days 1–3 after logging are all still thriving; the plan should not emit one entry per day.
        let plan = GardenTimelinePlanner.plan(state: state(lastEntry: day(2026, 6, 11)),
                                              now: day(2026, 6, 11), calendar: cal)
        let thrivingMoments = plan.moments.filter { $0.snapshot.vitality == .thriving }
        XCTAssertEqual(thrivingMoments.count, 1, "Identical thriving days collapse to one entry")
    }

    func testStopsProjectingOnceDormant() {
        let plan = GardenTimelinePlanner.plan(state: state(lastEntry: day(2026, 6, 11)),
                                              now: day(2026, 6, 11), calendar: cal)
        let dormantCount = plan.moments.filter { $0.snapshot.vitality == .dormant }.count
        XCTAssertEqual(dormantCount, 1, "Should not keep emitting unchanging dormant entries")
        XCTAssertLessThanOrEqual(plan.moments.count, 6, "Timeline stays small (battery-conscious)")
    }

    func testRevivalShowsTodayThenClearsNextDay() {
        // Revived today: the welcome-back moment shows now, but not on the next day's entry.
        let plan = GardenTimelinePlanner.plan(state: state(lastEntry: day(2026, 6, 11), revival: true),
                                              now: day(2026, 6, 11), calendar: cal)
        XCTAssertTrue(plan.moments.first!.snapshot.isReviving, "Welcome-back shows at 'now'")
        XCTAssertTrue(plan.moments.dropFirst().allSatisfy { !$0.snapshot.isReviving },
                      "And clears on subsequent days")
    }

    // MARK: Deep links

    func testComposeURLString() {
        XCTAssertEqual(GardenDeepLink.composeURL.absoluteString, "gratitudegarden://compose")
    }

    func testRoutesComposeURL() {
        XCTAssertEqual(GardenDeepLink.route(for: GardenDeepLink.composeURL), .compose)
        XCTAssertEqual(GardenDeepLink.route(for: URL(string: "gratitudegarden://compose")!), .compose)
    }

    func testRejectsForeignAndUnknownURLs() {
        XCTAssertNil(GardenDeepLink.route(for: URL(string: "https://example.com/compose")!))
        XCTAssertNil(GardenDeepLink.route(for: URL(string: "gratitudegarden://settings")!))
    }

    // MARK: Widget copy

    func testWidgetShortCopy() {
        XCTAssertEqual(GardenCopy.widgetShort(.thriving, isReviving: false), "Thriving")
        XCTAssertEqual(GardenCopy.widgetShort(.drooping, isReviving: false), "Waiting for you")
        XCTAssertEqual(GardenCopy.widgetShort(.dormant, isReviving: false), "Ready to bloom again")
        XCTAssertEqual(GardenCopy.widgetShort(.dormant, isReviving: true), "Welcome back")
    }
}

/// Verifies the app router turns a deep link into a compose request.
@MainActor
final class AppRouterTests: XCTestCase {
    func testComposeDeepLinkRequestsComposer() {
        let router = AppRouter()
        XCTAssertFalse(router.isComposing)
        XCTAssertTrue(router.handle(url: GardenDeepLink.composeURL))
        XCTAssertTrue(router.isComposing)
    }

    func testForeignURLIsIgnored() {
        let router = AppRouter()
        XCTAssertFalse(router.handle(url: URL(string: "https://example.com")!))
        XCTAssertFalse(router.isComposing)
    }
}
