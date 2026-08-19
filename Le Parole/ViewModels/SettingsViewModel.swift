import Foundation
import GRDB

@Observable
final class SettingsViewModel {
    var settings: UserSettings?

    private var cancellable: AnyDatabaseCancellable?

    init() {
        let db = DatabaseService.shared
        cancellable = db.makeSettingsObservation().start(
            in: db.db,
            scheduling: .async(onQueue: .main),
            onError: { _ in },
            onChange: { [weak self] s in self?.settings = s }
        )
    }

    var dailyPracticeGoal: Int {
        get { settings?.dailyPracticeGoal ?? 20 }
        set {
            guard var s = settings else { return }
            s.dailyPracticeGoal = newValue
            Task.detached {
                try? DatabaseService.shared.db.write { db in try s.save(db) }
            }
        }
    }

    var newWordsPerDay: Int {
        get { settings?.dailyNewWordGoal ?? 20 }
        set {
            guard var s = settings else { return }
            s.dailyNewWordGoal = newValue
            Task.detached {
                try? DatabaseService.shared.db.write { db in try s.save(db) }
            }
        }
    }

    var extraConjugationCards: Int {
        get { settings?.extraConjugationCards ?? 2 }
        set {
            guard var s = settings else { return }
            s.extraConjugationCards = newValue
            Task.detached {
                try? DatabaseService.shared.db.write { db in try s.save(db) }
            }
        }
    }

    var autoPlayPronunciation: Bool {
        get { settings?.autoPlayPronunciation ?? true }
        set {
            guard var s = settings else { return }
            s.autoPlayPronunciation = newValue
            Task.detached {
                try? DatabaseService.shared.db.write { db in try s.save(db) }
            }
        }
    }

    var conjugationLevel: Int {
        get { settings?.conjugationLevel ?? 1 }
        set {
            guard var s = settings else { return }
            s.conjugationLevel = newValue
            Task.detached {
                try? DatabaseService.shared.db.write { db in try s.save(db) }
            }
        }
    }

    var geminiApiKey: String {
        get { settings?.geminiApiKey ?? "" }
        set {
            guard var s = settings else { return }
            s.geminiApiKey = newValue
            Task.detached {
                try? DatabaseService.shared.db.write { db in try s.save(db) }
            }
        }
    }

    var targetLevel: String {
        get { settings?.targetLevel ?? "None" }
        set {
            guard var s = settings else { return }
            s.targetLevel = newValue
            Task.detached {
                try? DatabaseService.shared.db.write { db in try s.save(db) }
            }
        }
    }
}
