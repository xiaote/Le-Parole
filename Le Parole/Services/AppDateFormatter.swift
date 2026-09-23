import Foundation

enum AppDateFormatter: Sendable {
    private static let lock = NSLock()
    private nonisolated(unsafe) static let _dayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = .current
        return df
    }()

    static func string(from date: Date) -> String {
        lock.withLock {
            _dayFormatter.string(from: date)
        }
    }

    static func date(from string: String) -> Date? {
        lock.withLock {
            _dayFormatter.date(from: string)
        }
    }
}
