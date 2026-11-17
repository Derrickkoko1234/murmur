import Foundation
import Testing

import MurmurCore

struct UsageStatsTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Noon on 2026-10-26 plus `days`, in UTC.
    private func day(_ days: Int) -> Date {
        Date(timeIntervalSince1970: 1_793_016_000 + Double(days) * 86_400)
    }

    @Test("words and words per minute")
    func words() {
        let stats = UsageStats(
            runs: [(day(0), 30, "one two three"), (day(0), 30, "four  five\nsix")],
            now: day(0),
            calendar: calendar
        )
        #expect(stats.words == 6)
        #expect(stats.wordsPerMinute == 6)
    }

    @Test("no history is all zeros")
    func empty() {
        let stats = UsageStats(runs: [], now: day(0), calendar: calendar)
        #expect(stats == UsageStats(runs: [(day(-9), 0, "")], now: day(0), calendar: calendar))
        #expect(stats.words == 0 && stats.wordsPerMinute == 0 && stats.dayStreak == 0)
    }

    @Test("streak counts consecutive days back from today, stopping at a gap")
    func streak() {
        let stats = UsageStats(runs: [0, 0, -1, -2, -4].map { (day($0), 1, "hi") }, now: day(0), calendar: calendar)
        #expect(stats.dayStreak == 3)
    }

    @Test("a streak that ended yesterday is still alive today")
    func streakThroughYesterday() {
        func streak(now: Date) -> Int {
            UsageStats(runs: [-1, -2].map { (day($0), 1, "hi") }, now: now, calendar: calendar).dayStreak
        }
        #expect(streak(now: day(0)) == 2)
        #expect(streak(now: day(1)) == 0)
    }
}
