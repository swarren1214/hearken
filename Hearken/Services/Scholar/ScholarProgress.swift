import Foundation
import SwiftData

/// A read-only view of one subject's Scholar Path progress, built from SwiftData queries.
/// Everything is computed from evidence, never stored, so devices can't disagree.
struct ScholarProgress {
    let path: ScholarPathFile
    /// XP: distinct award keys only, so duplicates from sync count once.
    let xp: Int
    private let doneItems: Set<String>
    private let awardedKeys: Set<String>
    private let passed: Set<String>
    private let bestAttempt: [String: AssessmentAttempt]
    let storedRank: ScholarRank?
    let grants: [RankGrant]
    let isEnrolled: Bool

    init(path: ScholarPathFile, awards: [SubjectAward], completions: [ItemCompletion], attempts: [AssessmentAttempt], grants: [RankGrant], enrollments: [SubjectEnrollment]) {
        let subjectID = path.subjectID
        self.path = path

        var seen: Set<String> = []
        var total = 0
        for award in awards where award.subjectID == subjectID && !seen.contains(award.key) {
            seen.insert(award.key)
            total += award.amount
        }
        xp = total
        awardedKeys = Set(seen.map { $0.split(separator: "|").dropFirst().first.map(String.init) ?? "" })

        let done = Set(completions.filter { $0.subjectID == subjectID && !$0.cleared }.map(\.itemID))
        doneItems = done

        var best: [String: AssessmentAttempt] = [:]
        var passedIDs: Set<String> = []
        for attempt in attempts where attempt.subjectID == subjectID {
            if attempt.passed { passedIDs.insert(attempt.assessmentID) }
            if let current = best[attempt.assessmentID], current.points >= attempt.points { continue }
            best[attempt.assessmentID] = attempt
        }
        bestAttempt = best
        passed = passedIDs

        let mine = grants.filter { $0.subjectID == subjectID }.sorted { $0.rankRaw < $1.rankRaw }
        self.grants = mine
        storedRank = mine.last?.rank
        isEnrolled = enrollments.contains { $0.subjectID == subjectID } || !done.isEmpty
    }

    // MARK: Items and courses

    func isDone(_ item: PathItem) -> Bool { doneItems.contains(item.id) }

    /// XP for this item has been paid (perhaps through its equivalent).
    func isAwarded(_ item: PathItem) -> Bool { awardedKeys.contains(item.awardKey) }

    func hasPassed(_ assessment: PathAssessment?) -> Bool {
        guard let assessment else { return true }
        return passed.contains(assessment.id)
    }

    func best(_ assessment: PathAssessment) -> AssessmentAttempt? { bestAttempt[assessment.id] }

    struct CourseStatus {
        let requiredDone: Int
        let requiredTotal: Int
        let xpEarned: Int
        let xpAvailable: Int
        let checkpointPassed: Bool

        var requiredComplete: Bool { requiredDone == requiredTotal }
        var isComplete: Bool { requiredComplete && checkpointPassed }
        var fraction: Double {
            let steps = requiredTotal + 1
            return Double(requiredDone + (checkpointPassed ? 1 : 0)) / Double(max(steps, 1))
        }
    }

    func status(of course: PathCourse) -> CourseStatus {
        let required = course.requiredItems
        let earned = course.allItems.filter { isAwarded($0) }.reduce(0) { $0 + $1.xp }
        let checkpointPassed = hasPassed(course.checkpoint)
        return CourseStatus(
            requiredDone: required.filter { isDone($0) }.count,
            requiredTotal: required.count,
            xpEarned: earned + (checkpointPassed && course.checkpoint != nil ? ScholarRules.checkpointXP : 0),
            xpAvailable: course.requiredXP,
            checkpointPassed: checkpointPassed
        )
    }

    /// The course can be started: every earlier course in the path is complete, and so is
    /// the previous stage's advancement check.
    func isUnlocked(_ course: PathCourse) -> Bool {
        if ScholarDebug.unlockAll { return true }
        for stage in path.publishedStages {
            for other in stage.courses {
                if other.id == course.id { return true }
                if !status(of: other).isComplete { return false }
            }
            if !hasPassed(stage.advancementCheck) { return false }
        }
        return false
    }

