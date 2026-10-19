import Foundation
import FoundationModels
import OSLog

/// Suggested weekly questions for a group's chapters. Written on this device by Apple
/// Intelligence when it's available (nothing leaves the phone); otherwise three questions that
/// work for any reading.
@MainActor
enum QuestionSuggester {
    struct Suggestion: Identifiable, Hashable {
        let id = UUID()
        let text: String
        /// "Alma 32:28–43", or the week's range.
        let reference: String
    }

    private static let instructions = """
    You write weekly discussion questions for scripture study groups in Hearken, used by members of The Church of Jesus Christ \
    of Latter-day Saints, often families with teenagers. Questions invite people to share experiences and feelings, not facts.

    Rules:
    - Stay with the chapters given. Never invent quotes, verse numbers, names or events.
    - Plain, warm language a teenager could answer. One sentence, or two short ones.
    - No doctrine claims, no advice, nothing that asks people to share private struggles in detail.
    """

    static var canGenerate: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Suggestions for the week, given its chapters ("Alma 32", "Alma 33"…) and their headings.
    static func suggestions(range: String, chapters: [(title: String, heading: String?)]) async -> [Suggestion] {
        guard canGenerate, !chapters.isEmpty else { return fallback(range: range) }
        let list = chapters.prefix(10).map { chapter in
            chapter.heading.map { "\(chapter.title): \($0)" } ?? chapter.title
        }.joined(separator: "\n")
        let prompt = "This week's chapters (\(range)):\n\(list)\n\nWrite three discussion questions."
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt, generating: GroupQuestionIdeas.self,
                                                     options: GenerationOptions(temperature: 0.7))
            let result = response.content.questions
                .map { Suggestion(text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines), reference: $0.reference) }
                .filter { !$0.text.isEmpty && $0.text.count <= 300 }
            return result.isEmpty ? fallback(range: range) : Array(result.prefix(3))
        } catch {
            Logger(subsystem: "com.stephenwarren.hearken", category: "groups")
                .error("question suggestions failed: \(String(describing: error), privacy: .public)")
            return fallback(range: range)
        }
    }

    static func fallback(range: String) -> [Suggestion] {
        [
            Suggestion(text: "What verse from this week's reading stayed with you, and why?", reference: range),
            Suggestion(text: "Where did you see something from this week's chapters show up in your own life?", reference: range),
            Suggestion(text: "Who in this week's reading would you most like to sit down and talk with? What would you ask?", reference: range),
        ]
    }
}

/// What Apple Intelligence returns for `QuestionSuggester`.
@Generable
nonisolated struct GroupQuestionIdeas {
    @Guide(description: "Three discussion questions for a family or study group that read these chapters this week.", .maximumCount(3))
    var questions: [GroupQuestionIdea]
}

@Generable
nonisolated struct GroupQuestionIdea {
    @Guide(description: "One warm, open question, under 160 characters, that invites a personal answer about living what the chapters teach. It may briefly mention a story, person or image from the chapters. Never yes-or-no, never a quiz question.")
    var text: String
    @Guide(description: "The chapter, or chapter and verses, the question draws on, written like \"Alma 32\" or \"Alma 32:28–43\". Only use chapters from the list given.")
    var reference: String
}
