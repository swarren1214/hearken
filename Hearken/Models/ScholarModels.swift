import Foundation
import SwiftData

// Scholar Path evidence. Like the other models: every property has a default and there are
// no unique constraints, so they sync through CloudKit. Uniqueness (one award per activity)
// is enforced by `key` when writing and by counting distinct keys when reading, so a
// duplicate created offline on two devices still counts once.

/// One XP award for one activity. Never edited or deleted, except by Delete Account.
@Model
final class SubjectAward {
    /// "subjectID|activityID|type", the dedupe key.
    var key: String = ""
    var subjectID: String = ""
    var activityID: String = ""
    var typeRaw: String = ""
    var amount: Int = 0
    var earnedAt: Date = Date.now
    var ruleVersion: Int = 1

    init(subjectID: String, activityID: String, type: SubjectAwardType, amount: Int, ruleVersion: Int) {
        self.key = SubjectAward.key(subjectID: subjectID, activityID: activityID, type: type)
        self.subjectID = subjectID
        self.activityID = activityID
        self.typeRaw = type.rawValue
        self.amount = amount
        self.ruleVersion = ruleVersion
    }

    static func key(subjectID: String, activityID: String, type: SubjectAwardType) -> String {
        "\(subjectID)|\(activityID)|\(type.rawValue)"
    }
}

enum SubjectAwardType: String {
    /// First completion of a learning item (lesson, reading, video, practice).
    case firstCompletion
    /// First pass of a course checkpoint.
    case checkpoint
    /// Passing the Stage 4 capstone.
    case capstone
}

/// A learning item marked done, with the learner's written response as evidence.
@Model
final class ItemCompletion {
    var itemID: String = ""
    var subjectID: String = ""
    var completedAt: Date = Date.now
    /// Unmarked by the learner. The checklist ignores it; XP already earned stays.
    var cleared: Bool = false
    var response: String = ""
    /// What the on-device reviewer said, if it looked at the response.
    var feedback: String = ""

    init(itemID: String, subjectID: String, response: String, feedback: String) {
        self.itemID = itemID
        self.subjectID = subjectID
        self.response = response
        self.feedback = feedback
    }
}

/// One attempt at a check. Every attempt is kept as evidence.
@Model
final class AssessmentAttempt {
    var assessmentID: String = ""
    var subjectID: String = ""
    /// "checkpoint", "advancement" or "capstone".
    var kindRaw: String = ""
    var questionIDs: [String] = []
    var points: Int = 0
    var maxPoints: Int = 0
    var passed: Bool = false
    /// True when any answer was scored by the on-device model.
    var aiScored: Bool = false
    /// The learner's answers and the scores they got, as JSON, for review.
    var answersJSON: String = ""
    var attemptedAt: Date = Date.now

    init(assessmentID: String, subjectID: String, kind: String, questionIDs: [String], points: Int, maxPoints: Int, passed: Bool, aiScored: Bool, answersJSON: String) {
        self.assessmentID = assessmentID
        self.subjectID = subjectID
        self.kindRaw = kind
        self.questionIDs = questionIDs
        self.points = points
        self.maxPoints = maxPoints
        self.passed = passed
        self.aiScored = aiScored
        self.answersJSON = answersJSON
    }
}

/// Starting a subject's path.
@Model
final class SubjectEnrollment {
    var subjectID: String = ""
    var enrolledAt: Date = Date.now

    init(subjectID: String) {
        self.subjectID = subjectID
    }
}

/// A rank earned in a subject. Durable: the highest grant is the rank shown, even if the
/// curriculum changes later.
@Model
final class RankGrant {
    var subjectID: String = ""
    var rankRaw: Int = 1
    var earnedAt: Date = Date.now
    var xpAtAward: Int = 0
    var ruleVersion: Int = 1
    /// What earned it: stage numbers and assessment IDs.
    var evidence: [String] = []
    /// The unlock celebration has been shown.
    var celebrated: Bool = false

    init(subjectID: String, rank: ScholarRank, xpAtAward: Int, ruleVersion: Int, evidence: [String]) {
        self.subjectID = subjectID
        self.rankRaw = rank.rawValue
        self.xpAtAward = xpAtAward
        self.ruleVersion = ruleVersion
        self.evidence = evidence
    }

    var rank: ScholarRank { ScholarRank(rawValue: rankRaw) ?? .novice }
}
