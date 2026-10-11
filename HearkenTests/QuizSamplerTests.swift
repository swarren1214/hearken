import Foundation
import Testing
@testable import Hearken

@MainActor
struct QuizSamplerTests {
    /// A small deterministic generator, so draws are repeatable.
    struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    private func question(_ id: String, family: String, type: String = "multiple_choice", overlaps: [String]? = nil) -> BankQuestion {
        var json: [String: Any] = [
            "id": id, "revision": 1, "type": type, "prompt": "Q \(id)", "explanation": "E",
            "questionFamilyID": family, "difficulty": "introductory",
        ]
        if type == "matching" {
            json["leftItems"] = [["id": "l1", "text": "A"], ["id": "l2", "text": "B"]]
            json["rightItems"] = [["id": "r1", "text": "1"], ["id": "r2", "text": "2"]]
            json["correctPairs"] = [["leftID": "l1", "rightID": "r1"], ["leftID": "l2", "rightID": "r2"]]
        } else {
            json["options"] = [["id": "o1", "text": "True"], ["id": "o2", "text": "False"]]
            json["correctOptionID"] = "o1"
        }
        if let overlaps { json["overlapsWithQuestionIDs"] = overlaps }
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(BankQuestion.self, from: data)
    }

    private func quiz(_ pool: [BankQuestion], count: Int, pass: Int, maxTF: Int? = nil, maxMatching: Int? = nil, groups: [[String]]? = nil) -> PathQuiz {
        let json: [String: Any?] = ["questionPool": pool.map(\.id), "questionCount": count, "passCount": pass, "maxTrueFalse": maxTF, "maxMatching": maxMatching, "groups": groups]
        let data = try! JSONSerialization.data(withJSONObject: json.compactMapValues { $0 })
        return try! JSONDecoder().decode(PathQuiz.self, from: data)
    }

    @Test func oneQuestionPerFamily() {
        let pool = [question("a", family: "f1"), question("b", family: "f1"), question("c", family: "f2"), question("d", family: "f3")]
        var rng = Seeded(state: 1)
        let drawn = QuizSampler.draw(quiz(pool, count: 3, pass: 2), from: pool, recent: [], using: &rng)
        #expect(drawn.count == 3)
        #expect(Set(drawn.map(\.questionFamilyID)).count == 3)
    }

    @Test func capsTrueFalseAndMatching() {
        let pool = [
            question("t1", family: "a", type: "true_false"), question("t2", family: "b", type: "true_false"),
            question("m1", family: "c", type: "matching"), question("m2", family: "d", type: "matching"),
            question("q1", family: "e"), question("q2", family: "f"),
        ]
        for seed in 1...20 {
            var rng = Seeded(state: UInt64(seed))
            let drawn = QuizSampler.draw(quiz(pool, count: 6, pass: 5, maxTF: 1, maxMatching: 1), from: pool, recent: [], using: &rng)
            #expect(drawn.filter { $0.type == .trueFalse }.count <= 1)
            #expect(drawn.filter { $0.type == .matching }.count <= 1)
        }
    }

    @Test func matchingNeverBesideItsOverlaps() {
        let pool = [question("m", family: "a", type: "matching", overlaps: ["x"]), question("x", family: "b"), question("y", family: "c")]
        for seed in 1...20 {
            var rng = Seeded(state: UInt64(seed))
            let ids = Set(QuizSampler.draw(quiz(pool, count: 3, pass: 2), from: pool, recent: [], using: &rng).map(\.id))
            #expect(!(ids.contains("m") && ids.contains("x")))
        }
    }

    @Test func freshQuestionsFirst() {
        let pool = (1...6).map { question("q\($0)", family: "f\($0)") }
        var rng = Seeded(state: 7)
        let drawn = QuizSampler.draw(quiz(pool, count: 3, pass: 2), from: pool, recent: ["q1", "q2", "q3"], using: &rng)
        #expect(Set(drawn.map(\.id)) == ["q4", "q5", "q6"])
    }

