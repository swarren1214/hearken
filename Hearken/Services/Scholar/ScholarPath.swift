import Foundation

// A subject's Scholar Path, loaded from Resources/Content/path-<subjectID>.json.
// The JSON is generated from the course's Markdown by scripts/course_md_to_json.py and
// checked by scripts/validate_path.py. IDs are permanent: XP is keyed to them.
//
// XP is never stored in the file. It comes from each item's kind (ScholarRules.xp(for:)),
// so a path can't inflate its own rewards.

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
        requiredItems.reduce(0) { $0 + $1.xp } + (checkpoint == nil ? 0 : ScholarRules.checkpointXP)
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
        /// An application exercise with success criteria.
        case practice
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

    /// The key XP is awarded under: the equivalence group when there is one.
    var awardKey: String { equivalenceGroup ?? id }
    var xp: Int { ScholarRules.xp(for: kind) }

    var kindName: String {
        switch kind {
        case .lesson: "Lesson"
        case .reading: passage != nil ? "Scripture reading" : "Reading"
        case .video: "Video"
        case .practice: "Practice"
        }
    }

    var symbol: String {
        switch kind {
        case .lesson: "doc.text"
        case .reading: passage != nil ? "book" : "safari"
        case .video: "play.rectangle"
        case .practice: "pencil.and.list.clipboard"
        }
    }
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
    let questionPool: [String]
    let questionCount: Int
    let passPercent: Int

    /// True once there are enough questions to give the check.
    var isReady: Bool { !questionPool.isEmpty }
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

    func stage(containing courseID: String) -> PathStage? { stages.first { $0.courses.contains { $0.id == courseID } } }
}
