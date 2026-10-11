import Testing
@testable import Hearken

@MainActor
struct ScholarRulesTests {
    @Test func nothingBeforeTheFirstItem() {
        #expect(ScholarRules.rank(xp: 0, completedStages: 0, hasCompletedAnItem: false, stored: nil) == nil)
    }

    @Test func firstItemEarnsNovice() {
        #expect(ScholarRules.rank(xp: 20, completedStages: 0, hasCompletedAnItem: true, stored: nil) == .novice)
    }

    @Test func xpAloneNeverEarnsARank() {
        #expect(ScholarRules.rank(xp: 5_000, completedStages: 0, hasCompletedAnItem: true, stored: nil) == .novice)
    }

    @Test func stageAloneNeverEarnsARank() {
        #expect(ScholarRules.rank(xp: 499, completedStages: 1, hasCompletedAnItem: true, stored: nil) == .novice)
    }

    @Test(arguments: [(500, 1, ScholarRank.apprentice), (1_500, 2, .investigator), (3_000, 3, .scholar), (5_000, 4, .sage)])
    func thresholds(xp: Int, stages: Int, expected: ScholarRank) {
        #expect(ScholarRules.rank(xp: xp, completedStages: stages, hasCompletedAnItem: true, stored: nil) == expected)
        #expect(ScholarRules.rank(xp: xp - 1, completedStages: stages, hasCompletedAnItem: true, stored: nil) == ScholarRank(rawValue: expected.rawValue - 1))
    }

    @Test func twoRanksAtOnce() {
        #expect(ScholarRules.rank(xp: 1_600, completedStages: 2, hasCompletedAnItem: true, stored: .novice) == .investigator)
    }

    @Test func neverLowerThanStored() {
        #expect(ScholarRules.rank(xp: 100, completedStages: 0, hasCompletedAnItem: true, stored: .scholar) == .scholar)
    }

    @Test func ceilingStopsUnpublishedRanks() {
        #expect(ScholarRules.rank(xp: 5_000, completedStages: 4, hasCompletedAnItem: true, stored: nil, ceiling: .scholar) == .scholar)
    }

    @Test func passMark() {
        #expect(ScholarRules.pointsToPass(maxPoints: 20, passPercent: 80) == 16)
        #expect(ScholarRules.pointsToPass(maxPoints: 10, passPercent: 80) == 8)
        #expect(ScholarRules.pointsToPass(maxPoints: 18, passPercent: 80) == 15)
    }

    @Test func xpSchedule() {
        #expect(ScholarRules.xp(for: .lesson) == 20)
        #expect(ScholarRules.xp(for: .reading) == 30)
        #expect(ScholarRules.xp(for: .video) == 20)
        #expect(ScholarRules.xp(for: .practice) == 10)
    }
}
