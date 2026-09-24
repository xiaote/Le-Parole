import Foundation

/// "yyyy-MM-dd" day keys in the current time zone. `DateFormatter` is
/// thread-safe, so this is usable from any isolation.
enum AppDateFormatter: Sendable {
    private nonisolated static let dayFormatter: DateFormatter = {
        let df = DateFormatter()
        // ASCII digits, but the user's calendar (matches the historic keys).
        df.locale = Locale(identifier: "en_US_POSIX")
        df.calendar = .current
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = .current
        return df
    }()

    nonisolated static func string(from date: Date) -> String {
        dayFormatter.string(from: date)
    }

    nonisolated static func date(from string: String) -> Date? {
        dayFormatter.date(from: string)
    }
}
