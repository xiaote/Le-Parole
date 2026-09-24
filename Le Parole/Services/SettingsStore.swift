import Foundation
import GRDB

/// The single source of truth for `UserSettings`. Changes apply locally at once
/// and are persisted with `asyncWrite`, which (called from the main actor)
/// enqueues writes in order, so the last change always wins.
@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    private(set) var settings: UserSettings?
    @ObservationIgnored private var cancellable: AnyDatabaseCancellable?
    /// Observed values are ignored while local writes are in flight, so an
    /// earlier write's echo cannot briefly revert a newer local change.
    @ObservationIgnored private var pendingWrites = 0

    private init() {
        cancellable = ValueObservation.tracking { db in try UserSettings.fetchOne(db) }
            .start(
                in: DatabaseService.shared.db,
                scheduling: .immediate,
                onError: { error in print("Settings observation failed: \(error)") },
                onChange: { [weak self] settings in
                    guard let self, pendingWrites == 0 else { return }
                    self.settings = settings
                }
            )
    }

    var dailyPracticeGoal: Int { settings?.dailyPracticeGoal ?? 20 }
    var dailyNewWordGoal: Int { settings?.dailyNewWordGoal ?? 20 }
    var autoPlayPronunciation: Bool { settings?.autoPlayPronunciation ?? true }
    var conjugationLevel: Int { settings?.conjugationLevel ?? 1 }
    var targetLevel: String { settings?.targetLevel ?? "None" }

    func update(_ change: (inout UserSettings) -> Void) {
        guard var updated = settings else { return }
        change(&updated)
        settings = updated
        pendingWrites += 1
        let record = updated
        DatabaseService.shared.db.asyncWrite({ db in
            var record = record
            try record.save(db)
        }, completion: { _, result in
            if case .failure(let error) = result {
                print("Failed to save settings: \(error)")
            }
            Task { @MainActor in SettingsStore.shared.pendingWrites -= 1 }
        })
    }
}
