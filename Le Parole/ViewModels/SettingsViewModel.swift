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
            onChange: { [weak self] s in
                guard let self else { return }
                settings = s
                // A restore can move a legacy key from the database into the Keychain.
                let storedKey = KeychainStore.get(KeychainStore.geminiApiKey) ?? ""
                if storedKey != geminiApiKey { geminiApiKey = storedKey }
            }
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

    /// Kept in the Keychain rather than SQLite so it never ends up in a backup.
    var geminiApiKey = KeychainStore.get(KeychainStore.geminiApiKey) ?? "" {
        didSet { KeychainStore.set(geminiApiKey, for: KeychainStore.geminiApiKey) }
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
