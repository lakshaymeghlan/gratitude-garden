import Foundation
import Observation

/// Ties together permission, scheduling, settings, and the pure `NotificationPlanner`. The settings
/// screen observes it; it contains no scheduling *rules* itself (those live in the planner) — only
/// orchestration: read state, plan, and either post or cancel.
@MainActor
@Observable
final class NotificationManager {
    private let authorizer: NotificationAuthorizing
    private let scheduler: NotificationScheduling
    private let settingsStore: NotificationSettingsStore
    private let gardenStore: GardenStore
    private let calendar: Calendar
    private let now: () -> Date

    private(set) var settings: NotificationSettings
    private(set) var authorizationStatus: NotificationAuthorizationStatus = .notDetermined
    /// The next reminder we've actually scheduled (for the "next reminder" preview); nil if none.
    private(set) var nextReminder: PlannedNotification?

    init(authorizer: NotificationAuthorizing = UserNotificationAuthorizer(),
         scheduler: NotificationScheduling = UserNotificationScheduler(),
         settingsStore: NotificationSettingsStore = FileNotificationSettingsStore(),
         gardenStore: GardenStore = FileGardenStore(),
         calendar: Calendar = .current,
         now: @escaping () -> Date = Date.init) {
        self.authorizer = authorizer
        self.scheduler = scheduler
        self.settingsStore = settingsStore
        self.gardenStore = gardenStore
        self.calendar = calendar
        self.now = now
        self.settings = settingsStore.load()
    }

    /// Call when the app appears/returns to foreground: refresh authorization and reschedule so the
    /// timeline reflects today's date and any entries logged elsewhere.
    func onForeground() async {
        authorizationStatus = await authorizer.currentStatus()
        await refreshSchedule()
    }

    /// Turn reminders on/off. Enabling prompts for permission if it hasn't been asked yet.
    func setEnabled(_ enabled: Bool) async {
        settings.isEnabled = enabled
        persist()
        if enabled {
            authorizationStatus = authorizationStatus == .notDetermined
                ? await authorizer.requestAuthorization()
                : await authorizer.currentStatus()
        }
        await refreshSchedule()
    }

    func setReminderTime(hour: Int, minute: Int) async {
        settings.hour = hour
        settings.minute = minute
        persist()
        await refreshSchedule()
    }

    /// Explicit re-request (used by the settings screen when status is `.notDetermined`).
    func requestPermission() async {
        authorizationStatus = await authorizer.requestAuthorization()
        await refreshSchedule()
    }

    /// Recomputes the plan and either posts it or cancels everything. Safe to call any time.
    func refreshSchedule() async {
        let planned = NotificationPlanner.plan(settings: settings,
                                               state: gardenStore.loadGarden(),
                                               now: now(),
                                               calendar: calendar)
        let canSchedule = settings.isEnabled && authorizationStatus.allowsScheduling && !planned.isEmpty
        if canSchedule {
            await scheduler.replaceAll(with: planned, calendar: calendar)
            nextReminder = planned.first
        } else {
            await scheduler.cancelAll()
            nextReminder = nil
        }
    }

    private func persist() { try? settingsStore.save(settings) }
}
