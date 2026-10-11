import Foundation

// A subject's Scholar Path, loaded from Resources/Content/path-<subjectID>.json.
// The JSON is generated from the course's Markdown by scripts/course_md_to_json.py and
// checked by scripts/validate_path.py. IDs are permanent: XP is keyed to them.
//
// XP is never stored in the file. It comes from each item's kind (ScholarRules.xp(for:)),
// so a path can't inflate its own rewards.
//
// Version 2 modules (scripts/module_v2_to_path.py) add item kinds that are completed by
// passing a check rather than by writing a response: an article with section checks, a reading
// with a quiz, a matching practice set, a module quiz and a rubric-scored essay. Their
// objective questions live in bank-<moduleID>.json (QuestionBank).

struct ScholarPathFile: Decodable {
    let subjectID: String
    let ruleVersion: Int
    let title: String
    let summary: String
    let stages: [PathStage]
    let capstone: PathCapstone?
    let questions: [PathQuestion]
}

struct PathStage: Decodable, Identifiable, Hashable {
    let number: Int
    let title: String
    let outcome: String
    /// Unpublished stages are hidden, along with the ranks they gate.
    let published: Bool
    let courses: [PathCourse]
    let advancementCheck: PathAssessment?

    var id: Int { number }
}

struct PathCourse: Decodable, Identifiable, Hashable {
    let id: String
    let number: Int
    let title: String
    let summary: String
    let milestone: String?
    let objectives: [String]
    let modules: [PathModule]
    let checkpoint: PathAssessment?
    let videos: [PathItem]
    let books: [PathResource]

    /// Every item in the course, in order: module items, then the course's videos.
    var allItems: [PathItem] { modules.flatMap(\.items) + videos }
    var requiredItems: [PathItem] { allItems.filter(\.required) }
    var optionalItems: [PathItem] { allItems.filter { !$0.required } }

    /// XP the required items and checkpoint can earn.
    var requiredXP: Int {
        requiredItems.reduce(0) { $0 + $1.xp } + (checkpoint?.xp ?? 0)
    }

    var minutes: Int { allItems.filter(\.required).reduce(0) { $0 + ($1.minutes ?? 0) } }
}

struct PathModule: Decodable, Identifiable, Hashable {
    let id: String
    let number: String
    let title: String
    let objectives: [String]
    let keyPoints: [String]
    let items: [PathItem]
}

struct PathItem: Decodable, Identifiable, Hashable {
    enum Kind: String, Decodable {
        /// An original Hearken article, read in the app.
        case lesson
        /// Scripture (opens in the reader) or a primary or institutional source (opens in Safari).
        case reading
        /// An embedded video with a reading alternative.
        case video
        /// An application exercise: success criteria (v1), or a matching set (v2, `questionID`).
        case practice
        /// v2: a long-form original article in sections, each followed by check questions.
        case article
        /// v2: the module quiz.
        case quiz
        /// v2: a short essay scored against a rubric.
        case essay
    }

    let id: String
    let kind: Kind
    let title: String
    let required: Bool
    let minutes: Int?
    /// Lesson text (Markdown).
    let body: String?
    /// What the learner writes to complete it.
    let prompt: String
    let successCriteria: String?
    /// What a good response includes (for the on-device reviewer; not shown to the learner).
    let guide: String?
    /// The course's completion rule for this item (for the reviewer).
    let completion: String?
    let passage: PathPassage?
    let source: PathResource?
    let video: PathVideo?
    /// For a video: the lesson item to read instead.
    let alternativeItemID: String?
    /// Alternative formats share one award.
    let equivalenceGroup: String?

    // v2 fields
    /// Article: the check questions after each section.
    let sectionChecks: [PathSectionCheck]?
    /// Reading: several passages read together.
    let passages: [PathPassage]?
    /// Reading: what to look for, shown before reading.
    let focusQuestions: [String]?
    /// Reading quiz or module quiz.
    let quiz: PathQuiz?
    /// Practice: the matching set to work.
    let questionID: String?
    /// Essay prompts and rubric.
    let essay: PathEssay?

    /// Every passage this item assigns.
    var allPassages: [PathPassage] { passages ?? passage.map { [$0] } ?? [] }

    /// Completed by passing a check (v2) rather than by writing a response (v1).
    var isCheckCompleted: Bool {
        switch kind {
        case .article, .quiz, .essay: true
        case .reading: quiz != nil
        case .practice: questionID != nil
        case .lesson, .video: false
        }
    }

    /// The key XP is awarded under: the equivalence group when there is one.
    var awardKey: String { equivalenceGroup ?? id }
    var xp: Int { ScholarRules.xp(for: self) }

    var kindName: String {
        switch kind {
        case .lesson: "Lesson"
        case .reading: passage != nil ? "Scripture reading" : "Reading"
        case .video: "Video"
        case .practice: "Practice"
        case .article: "Article"
        case .quiz: "Module quiz"
        case .essay: "Essay"
        }
    }

    var symbol: String {
        switch kind {
        case .lesson: "doc.text"
        case .reading: passage != nil ? "book" : "safari"
        case .video: "play.rectangle"
        case .practice: questionID != nil ? "square.on.square.dashed" : "pencil.and.list.clipboard"
        case .article: "doc.richtext"
        case .quiz: "checklist"
        case .essay: "square.and.pencil"
        }
    }
}

/// Article check questions shown after one section.
struct PathSectionCheck: Decodable, Hashable {
    /// The section's heading, as in the article's Markdown.
    let section: String
    let questionIDs: [String]
}

