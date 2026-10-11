import Foundation

// Objective questions for the Scholar Path's v2 modules: multiple choice, true/false and
// matching. Loaded from Resources/Content/bank-<moduleID>.json, which use the assessment-design
// bank format unchanged (stable question, option and pair IDs; answers are compared by ID,
// never by display position).

struct BankFile: Decodable {
    let moduleID: String
    let questions: [BankQuestion]
}

struct BankQuestion: Decodable, Identifiable, Hashable {
    enum Kind: String, Decodable {
        case multipleChoice = "multiple_choice"
        case trueFalse = "true_false"
        case matching
    }

    struct Option: Decodable, Hashable, Identifiable {
        let id: String
        let text: String
    }

    struct Pair: Decodable, Hashable {
        let leftID: String
        let rightID: String
    }

    let id: String
    let revision: Int
    let type: Kind
    let prompt: String
    /// Matching sets have a short title and instructions.
    let title: String?
    let instructions: String?
    let options: [Option]?
    let correctOptionID: String?
    let leftItems: [Option]?
    let rightItems: [Option]?
    let correctPairs: [Pair]?
    let explanation: String
    let questionFamilyID: String
    let difficulty: String
    /// Questions a matching set must not appear alongside.
    let overlapsWithQuestionIDs: [String]?

    var kindName: String {
        switch type {
        case .multipleChoice: "Multiple choice"
        case .trueFalse: "True or false"
        case .matching: "Matching"
        }
    }

    /// The right item each left item belongs with.
    var answerKey: [String: String] {
        Dictionary((correctPairs ?? []).map { ($0.leftID, $0.rightID) }, uniquingKeysWith: { first, _ in first })
    }
}

/// Every bundled question, by ID.
@MainActor
final class QuestionBank {
    static let shared = QuestionBank()

    let questions: [String: BankQuestion]

    init(bundle: Bundle = .main) {
        var found: [String: BankQuestion] = [:]
        let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        for url in urls where url.lastPathComponent.hasPrefix("bank-") {
            do {
                let file = try JSONDecoder().decode(BankFile.self, from: Data(contentsOf: url))
                for question in file.questions { found[question.id] = question }
            } catch {
                assertionFailure("Could not decode \(url.lastPathComponent): \(error)")
            }
        }
        questions = found
    }

    func question(_ id: String) -> BankQuestion? { questions[id] }
}

// MARK: - Answers

/// A learner's answer to one objective question.
struct BankAnswer: Codable, Hashable {
    /// Multiple choice and true/false: the chosen option's ID.
    var optionID: String?
    /// Matching: right item ID chosen for each left item ID.
    var pairs: [String: String] = [:]

    func isComplete(for question: BankQuestion) -> Bool {
        switch question.type {
        case .multipleChoice, .trueFalse: optionID != nil
        case .matching: (question.leftItems ?? []).allSatisfy { pairs[$0.id] != nil }
        }
    }

    /// One point, all or nothing: every pair right for a matching set.
    func isCorrect(for question: BankQuestion) -> Bool {
        switch question.type {
        case .multipleChoice, .trueFalse: optionID != nil && optionID == question.correctOptionID
        case .matching: !question.answerKey.isEmpty && question.answerKey == pairs
        }
    }
}

// MARK: - Drawing a quiz

enum QuizSampler {
    /// Draws up to `quiz.questionCount` questions from its pool:
    /// - at most one question per question family;
    /// - never a matching set alongside a question it overlaps with;
    /// - no more than `maxTrueFalse` true/false items or `maxMatching` matching sets;
    /// - questions not in `recent` first, so a retake sees fresh ones where the pool allows.
    @MainActor
    static func draw(_ quiz: PathQuiz, bank: QuestionBank = .shared, recent: Set<String> = []) -> [BankQuestion] {
        var generator = SystemRandomNumberGenerator()
        return draw(quiz, from: quiz.questionPool.compactMap { bank.question($0) }, recent: recent, using: &generator)
    }

    static func draw<G: RandomNumberGenerator>(_ quiz: PathQuiz, from pool: [BankQuestion], recent: Set<String>, using generator: inout G) -> [BankQuestion] {
        func ordered(_ questions: [BankQuestion]) -> [BankQuestion] {
            let shuffled = questions.shuffled(using: &generator)
            return shuffled.filter { !recent.contains($0.id) } + shuffled.filter { recent.contains($0.id) }
        }
        var chosen: [BankQuestion] = []
        var families: Set<String> = []
        var trueFalse = 0, matching = 0
        func take(_ question: BankQuestion) -> Bool {
            guard chosen.count < quiz.questionCount, !families.contains(question.questionFamilyID) else { return false }
            if question.type == .trueFalse, trueFalse >= (quiz.maxTrueFalse ?? .max) { return false }
            if question.type == .matching, matching >= (quiz.maxMatching ?? .max) { return false }
            let overlaps = chosen.contains { other in
                (other.overlapsWithQuestionIDs ?? []).contains(question.id) || (question.overlapsWithQuestionIDs ?? []).contains(other.id)
            }
            if overlaps { return false }
            chosen.append(question)
            families.insert(question.questionFamilyID)
            if question.type == .trueFalse { trueFalse += 1 }
            if question.type == .matching { matching += 1 }
            return true
        }

        if let groups = quiz.groups, !groups.isEmpty {
            // Round-robin across groups (modules), so every one is covered before any repeats.
            let byID = Dictionary(pool.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var queues = groups.map { ordered($0.compactMap { byID[$0] }) }
            var progressed = true
            while chosen.count < quiz.questionCount && progressed {
                progressed = false
                for g in queues.indices where chosen.count < quiz.questionCount {
                    while let next = queues[g].first {
                        queues[g].removeFirst()
                        if take(next) { progressed = true; break }
                    }
                }
            }
            return chosen.shuffled(using: &generator)
        }

        for question in ordered(pool) where chosen.count < quiz.questionCount {
            _ = take(question)
        }
        return chosen
    }

    /// The pass mark for a quiz that drew `drawn` questions: the quiz's own mark, scaled down
    /// (rounding up) only if the pool couldn't fill it.
    static func passMark(_ quiz: PathQuiz, drawn: Int) -> Int {
        guard drawn < quiz.questionCount, quiz.questionCount > 0 else { return quiz.passCount }
        return Int((Double(quiz.passCount * drawn) / Double(quiz.questionCount)).rounded(.up))
    }
}
