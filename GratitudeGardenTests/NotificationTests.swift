import XCTest
@testable import GratitudeGarden

/// Tests for the notification system: the pure planner (forgiving scheduling rules), the settings
/// store, and the manager's enable/disable/permission orchestration (via fakes).
final class NotificationPlannerTests: XCTestCase {

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func settings(_ enabled: Bool, hour: Int = 20) -> NotificationSettings {
        NotificationSettings(isEnabled: enabled, hour: hour, minute: 0)
    }

    private func state(lastEntry: Date?) -> GardenState {
        GardenState(lastEntryDate: lastEntry.map { cal.startOfDay(for: $0) },
                    consecutiveDayCount: 1, totalEntries: 3, growthStage: .sprout, lastEntryWasRevival: false)
    }

    // MARK: Enable / disable

    func testDisabledProducesNothing() {
        let plan = NotificationPlanner.plan(settings: settings(false),
                                            state: state(lastEntry: at(2026, 6, 11, 9)),
                                            now: at(2026, 6, 11, 9), calendar: cal)
        XCTAssertTrue(plan.isEmpty)
    }

    func testEnabledProducesFutureRemindersOnly() {
        // Now 9am; reminder time 8pm → today's 8pm is still in the future and should be included…
        let plan = NotificationPlanner.plan(settings: settings(true),
                                            state: state(lastEntry: nil),
                                            now: at(2026, 6, 11, 9), calendar: cal)
        XCTAssertFalse(plan.isEmpty)
        XCTAssertTrue(plan.allSatisfy { $0.date > at(2026, 6, 11, 9) }, "Never schedule in the past")
    }

    // MARK: Revival / never-punish

    func testSkipsTodayWhenAlreadyTended() {
        // Logged today; even though 8pm is ahead, we must NOT ping today.
        let plan = NotificationPlanner.plan(settings: settings(true),
                                            state: state(lastEntry: at(2026, 6, 11, 9)),
                                            now: at(2026, 6, 11, 9), calendar: cal)
        let todays = plan.filter { cal.isDate($0.date, inSameDayAs: at(2026, 6, 11, 12)) }
        XCTAssertTrue(todays.isEmpty, "Never notify on a day already tended (covers just-returned users)")
        XCTAssertTrue(plan.allSatisfy { $0.date >= at(2026, 6, 12, 0) }, "Soonest reminder is tomorrow")
    }

    // MARK: Grace period → tone

    func testGraceDaysUseDailyReminderTone() {
        // Logged today; the next eligible reminders (days 1–2 out) are within the thriving grace.
        let plan = NotificationPlanner.plan(settings: settings(true),
                                            state: state(lastEntry: at(2026, 6, 11, 9)),
                                            now: at(2026, 6, 11, 9), calendar: cal)
        let firstTwo = plan.prefix(2)
        XCTAssertTrue(firstTwo.allSatisfy { $0.tier == .dailyReminder },
                      "Within grace, reminders stay light/daily")
    }

    func testDayThreePlusBecomesGentleNudge() {
        let plan = NotificationPlanner.plan(settings: settings(true),
                                            state: state(lastEntry: at(2026, 6, 11, 9)),
                                            now: at(2026, 6, 11, 9), calendar: cal)
        XCTAssertTrue(plan.contains { $0.tier == .gentleNudge },
                      "Once drooping (day 3+), tone shifts to a gentle nudge")
        // And gentle-nudge copy must stay forgiving.
        for n in plan where n.tier == .gentleNudge {
            XCTAssertTrue(NotificationCopy.gentleNudges.contains(.init(title: n.title, body: n.body)))
        }
    }

    func testDormantUsesInvitationTone() {
        // Last entry long ago → all upcoming reminders are dormant invitations.
        let plan = NotificationPlanner.plan(settings: settings(true),
                                            state: state(lastEntry: at(2026, 1, 1, 9)),
                                            now: at(2026, 6, 11, 9), calendar: cal)
        XCTAssertFalse(plan.isEmpty)
        XCTAssertTrue(plan.allSatisfy { $0.tier == .dormantInvitation })
    }

    // MARK: Copy is forgiving (defensive scan)

    func testNoForbiddenLanguageInAnyCopy() {
        let banned = ["missed", "streak", "don't forget", "falling behind", "dying", "come back"]
        let all = NotificationCopy.dailyReminders + NotificationCopy.gentleNudges + NotificationCopy.dormantInvitations
        for line in all {
            let text = (line.title + " " + line.body).lowercased()
            for word in banned {
                XCTAssertFalse(text.contains(word), "Forbidden phrase “\(word)” in: \(text)")
            }
        }
    }