/// A quiz drawn from the question bank.
struct PathQuiz: Decodable, Hashable {
    let questionPool: [String]
    let questionCount: Int
    /// Correct answers needed to pass.
    let passCount: Int
    let maxTrueFalse: Int?
    let maxMatching: Int?
    /// For checkpoints and exams: the pool split by module, so every module is covered.
    let groups: [[String]]?
}

struct PathEssay: Decodable, Hashable {
    struct Criterion: Decodable, Hashable, Identifiable {
        let id: String
        let title: String
        let full: String
        let partial: String
        let none: String
    }

    struct Prompt: Decodable, Hashable, Identifiable {
        let id: String
        let prompt: String
        /// For the scorer, never shown to the learner.
        let guide: String
    }

    let minWords: Int
    let maxWords: Int
    /// After this many scored drafts the essay completes even without a pass.
    let revisionsBeforeCompletion: Int
    let rubric: [Criterion]
    let prompts: [Prompt]

    /// Passing: at least two-thirds of the points, with no criterion at zero.
    var pointsToPass: Int { Int((Double(rubric.count * 2) * 2 / 3).rounded(.up)) }
}

struct PathPassage: Decodable, Hashable {
    let chapterID: String
    let from: Int
    let to: Int
}

struct PathResource: Decodable, Hashable {
    let title: String
    let url: URL?
    let note: String?
}

struct PathVideo: Decodable, Hashable {
    let provider: String
    let videoID: String
    let speaker: String?
    let transcriptURL: URL?
}

struct PathAssessment: Decodable, Hashable {
    let id: String
    /// v1: short-answer and multiple-choice questions in the path file.
    let questionPool: [String]
    let questionCount: Int
    let passPercent: Int
    /// v2: objective questions drawn from the module banks, plus an essay. Both must pass.
    let quiz: PathQuiz?
    let essay: PathEssay?

    var isV2: Bool { quiz != nil }

    /// True once there are enough questions to give the check.
    var isReady: Bool { !questionPool.isEmpty || quiz != nil }

    /// XP a checkpoint pays once: 100 for a v1 checkpoint, ten per question for a v2 one
    /// (200 for a 20-question Stage 1 checkpoint). Advancement checks pay none.
    var xp: Int { quiz.map { $0.questionCount * 10 } ?? ScholarRules.checkpointXP }
}

/// A check question: multiple choice (graded instantly) or short answer (scored 0–2 by the
/// on-device model against the answer guide). Both are worth 2 points.
struct PathQuestion: Decodable, Identifiable, Hashable {
    enum Kind: String, Decodable {
        case multipleChoice, shortAnswer
    }

    let id: String
    let kind: Kind
    let prompt: String
    let options: [String]?
    let answer: Int?
    /// What a full-credit short answer includes (shown after scoring).
    let guide: String?
    let explanation: String?
    let reference: String?

    static let maxPoints = 2
}

struct PathCapstone: Decodable, Hashable {
    let id: String
    let title: String
    let summary: String
    let requirements: [String]
    let rubric: [String]
}

// MARK: - Catalog

/// Every bundled path, by subject ID.
@MainActor
final class PathCatalog {
    static let shared = PathCatalog()

    let paths: [String: ScholarPathFile]

    init(bundle: Bundle = .main) {
        var found: [String: ScholarPathFile] = [:]
        // File-system-synchronized groups copy resources to the bundle root.
        let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        for url in urls where url.lastPathComponent.hasPrefix("path-") {
            do {
                let file = try JSONDecoder().decode(ScholarPathFile.self, from: Data(contentsOf: url))
                found[file.subjectID] = file
            } catch {
                assertionFailure("Could not decode \(url.lastPathComponent): \(error)")
            }
        }
        paths = found
    }

    func path(for subjectID: String) -> ScholarPathFile? { paths[subjectID] }
}

extension ScholarPathFile {
    var publishedStages: [PathStage] { stages.filter(\.published) }

    /// The highest rank this path can award as published.
    var highestAttainableRank: ScholarRank {
        let stagesReady = publishedStages.count
        return ScholarRank(rawValue: min(stagesReady + 1, ScholarRank.sage.rawValue)) ?? .novice
    }

    func question(_ id: String) -> PathQuestion? { questions.first { $0.id == id } }

    func item(_ id: String) -> PathItem? {
        for stage in stages { for course in stage.courses { if let item = course.allItems.first(where: { $0.id == id }) { return item } } }
        return nil
    }

    func course(_ id: String) -> PathCourse? { stages.flatMap(\.courses).first { $0.id == id } }

    /// A course checkpoint or stage advancement check by ID.
    func assessment(_ id: String) -> PathAssessment? {
        for stage in stages {
            if stage.advancementCheck?.id == id { return stage.advancementCheck }
            if let checkpoint = stage.courses.compactMap(\.checkpoint).first(where: { $0.id == id }) { return checkpoint }
        }
        return nil
    }

    /// XP the stage's required work pays: its courses' required items and checkpoints, and
    /// the capstone in Stage 4.
    func requiredXP(_ stage: PathStage) -> Int {
        stage.courses.reduce(0) { $0 + $1.requiredXP } + (stage.number == 4 && capstone != nil ? ScholarRules.capstoneXP : 0)
    }

    /// A rank's XP threshold (rules version 2): all the required XP through the stages it
    /// needs, so a badge means its stages' required work is done, however long the path's
    /// courses are. A path whose stages are missing falls back to the fixed thresholds.
    func xpThreshold(for rank: ScholarRank) -> Int {
        guard rank > .novice else { return 0 }
        let needed = stages.filter { $0.number <= rank.requiredStages }
        guard needed.count == rank.requiredStages else { return rank.xpThreshold }
        return needed.reduce(0) { $0 + requiredXP($1) }
    }

    func stage(containing courseID: String) -> PathStage? { stages.first { $0.courses.contains { $0.id == courseID } } }
}
