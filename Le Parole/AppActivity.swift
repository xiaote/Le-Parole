import Foundation

/// Shared presentation state for work that is unnecessary while a full-screen
/// study session covers the dashboard tabs.
@Observable
final class AppActivity {
    var isStudySessionActive = false
}
