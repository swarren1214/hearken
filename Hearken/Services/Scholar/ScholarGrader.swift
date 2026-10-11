import Foundation
import FoundationModels
import OSLog

// On-device scoring for the Scholar Path, with Apple's language model:
// - short-answer check questions are scored 0–2 against the course's answer guide;
// - written responses that complete a learning item get a light review.
// Scores are labeled as AI-scored in the app. When the model isn't available, short answers
// can't be scored (the check says so), and item responses are accepted on length alone.

@Generable
struct ShortAnswerScore {
    @Guide(description: "0 if the answer is missing or incorrect, 1 if it is partial or unsupported, 2 if it is accurate and shows context", .range(0...2))
    var points: Int

    @Guide(description: "One or two plain, encouraging sentences: what the answer got right and what a full answer adds. Never comment on the learner's beliefs.")
    var feedback: String
}

@Generable
struct ResponseReview {
    @Guide(description: "True if the response is a genuine, relevant attempt at the prompt that shows the reading or lesson was understood. It need not be complete or perfect. Spelling, style and the learner's beliefs do not matter.")
    var meetsPrompt: Bool

    @Guide(description: "One short, encouraging sentence. If it doesn't meet the prompt, say what is missing.")
    var feedback: String
}

@Generable
struct CriterionScore {
    @Guide(description: "The criterion's id, exactly as given")
    var criterionID: String

    @Guide(description: "0, 1 or 2, following that criterion's descriptions", .range(0...2))
    var points: Int

    @Guide(description: "The short phrase or sentence from the essay this score rests on, quoted exactly; empty if there is none")
    var evidence: String
}

@Generable
struct EssayScore {
    @Guide(description: "One score for every rubric criterion, in the order given")
    var criteria: [CriterionScore]

    @Guide(description: "One concrete, kind suggestion for the next draft: the single change that would raise the score most. Never comment on the learner's beliefs.")
    var suggestion: String
}

/// An essay's result: points per criterion, in rubric order.
struct ScoredEssay: Codable, Hashable {
    struct Criterion: Codable, Hashable {
        let id: String
        let points: Int
        let evidence: String
    }

    let criteria: [Criterion]
    let suggestion: String

    var total: Int { criteria.reduce(0) { $0 + $1.points } }

    /// Passing: the essay's points to pass, with no criterion at zero.
    func passes(_ essay: PathEssay) -> Bool { total >= essay.pointsToPass && !criteria.contains { $0.points == 0 } }
}

/// A short answer's score.
struct ScoredAnswer: Codable, Hashable {
    let points: Int
    let feedback: String
}

@MainActor
enum ScholarGrader {
    private static let log = Logger(subsystem: "com.stephenwarren.hearken", category: "scholar")

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static let instructions = """
    You score answers in Hearken, a study app with structured courses on religious subjects. \
    You assess understanding, use of evidence and reasoning only.

    Rules:
    - Score against the answer guide provided. Do not require the learner's wording to match it.
    - Never reward or penalize belief, testimony, or religious commitment. A learner who explains a teaching \
    accurately without saying they believe it earns full credit.
    - Be fair and consistent. When an answer falls between two scores, choose the lower one and say what is missing.
    - Keep feedback brief, specific and kind.
    """

    /// Scores one short answer 0–2. Throws when the model can't respond.
    static func score(question: PathQuestion, answer: String) async throws -> ScoredAnswer {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ScoredAnswer(points: 0, feedback: "No answer was given.") }
        let session = LanguageModelSession(instructions: instructions)
        let prompt = """
        Question: \(question.prompt)

        Answer guide (what a full-credit answer includes): \(question.guide ?? question.explanation ?? "An accurate, sourced answer.")

        Learner's answer: \(trimmed)

        Score the learner's answer.
        """
        let response = try await session.respond(to: prompt, generating: ShortAnswerScore.self, options: GenerationOptions(temperature: 0))
        let content = response.content
        return ScoredAnswer(points: min(max(content.points, 0), PathQuestion.maxPoints), feedback: content.feedback)
    }

    /// Scores an essay against its rubric. `sources` is the text of the module's assigned
    /// passages, so accuracy is judged against what they actually say. Throws when the model
    /// can't respond.
    static func score(essay: PathEssay, prompt: PathEssay.Prompt, text: String, sources: String) async throws -> ScoredEssay {
        let session = LanguageModelSession(instructions: instructions)
        let rubric = essay.rubric.map { "- id: \($0.id) (\($0.title)). 2 points: \($0.full). 1 point: \($0.partial). 0 points: \($0.none)." }.joined(separator: "\n")
        var request = """
        Essay prompt: \(prompt.prompt)

        What a strong essay includes (answer guide): \(prompt.guide)

        Rubric, one score per criterion:
        \(rubric)
        """
        if !sources.isEmpty { request += "\n\nThe assigned sources, for checking accuracy:\n\(sources)" }
        request += "\n\nLearner's essay:\n\(text)\n\nScore the essay on every criterion."
        let response = try await session.respond(to: request, generating: EssayScore.self, options: GenerationOptions(temperature: 0))
        let content = response.content
        // Match scores to the rubric by id, falling back to order; a criterion the model left out scores 1.
        let criteria = essay.rubric.enumerated().map { index, criterion in
            let score = content.criteria.first { $0.criterionID == criterion.id } ?? (index < content.criteria.count ? content.criteria[index] : nil)
            return ScoredEssay.Criterion(id: criterion.id, points: min(max(score?.points ?? 1, 0), 2), evidence: score?.evidence ?? "")
        }
        return ScoredEssay(criteria: criteria, suggestion: content.suggestion)
    }

    /// A light review of the written response that completes a learning item.
    /// Returns nil when the model isn't available (the response is then accepted on length).
    static func review(item: PathItem, response: String) async -> ResponseReview? {
        guard isAvailable else { return nil }
        let session = LanguageModelSession(instructions: instructions)
        var prompt = "Learning item: \(item.title)\n\nPrompt the learner answered: \(item.prompt)"
        if let criteria = item.successCriteria { prompt += "\n\nSuccess criteria: \(criteria)" }
        if let guide = item.guide { prompt += "\n\nWhat a good response includes: \(guide)" }
        if let completion = item.completion { prompt += "\n\nCompletion rule: \(completion)" }
        prompt += "\n\nLearner's response: \(response)\n\nDoes the response meet the prompt?"
        do {
            return try await session.respond(to: prompt, generating: ResponseReview.self, options: GenerationOptions(temperature: 0)).content
        } catch {
            log.error("response review failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
