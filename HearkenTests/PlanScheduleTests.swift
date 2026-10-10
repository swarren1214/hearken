import Foundation
import Testing
@testable import Hearken

@MainActor
struct PlanScheduleTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Denver")!
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    @Test func everyChapterIsAssignedOnceInOrder() {
        let weights = (1...239).map { Double(($0 * 37) % 900 + 200) }
        let ranges = PlanScheduler.partition(weights: weights, into: 90)
        #expect(ranges.count == 90)
        #expect(ranges.first?.lowerBound == 0)
        #expect(ranges.last?.upperBound == 239)
        for (a, b) in zip(ranges, ranges.dropFirst()) { #expect(a.upperBound == b.lowerBound) }
        #expect(ranges.allSatisfy { !$0.isEmpty })
    }

    @Test func longChaptersGetLighterDays() {
        // One very long chapter among short ones gets a day to itself.
        let weights: [Double] = [100, 100, 100, 1_000, 100, 100, 100]
        let ranges = PlanScheduler.partition(weights: weights, into: 3)
        #expect(ranges.contains(3..<4))
    }

    @Test func neverMoreDaysThanChapters() {
        #expect(PlanScheduler.partition(weights: [1, 1, 1], into: 10).count == 3)
    }

    @Test func weekdayPlansSkipWeekends() {
        // Friday Oct 9, 2026: the next three weekdays are Fri, Mon, Tue.
        let dates = PlanScheduler.readingDates(from: date(2026, 10, 9), count: 3, days: .weekdays, calendar: calendar)
        #expect(dates == [date(2026, 10, 9), date(2026, 10, 12), date(2026, 10, 13)])
    }

    @Test func ninetyDayPlanFinishesOnDayNinety() {
        let dates = PlanScheduler.readingDates(from: date(2026, 10, 9), count: 90, days: .everyDay, calendar: calendar)
        #expect(dates.last == date(2027, 1, 6))
    }

    @Test func behindAndNextChapter() {
        let plan = ReadingPlan(id: "t", title: "Test", subtitle: "", days: 3, coverHex: 0, chapterIDs: ["bofm.alma.1", "bofm.alma.2", "bofm.alma.3"])
        let days = PlanScheduler.days(chapterIDs: plan.chapterIDs, words: [100, 100, 100], dayCount: 3, firstDayNumber: 1,
                                      start: date(2026, 10, 7), readingDays: .everyDay, calendar: calendar)
        let state = PlanState(plan: plan, days: days, read: ["bofm.alma.2"], totalDays: 3, now: date(2026, 10, 9), calendar: calendar)
        #expect(state.daysBehind == 1)
        #expect(state.overdueChapterIDs == ["bofm.alma.1"])
        #expect(state.nextChapterID == "bofm.alma.1")
        #expect(state.dayNumber == 3)
    }

    @Test func rangesReadNaturally() {
        #expect(PlanFormat.range(["bofm.alma.5", "bofm.alma.6", "bofm.alma.7"]) == "Alma 5–7")
        #expect(PlanFormat.range(["bofm.mosiah.29", "bofm.alma.1"]) == "Mosiah 29 – Alma 1")
        #expect(PlanFormat.range(["dc-testament.dc.76"]) == "D&C 76")
        #expect(PlanFormat.perDay(chapters: 239, days: 90) == "2–3")
    }
}