    @Test func passMarkScalesOnlyWhenThePoolIsShort() {
        let pool = (1...5).map { question("q\($0)", family: "f\($0)") }
        let spec = quiz(pool, count: 12, pass: 10)
        #expect(QuizSampler.passMark(spec, drawn: 12) == 10)
        #expect(QuizSampler.passMark(spec, drawn: 6) == 5)
    }

    @Test func matchingNeedsEveryPair() {
        let set = question("m", family: "a", type: "matching")
        #expect(BankAnswer(pairs: ["l1": "r1", "l2": "r2"]).isCorrect(for: set))
        #expect(!BankAnswer(pairs: ["l1": "r2", "l2": "r1"]).isCorrect(for: set))
        #expect(!BankAnswer(pairs: ["l1": "r1"]).isComplete(for: set))
    }

    @Test func choicesComparedByID() {
        let q = question("q", family: "a")
        #expect(BankAnswer(optionID: "o1").isCorrect(for: q))
        #expect(!BankAnswer(optionID: "o2").isCorrect(for: q))
    }

    @Test func essayPassNeedsTwoThirdsAndNoZero() {
        let rubric: [[String: String]] = ["a", "b", "c"].map { ["id": $0, "title": $0, "full": "", "partial": "", "none": ""] }
        let json: [String: Any] = ["minWords": 150, "maxWords": 250, "revisionsBeforeCompletion": 3, "rubric": rubric, "prompts": []]
        let essay = try! JSONDecoder().decode(PathEssay.self, from: JSONSerialization.data(withJSONObject: json))
        func scored(_ points: [Int]) -> ScoredEssay {
            ScoredEssay(criteria: zip(["a", "b", "c"], points).map { .init(id: $0, points: $1, evidence: "") }, suggestion: "")
        }
        #expect(essay.pointsToPass == 4)
        #expect(scored([2, 1, 1]).passes(essay))
        #expect(!scored([2, 2, 0]).passes(essay))
        #expect(!scored([1, 1, 1]).passes(essay))
    }

    @Test func groupsCoverEveryModule() {
        let a = (1...10).map { question("a\($0)", family: "fa\($0)") }
        let b = (1...2).map { question("b\($0)", family: "fb\($0)") }
        let c = (1...2).map { question("c\($0)", family: "fc\($0)") }
        let pool = a + b + c
        for seed in 1...20 {
            var rng = Seeded(state: UInt64(seed))
            let spec = quiz(pool, count: 6, pass: 5, groups: [a.map(\.id), b.map(\.id), c.map(\.id)])
            let ids = Set(QuizSampler.draw(spec, from: pool, recent: [], using: &rng).map(\.id))
            #expect(ids.count == 6)
            #expect(!ids.isDisjoint(with: b.map(\.id)))
            #expect(!ids.isDisjoint(with: c.map(\.id)))
        }
    }

    @Test func pathThresholdsReplaceFixedOnes() {
        let thresholds: [ScholarRank: Int] = [.apprentice: 2_920, .investigator: 3_920, .scholar: 5_420, .sage: 7_420]
        let lookup: (ScholarRank) -> Int = { thresholds[$0] ?? 0 }
        #expect(ScholarRules.rank(xp: 2_919, completedStages: 1, hasCompletedAnItem: true, stored: nil, threshold: lookup) == .novice)
        #expect(ScholarRules.rank(xp: 2_920, completedStages: 1, hasCompletedAnItem: true, stored: nil, threshold: lookup) == .apprentice)
        #expect(ScholarRules.rank(xp: 3_920, completedStages: 2, hasCompletedAnItem: true, stored: nil, threshold: lookup) == .investigator)
        // A rank earned under the old rules is never taken away.
        #expect(ScholarRules.rank(xp: 600, completedStages: 1, hasCompletedAnItem: true, stored: .apprentice, threshold: lookup) == .apprentice)
    }

    @Test func v2ItemXP() {
        #expect(ScholarRules.xp(for: .article) == 50)
        #expect(ScholarRules.xp(for: .quiz) == 80)
        #expect(ScholarRules.xp(for: .essay) == 60)
    }
}