    func testHorizonIsBounded() {
        let plan = NotificationPlanner.plan(settings: settings(true),
                                            state: state(lastEntry: nil),
                                            now: at(2026, 6, 11, 9), calendar: cal)
        XCTAssertLessThanOrEqual(plan.count, NotificationPlanner.horizonDays + 1)
    }
}

// MARK: - Settings store

final class NotificationSettingsStoreTests: XCTestCase {
    func testRoundTripAndDefault() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = FileNotificationSettingsStore(locator: FixedURLLocator(url: dir))
        XCTAssertEqual(store.load(), .default, "Fresh install uses the (off) default")

        var s = NotificationSettings.default
        s.isEnabled = true; s.hour = 7; s.minute = 30
        try store.save(s)
        XCTAssertEqual(FileNotificationSettingsStore(locator: FixedURLLocator(url: dir)).load(), s)
    }
}

// MARK: - Manager orchestration (with fakes)

@MainActor
final class NotificationManagerTests: XCTestCase {

    private func makeManager(status: NotificationAuthorizationStatus,
                             enabledInStore: Bool = false) throws -> (NotificationManager, SpyScheduler, FakeAuthorizer) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let locator = FixedURLLocator(url: dir)
        let gardenStore = FileGardenStore(locator: locator)
        // Give the garden a last entry yesterday so there are future reminders to schedule.
        var g = GardenState.empty
        g.lastEntryDate = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))
        try gardenStore.save(g)

        let settingsStore = FileNotificationSettingsStore(locator: locator)
        if enabledInStore { try settingsStore.save(NotificationSettings(isEnabled: true, hour: 20, minute: 0)) }

        let scheduler = SpyScheduler()
        let authorizer = FakeAuthorizer(status: status)
        let manager = NotificationManager(authorizer: authorizer, scheduler: scheduler,
                                          settingsStore: settingsStore, gardenStore: gardenStore)
        return (manager, scheduler, authorizer)
    }

    func testEnablingRequestsPermissionWhenNotDetermined() async throws {
        let (manager, scheduler, authorizer) = try makeManager(status: .notDetermined)
        authorizer.statusAfterRequest = .authorized
        await manager.setEnabled(true)
        XCTAssertEqual(authorizer.requestCount, 1, "Enabling should prompt when undetermined")
        XCTAssertEqual(manager.authorizationStatus, .authorized)
        XCTAssertFalse(scheduler.lastScheduled.isEmpty, "Authorized + enabled → reminders scheduled")
    }

    func testEnablingButDeniedSchedulesNothing() async throws {
        let (manager, scheduler, authorizer) = try makeManager(status: .notDetermined)
        authorizer.statusAfterRequest = .denied
        await manager.setEnabled(true)
        XCTAssertEqual(manager.authorizationStatus, .denied)
        XCTAssertTrue(scheduler.lastScheduled.isEmpty, "Denied → nothing scheduled")
        XCTAssertGreaterThan(scheduler.cancelCount, 0, "Denied → pending cleared")
        XCTAssertNil(manager.nextReminder)
    }

    func testDisablingCancelsEverything() async throws {
        let (manager, scheduler, _) = try makeManager(status: .authorized, enabledInStore: true)
        await manager.onForeground()                 // authorized + enabled → schedules
        XCTAssertFalse(scheduler.lastScheduled.isEmpty)

        await manager.setEnabled(false)
        XCTAssertTrue(scheduler.lastScheduled.isEmpty)
        XCTAssertGreaterThan(scheduler.cancelCount, 0)
    }

    func testChangingTimeReschedules() async throws {
        let (manager, scheduler, _) = try makeManager(status: .authorized, enabledInStore: true)
        await manager.onForeground()
        let before = scheduler.replaceCount
        await manager.setReminderTime(hour: 7, minute: 15)
        XCTAssertGreaterThan(scheduler.replaceCount, before, "New time should reschedule")
    }
}

// MARK: - Fakes

final class FakeAuthorizer: NotificationAuthorizing {
    var status: NotificationAuthorizationStatus
    var statusAfterRequest: NotificationAuthorizationStatus?
    private(set) var requestCount = 0
    init(status: NotificationAuthorizationStatus) { self.status = status }

    func currentStatus() async -> NotificationAuthorizationStatus { status }
    func requestAuthorization() async -> NotificationAuthorizationStatus {
        requestCount += 1
        if let s = statusAfterRequest { status = s }
        return status
    }
}

final class SpyScheduler: NotificationScheduling {
    private(set) var lastScheduled: [PlannedNotification] = []
    private(set) var replaceCount = 0
    private(set) var cancelCount = 0

    func replaceAll(with planned: [PlannedNotification], calendar: Calendar) async {
        replaceCount += 1
        lastScheduled = planned
    }
    func cancelAll() async {
        cancelCount += 1
        lastScheduled = []
    }
    func pendingIdentifiers() async -> [String] { lastScheduled.map(\.id) }
}
