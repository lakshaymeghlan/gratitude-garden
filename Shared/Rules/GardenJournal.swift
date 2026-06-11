import Foundation

/// The outcome of logging an entry.
struct LogResult: Equatable {
    let garden: GardenState
    let entry: Entry
    /// True if this entry brought the garden back from drooping/dormancy → show "welcome back".
    let didRevive: Bool
}

/// Orchestrates the daily-entry loop: persist the journal entry, run the pure rules engine to
/// advance `GardenState`, and persist that too.
///
/// Lives in `Shared/` and is platform-independent (Foundation only) so it's fully unit-testable and
/// free of any UIKit/WidgetKit dependency. It deliberately does NOT know about widget reloading —
/// that's an app concern the view model handles after a successful `log`.
///
/// `calendar` is injectable for deterministic tests; production uses `.current`.
final class GardenJournal {
    private let store: GardenStore
    private let calendar: Calendar

    init(store: GardenStore, calendar: Calendar = .current) {
        self.store = store
        self.calendar = calendar
    }

    func currentGarden() -> GardenState { store.loadGarden() }

    /// Heals lost or corrupt garden state by replaying the journal. Safe to call at every launch:
    /// if the stored state was reset (e.g. its file was corrupt and got quarantined) but entries
    /// survived, this rebuilds growth from them and re-persists. Returns whether a repair happened.
    @discardableResult
    func repair() -> Bool {
        let entries = store.loadEntries()
        guard !entries.isEmpty else { return false }
        let stored = store.loadGarden()
        let rebuilt = GardenRules.rebuild(fromEntries: entries, calendar: calendar)
        // Only overwrite when the journal implies more progress than the stored state has — i.e. the
        // stored state was genuinely lost. Never regress a healthy state.
        guard rebuilt.totalEntries > stored.totalEntries else { return false }
        try? store.save(rebuilt)
        return true
    }

    /// Clears the garden and journal entirely (used by Settings → Reset, behind a confirmation).
    func reset() throws {
        try store.save(GardenState.empty)
        try store.save([Entry]())
    }

    /// Newest-first, for the journal/history view.
    func allEntries() -> [Entry] {
        store.loadEntries().sorted { $0.date > $1.date }
    }

    /// The render descriptor for "now".
    func snapshot(now: Date) -> GardenSnapshot {
        GardenRules.snapshot(state: store.loadGarden(), now: now, calendar: calendar)
    }

    func sharedStoragePath() -> String? { store.sharedStoragePath() }

    /// Logs an entry: appends it to the journal, advances the garden via the rules engine, and
    /// persists both. Returns the new state and whether the garden revived.
    ///
    /// Note: the journal records every entry, but `GardenState.totalEntries` counts distinct *days*
    /// logged (the rules engine is idempotent within a day) — so writing twice in one day enriches
    /// the journal without ever inflating growth.
    @discardableResult
    func log(text: String, kind: EntryKind, on date: Date) throws -> LogResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = Entry(date: date, text: trimmed, kind: kind)

        var entries = store.loadEntries()
        entries.append(entry)
        try store.save(entries)

        let result = GardenRules.applyingEntry(on: date, to: store.loadGarden(), calendar: calendar)
        try store.save(result.state)

        return LogResult(garden: result.state, entry: entry, didRevive: result.didRevive)
    }
}