    // MARK: Stages

    func coursesComplete(in stage: PathStage) -> Int { stage.courses.filter { status(of: $0).isComplete }.count }

    /// Every course complete, so the advancement check is open.
    func isAdvancementOpen(_ stage: PathStage) -> Bool { ScholarDebug.unlockAll || allCoursesComplete(stage) }

    private func allCoursesComplete(_ stage: PathStage) -> Bool { coursesComplete(in: stage) == stage.courses.count }

    /// Complete for earning ranks: always the real rule, even with Unlock All Courses on.
    func isComplete(_ stage: PathStage) -> Bool {
        guard stage.published, allCoursesComplete(stage), hasPassed(stage.advancementCheck) else { return false }
        if stage.number == 4, let capstone = path.capstone, !passed.contains(capstone.id) { return false }
        return true
    }

    /// Contiguous complete stages from Stage 1.
    var completedStages: Int {
        var count = 0
        for stage in path.stages.sorted(by: { $0.number < $1.number }) {
            guard isComplete(stage) else { break }
            count += 1
        }
        return count
    }

    /// The stage being worked on: the first one not complete.
    var currentStage: PathStage? {
        path.publishedStages.sorted { $0.number < $1.number }.first { !isComplete($0) }
    }

    // MARK: Ranks

    var hasCompletedAnItem: Bool { !doneItems.isEmpty || !awardedKeys.isEmpty }

    /// The rank the evidence supports (never lower than one already granted).
    var rank: ScholarRank? {
        ScholarRules.rank(xp: xp, completedStages: completedStages, hasCompletedAnItem: hasCompletedAnItem, stored: storedRank, ceiling: path.highestAttainableRank)
    }

    /// The next rank this path can award as published, or nil at the top.
    var nextRank: ScholarRank? {
        let next = rank?.next ?? (rank == nil ? .novice : nil)
        guard let next, next <= path.highestAttainableRank else { return nil }
        if next > .novice, path.publishedStages.first(where: { $0.number == next.requiredStages }) == nil { return nil }
        return next
    }

    /// Progress toward the next rank's XP, 0…1. Novice has no XP bar (it's earned by finishing
    /// any item), so before that it reads 0; at the top of the path it reads 1.
    var xpFraction: Double {
        guard let next = nextRank else { return 1 }
        guard next.xpThreshold > 0 else { return 0 }
        return min(Double(xp) / Double(next.xpThreshold), 1)
    }

    /// Whether the next rank's XP requirement is met. Never true for Novice, which has none.
    var xpReached: Bool {
        guard let next = nextRank, next.xpThreshold > 0 else { return false }
        return xp >= next.xpThreshold
    }

    /// The stage the next rank needs.
    var nextStage: PathStage? {
        guard let next = nextRank, next.requiredStages > 0 else { return nil }
        return path.stages.first { $0.number == next.requiredStages }
    }

    func grant(_ rank: ScholarRank) -> RankGrant? { grants.first { $0.rankRaw == rank.rawValue } }
}

// MARK: - Writing

/// Writes awards, completions, attempts and rank grants. Every write is idempotent.
@MainActor
struct ScholarLedger {
    let context: ModelContext

