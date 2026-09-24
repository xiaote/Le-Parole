import Foundation

@Observable
final class SettingsViewModel {
    private let store = SettingsStore.shared

    var dailyPracticeGoal: Int {
        get { store.dailyPracticeGoal }
        set { store.update { $0.dailyPracticeGoal = newValue } }
    }

    var newWordsPerDay: Int {
        get { store.dailyNewWordGoal }
        set { store.update { $0.dailyNewWordGoal = newValue } }
    }

    var autoPlayPronunciation: Bool {
        get { store.autoPlayPronunciation }
        set { store.update { $0.autoPlayPronunciation = newValue } }
    }

    var conjugationLevel: Int {
        get { store.conjugationLevel }
        set { store.update { $0.conjugationLevel = newValue } }
    }

    /// Kept in the Keychain rather than SQLite so it never ends up in a backup.
    var geminiApiKey = KeychainStore.get(KeychainStore.geminiApiKey) ?? "" {
        didSet { KeychainStore.set(geminiApiKey, for: KeychainStore.geminiApiKey) }
    }

    /// A restore can move a legacy key from the database into the Keychain.
    func reloadGeminiApiKey() {
        let storedKey = KeychainStore.get(KeychainStore.geminiApiKey) ?? ""
        if storedKey != geminiApiKey { geminiApiKey = storedKey }
    }
}
