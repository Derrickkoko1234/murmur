import Foundation

/// The numbers on the home page, derived from dictation history alone.
public struct UsageStats: Sendable, Equatable {
    public let words: Int
    /// Words over time spent holding the key, so pauses count against it.
    public let wordsPerMinute: Int
    /// Consecutive days with at least one dictation, ending today — or yesterday, so the
    /// streak doesn't read as broken first thing in the morning.
    public let dayStreak: Int

    public init(
        runs: [(date: Date, seconds: Double, text: String)],
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        let words = runs.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
        let seconds = runs.reduce(0) { $0 + $1.seconds }
        self.words = words
        wordsPerMinute = seconds > 0 ? Int((Double(words) / (seconds / 60)).rounded()) : 0

        let days = Set(runs.map { calendar.startOfDay(for: $0.date) })
        var day = calendar.startOfDay(for: now)
        if !days.contains(day), let yesterday = calendar.date(byAdding: .day, value: -1, to: day) {
            day = yesterday
        }
        var streak = 0
        while days.contains(day), let previous = calendar.date(byAdding: .day, value: -1, to: day) {
            streak += 1
            day = previous
        }
        dayStreak = streak
    }
}
