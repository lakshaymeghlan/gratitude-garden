import Foundation
import Observation

/// What a successful save produced — used by the view layer to decide which (optional) haptic/sound
/// to play. Kept UIKit-free so the view model never imports feedback frameworks.
struct EntrySaveOutcome: Equatable {
    let didRevive: Bool
    let reachedFirstBloom: Bool
}

/// Drives the garden home screen and the entry composer.
///
/// Holds its collaborators via dependency injection (`GardenJournal`, `WidgetReloading`, a `now`
/// clock) so it runs on real shared storage in the app and on fakes in tests. It owns no garden
/// *logic* — that lives in the pure rules engine via the journal.
@MainActor
@Observable
final class GardenViewModel {
    private let journal: GardenJournal
    private let widgetReloader: WidgetReloading
    private let now: () -> Date

    private(set) var snapshot: GardenSnapshot
    private(set) var entries: [Entry]
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

    var sharedStoragePath: String? { journal.sharedStoragePath() }

    /// Call at launch / first appear: heal any lost state from the journal, then load. This is the
    /// forgiving recovery in action — a corrupt or reset state file is rebuilt from entries.
    func onAppear() {
        if journal.repair() { widgetReloader.reloadGardenWidget() }
        refresh()
    }

    func refresh() {
        snapshot = journal.snapshot(now: now())
        entries = journal.allEntries()
        showWelcomeBack = snapshot.isReviving
    }

    /// Logs an entry through the rules engine, persists, refreshes, and reloads the widget. Returns
    /// the outcome (nil if the text was empty / save failed) so the caller can play feedback.
    @discardableResult
    func save(text: String, kind: EntryKind) -> EntrySaveOutcome? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let growthBefore = snapshot.growthStage
        do {
            let result = try journal.log(text: text, kind: kind, on: now())
            widgetReloader.reloadGardenWidget()
            snapshot = journal.snapshot(now: now())
            entries = journal.allEntries()
            showWelcomeBack = result.didRevive
            let reachedFirstBloom = growthBefore < .blooming && result.garden.growthStage >= .blooming
            return EntrySaveOutcome(didRevive: result.didRevive, reachedFirstBloom: reachedFirstBloom)
        } catch {
            print("Save failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Clears the garden and journal (Settings → Reset, behind a confirmation).
    func resetGarden() {
        try? journal.reset()
        showWelcomeBack = false
        widgetReloader.reloadGardenWidget()
        refresh()
    }
}
