import Foundation
import Testing
@testable import Hearken

@MainActor
struct MasteryMathTests {
    @Test func unseenItemsHaveNoRecall() {
        #expect(MasteryMath.recall(days: 0, stability: 0) == 0)
        #expect(MasteryMath.recall(lastReviewed: nil, stability: 5, now: .now) == 0)
    }

    @Test func recallIsFullRightAfterReviewAndFallsOverTime() {
        #expect(MasteryMath.recall(days: 0, stability: 3) == 1)
        let soon = MasteryMath.recall(days: 1, stability: 3)
        let later = MasteryMath.recall(days: 10, stability: 3)
        #expect(soon > later)
        #expect(later > 0)
    }

    @Test func recallIsNinetyPercentAtStability() {
        // R = (1 + t / 9S)^-1, so at t = S recall is 0.9.
        #expect(abs(MasteryMath.recall(days: 4, stability: 4) - 0.9) < 0.000_1)
    }

    @Test func correctAnswersGrowStabilityAndMissesShrinkIt() {
        let first = MasteryMath.nextStability(current: 0, correct: true)
        #expect(first == 1)
        let second = MasteryMath.nextStability(current: first, correct: true)
        #expect(second == 2.5)
        let lapse = MasteryMath.nextStability(current: 10, correct: false)
        #expect(lapse == 4)
        #expect(MasteryMath.nextStability(current: 0.6, correct: false) == 0.5)
    }

    @Test func unitMasteryBlendsRecallAndReading() {
        let value = MasteryMath.unitMastery(recalls: [1, 0.5], readingFraction: 1)
        #expect(abs(value - (0.8 * 0.75 + 0.2)) < 0.000_1)
        #expect(MasteryMath.unitMastery(recalls: [], readingFraction: 0.5) == 0.5)
        #expect(MasteryMath.unitMastery(recalls: [0.4], readingFraction: nil) == 0.4)
        #expect(MasteryMath.unitMastery(recalls: [], readingFraction: nil) == 0)
    }

    @Test func subjectMasteryIsWeightedByItemCount() {
        let value = MasteryMath.subjectMastery(units: [(mastery: 1, weight: 3), (mastery: 0, weight: 1)])
        #expect(value == 0.75)
        let unweighted = MasteryMath.subjectMastery(units: [(mastery: 1, weight: 0), (mastery: 0, weight: 0)])
        #expect(unweighted == 0.5)
    }

    @Test(arguments: [(0.0, Tier.seeker), (0.24, .seeker), (0.25, .student), (0.62, .scholar), (0.75, .master), (1.0, .master)])
    func tiers(mastery: Double, expected: Tier) {
        #expect(Tier(mastery: mastery) == expected)
    }

    @Test func levelsMatchThePlan() {
        #expect(MasteryMath.level(forXP: 0).level == 1)
        #expect(MasteryMath.level(forXP: 399).level == 1)
        #expect(MasteryMath.level(forXP: 400).level == 2)
        let fifteen = MasteryMath.level(forXP: 3_000)
        #expect(fifteen.level == 15)
        #expect(fifteen.nextLevelXP == 3_200)
        #expect(MasteryMath.level(forXP: 3_100).fraction == 0.5)
    }

    @Test func streakCountsConsecutiveDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Denver"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 20)))
        func daysAgo(_ n: Int) -> Date { calendar.date(byAdding: .day, value: -n, to: now)! }

        #expect(MasteryMath.streak(activityDates: [], now: now, calendar: calendar) == 0)
        #expect(MasteryMath.streak(activityDates: [now, daysAgo(1), daysAgo(2)], now: now, calendar: calendar) == 3)
        // Nothing yet today still keeps yesterday's streak alive.
        #expect(MasteryMath.streak(activityDates: [daysAgo(1), daysAgo(2)], now: now, calendar: calendar) == 2)
        #expect(MasteryMath.streak(activityDates: [daysAgo(2)], now: now, calendar: calendar) == 0)
    }
}

@MainActor
struct ContentTests {
    @Test func bundledContentLoadsAndIDsAreUnique() {
        let content = ContentService()
        #expect(!content.subjects.isEmpty)
        #expect(content.chapter(content.defaultChapterID) != nil)
        #expect(Set(content.questions.map(\.id)).count == content.questions.count)
    }

    @Test func everyQuestionPointsAtRealContent() {
        let content = ContentService()
        let unitIDs = Set(content.subjects.flatMap { $0.units.map(\.id) })
        for question in content.questions {
            #expect(content.subject(question.subjectID) != nil, "\(question.id) has an unknown subject")
            #expect(unitIDs.contains(question.unitID), "\(question.id) has an unknown unit")
            #expect(question.options.indices.contains(question.answer), "\(question.id) answer is out of range")
            if let chapterID = question.chapterID {
                #expect(content.chapter(chapterID) != nil, "\(question.id) links a missing chapter")
            }
        }
    }

    @Test func referencesReadNaturally() {
        let content = ContentService()
        #expect(content.reference(chapterID: "bofm.alma.32", verse: 27) == "Alma 32:27")
    }
}
