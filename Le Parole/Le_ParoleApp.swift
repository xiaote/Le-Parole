import SwiftUI

@main
struct Le_ParoleApp: App {
    init() {
        // Force DatabaseService initialization on launch so migrations run before any view appears.
        _ = DatabaseService.shared
        DatabaseService.shared.cleanupConjugatedVerbsAsync()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
