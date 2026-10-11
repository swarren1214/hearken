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
