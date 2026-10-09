import Foundation
import SwiftData

/// A read-only view of the user's study records, built from SwiftData queries in a view.
struct MasterySnapshot {
    let reviews: [String: ItemReview]
    let completedChapters: Set<String>
    let now: Date

    init(reviews: [ItemReview], progress: [ReadingProgress], now: Date = .now) {
        self.reviews = Dictionary(reviews.map { ($0.questionID, $0) }, uniquingKeysWith: { first, _ in first })
        self.completedChapters = Set(progress.filter { $0.completedAt != nil }.map(\.chapterID))
        self.now = now
    }

    func recall(for questionID: String) -> Double {
        guard let review = reviews[questionID] else { return 0 }
        return MasteryMath.recall(lastReviewed: review.lastReviewed, stability: review.stability, now: now)
    }
}

/// Computes mastery from content + records, and records answers.
/// Mastery is always computed, never stored, so devices can't disagree.
struct MasteryService {
    var config = MasteryConfig.standard

    // MARK: Computing

    func unitMastery(_ unit: StudyUnit, content: ContentService, snapshot: MasterySnapshot) -> Double {
        let recalls = content.questions(forUnit: unit.id).map { snapshot.recall(for: $0.id) }
        let reading: Double? = unit.readingChapterIDs.isEmpty
            ? nil
            : Double(unit.readingChapterIDs.filter { snapshot.completedChapters.contains($0) }.count) / Double(unit.readingChapterIDs.count)
        return MasteryMath.unitMastery(recalls: recalls, readingFraction: reading, config: config)
    }

    func subjectMastery(_ subject: Subject, content: ContentService, snapshot: MasterySnapshot) -> Double {
        let units = subject.units.map { unit in
            (mastery: unitMastery(unit, content: content, snapshot: snapshot),
             weight: max(content.questions(forUnit: unit.id).count, unit.readingChapterIDs.count))
        }
        return MasteryMath.subjectMastery(units: units)
    }

    /// Questions most in need of review: lowest predicted recall first, unseen items included.
    func dueQuestions(from questions: [Question], snapshot: MasterySnapshot, limit: Int) -> [Question] {
        let ranked: [(question: Question, recall: Double)] = questions.map { question in
            (question: question, recall: snapshot.recall(for: question.id))
        }
        let due = ranked.filter { $0.recall < 0.9 }
        let sorted = due.sorted { lhs, rhs in
            if lhs.recall != rhs.recall {
                return lhs.recall < rhs.recall
            }
            return lhs.question.id < rhs.question.id
        }
        return sorted.prefix(limit).map(\.question)
    }

    /// Today's challenge: the five weakest questions, in a stable order for the whole day.
    func dailyChallenge(content: ContentService, snapshot: MasterySnapshot, count: Int = 5) -> [Question] {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: snapshot.now) ?? 0
        let weakest = dueQuestions(from: content.questions, snapshot: snapshot, limit: count * 2)
        let pool = weakest.isEmpty ? content.questions : weakest
        return Array(pool.sorted { stableHash($0.id, day) < stableHash($1.id, day) }.prefix(count))
    }

    // MARK: Recording

    /// Updates the item's spaced repetition state and awards XP for a correct answer.
    func record(questionID: String, correct: Bool, in context: ModelContext, now: Date = .now) {
        let id = questionID
        let descriptor = FetchDescriptor<ItemReview>(predicate: #Predicate { $0.questionID == id })
        let review: ItemReview
        if let existing = try? context.fetch(descriptor).first {
            review = existing
        } else {
            review = ItemReview(questionID: questionID)
            context.insert(review)
        }
        review.stability = MasteryMath.nextStability(current: review.stability, correct: correct, config: config)
        review.lastReviewed = now
        review.reps += 1
        review.lastCorrect = correct
        if !correct { review.lapses += 1 }

        if correct {
            context.insert(XPEvent(amount: config.xpPerCorrect, reason: "correct"))
        }
    }

    func award(_ amount: Int, reason: String, in context: ModelContext) {
        context.insert(XPEvent(amount: amount, reason: reason))
    }

    // A small deterministic hash; String.hashValue changes between launches.
    private func stableHash(_ text: String, _ seed: Int) -> Int {
        text.unicodeScalars.reduce(seed &* 31) { ($0 &* 31) &+ Int($1.value) }
    }
}
