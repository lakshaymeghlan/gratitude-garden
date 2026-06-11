import Foundation
import Observation

/// Drives the garden home screen and the entry composer.
///
/// Holds its collaborators via dependency injection (`GardenJournal`, `WidgetReloading`, and a
/// `now` clock) so it runs on real shared storage in the app and on fakes in tests. It owns no
/// garden *logic* — all of that lives in the pure rules engine via the journal. Its job is to read
/// the current snapshot, route saves through the journal, and nudge the widget afterwards.
@MainActor
@Observable
final class GardenViewModel {
    private let journal: GardenJournal
    private let widgetReloader: WidgetReloading
    private let now: () -> Date

    /// The single render descriptor for the current garden state.
    private(set) var snapshot: GardenSnapshot
    /// Journal entries, newest first.
    private(set) var entries: [Entry]
    /// Drives the transient welcome-back banner shown right after a reviving save.
    var showWelcomeBack: Bool = false

    init(journal: GardenJournal = GardenJournal(store: FileGardenStore()),
         widgetReloader: WidgetReloading = WidgetCenterReloader(),
         now: @escaping () -> Date = Date.init) {
        self.journal = journal
        self.widgetReloader = widgetReloader
        self.now = now
        self.snapshot = journal.snapshot(now: now())
        self.entries = journal.allEntries()
    }

    /// Container path, or `nil` if the App Group is unreachable — surfaced as a diagnostic.
    var sharedStoragePath: String? { journal.sharedStoragePath() }

    /// Re-reads shared storage (e.g. on foreground / first appear). Also reflects a persisted
    /// revival so the welcome-back message survives a relaunch on the day of return.
    func refresh() {
        snapshot = journal.snapshot(now: now())
        entries = journal.allEntries()
        showWelcomeBack = snapshot.isReviving
    }

    /// Logs an entry through the rules engine, persists it, refreshes state, and reloads the widget.
    /// Returns whether the save succeeded (the composer dismisses on success).
    @discardableResult
    func save(text: String, kind: EntryKind) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        do {
            let result = try journal.log(text: text, kind: kind, on: now())
            widgetReloader.reloadGardenWidget()
            snapshot = journal.snapshot(now: now())
            entries = journal.allEntries()
            showWelcomeBack = result.didRevive
            return true
        } catch {
            // POC-level handling; richer error UI can come in Phase 6.
            print("Save failed: \(error.localizedDescription)")
            return false
        }
    }
}