    /// Records a completed learning item and pays its XP the first time.
    func complete(_ item: PathItem, in path: ScholarPathFile, response: String, feedback: String) {
        let subjectID = path.subjectID
        let itemID = item.id
        let descriptor = FetchDescriptor<ItemCompletion>(predicate: #Predicate { $0.itemID == itemID && $0.subjectID == subjectID })
        if let existing = try? context.fetch(descriptor).first {
            existing.cleared = false
            existing.response = response
            existing.feedback = feedback
            existing.completedAt = .now
        } else {
            context.insert(ItemCompletion(itemID: itemID, subjectID: subjectID, response: response, feedback: feedback))
        }
        ensureEnrolled(subjectID)
        award(subjectID: subjectID, activityID: item.awardKey, type: .firstCompletion, amount: item.xp)
        refreshGrants(for: path)
    }

    /// Unmarks an item. Its XP stays, but the checklist (and future ranks) need it again.
    func clear(_ item: PathItem, in path: ScholarPathFile) {
        let subjectID = path.subjectID
        let itemID = item.id
        let descriptor = FetchDescriptor<ItemCompletion>(predicate: #Predicate { $0.itemID == itemID && $0.subjectID == subjectID })
        for completion in (try? context.fetch(descriptor)) ?? [] { completion.cleared = true }
    }

    /// Records an attempt; a first passing checkpoint pays 100 XP, a passed capstone 200.
    func record(_ attempt: AssessmentAttempt, in path: ScholarPathFile) {
        context.insert(attempt)
        ensureEnrolled(path.subjectID)
        if attempt.passed {
            switch attempt.kindRaw {
            case "checkpoint": award(subjectID: path.subjectID, activityID: attempt.assessmentID, type: .checkpoint, amount: ScholarRules.checkpointXP)
            case "capstone": award(subjectID: path.subjectID, activityID: attempt.assessmentID, type: .capstone, amount: ScholarRules.capstoneXP)
            default: break
            }
        }
        refreshGrants(for: path)
    }

    func ensureEnrolled(_ subjectID: String) {
        let id = subjectID
        let descriptor = FetchDescriptor<SubjectEnrollment>(predicate: #Predicate { $0.subjectID == id })
        if ((try? context.fetchCount(descriptor)) ?? 0) == 0 {
            context.insert(SubjectEnrollment(subjectID: subjectID))
        }
    }

    @discardableResult
    func award(subjectID: String, activityID: String, type: SubjectAwardType, amount: Int) -> Bool {
        let key = SubjectAward.key(subjectID: subjectID, activityID: activityID, type: type)
        let descriptor = FetchDescriptor<SubjectAward>(predicate: #Predicate { $0.key == key })
        guard ((try? context.fetchCount(descriptor)) ?? 0) == 0 else { return false }
        context.insert(SubjectAward(subjectID: subjectID, activityID: activityID, type: type, amount: amount, ruleVersion: ScholarRules.ruleVersion))
        return true
    }

    /// Writes a grant for every rank the evidence now supports that isn't granted yet.
    /// New grants are celebrated by ScholarCelebrations.
    func refreshGrants(for path: ScholarPathFile) {
        let subjectID = path.subjectID
        func fetch<T: PersistentModel>(_ type: T.Type, _ predicate: Predicate<T>) -> [T] {
            (try? context.fetch(FetchDescriptor<T>(predicate: predicate))) ?? []
        }
        let progress = ScholarProgress(
            path: path,
            awards: fetch(SubjectAward.self, #Predicate<SubjectAward> { $0.subjectID == subjectID }),
            completions: fetch(ItemCompletion.self, #Predicate<ItemCompletion> { $0.subjectID == subjectID }),
            attempts: fetch(AssessmentAttempt.self, #Predicate<AssessmentAttempt> { $0.subjectID == subjectID }),
            grants: fetch(RankGrant.self, #Predicate<RankGrant> { $0.subjectID == subjectID }),
            enrollments: []
        )
        guard let earned = progress.rank else { return }
        for rank in ScholarRank.allCases where rank <= earned && progress.grant(rank) == nil {
            var evidence = (0..<rank.requiredStages).map { "stage-\($0 + 1)" }
            evidence += path.stages.filter { $0.number <= rank.requiredStages }.compactMap { $0.advancementCheck?.id }
            context.insert(RankGrant(subjectID: subjectID, rank: rank, xpAtAward: progress.xp, ruleVersion: ScholarRules.ruleVersion, evidence: evidence))
        }
    }
}

/// Testing aid: Settings › Developer › Unlock All Courses (debug builds only). Opens every
/// course and check so a path can be reviewed end to end. Earning rules are unchanged.
enum ScholarDebug {
    static let unlockAllKey = "scholar.debug.unlockAll"

    static var unlockAll: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: unlockAllKey)
        #else
        return false
        #endif
    }
}
