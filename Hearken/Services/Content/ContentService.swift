import Foundation
import Observation

/// Loads the bundled content and answers lookups.
///
/// v1 reads JSON from Resources/Content. The plan is to compile this into a SQLite store
/// with full-text search at build time once the full standard works are imported;
/// keep callers on this API so that swap stays invisible to views.
@Observable
final class ContentService {
    let volumes: [Volume]
    let subjects: [Subject]
    let questions: [Question]

    private let chapters: [String: Chapter]
    private let bookTitles: [String: String]
    private let questionsByID: [String: Question]

    init(bundle: Bundle = .main) {
        let library = Self.load(ScriptureLibrary.self, named: "scripture", in: bundle)
        let catalog = Self.load(SubjectCatalog.self, named: "subjects", in: bundle)

        let loadedVolumes = library?.volumes ?? []
        let loadedQuestions = catalog?.questions ?? []

        var chapterIndex: [String: Chapter] = [:]
        var titleIndex: [String: String] = [:]
        for volume in loadedVolumes {
            for book in volume.books {
                for chapter in book.chapters {
                    chapterIndex[chapter.id] = chapter
                    titleIndex[chapter.id] = book.title
                }
            }
        }

        volumes = loadedVolumes
        subjects = catalog?.subjects ?? []
        questions = loadedQuestions
        chapters = chapterIndex
        bookTitles = titleIndex
        questionsByID = Dictionary(loadedQuestions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: Scripture

    var defaultChapterID: String { "bofm.alma.32" }

    func chapter(_ id: String) -> Chapter? { chapters[id] }

    /// "Alma 32"
    func title(forChapter id: String) -> String {
        guard let chapter = chapters[id], let book = bookTitles[id] else { return "" }
        return "\(book) \(chapter.number)"
    }

    func bookTitle(forChapter id: String) -> String { bookTitles[id] ?? "" }

    /// "Alma 32:27"
    func reference(chapterID: String, verse: Int) -> String {
        "\(title(forChapter: chapterID)):\(verse)"
    }

    func search(_ text: String, limit: Int = 50) -> [VerseHit] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return [] }
        var hits: [VerseHit] = []
        for volume in volumes {
            for book in volume.books {
                for chapter in book.chapters {
                    for verse in chapter.verses where verse.text.localizedCaseInsensitiveContains(query) {
                        hits.append(VerseHit(chapterID: chapter.id, reference: "\(book.title) \(chapter.number):\(verse.number)", verse: verse))
                        if hits.count >= limit { return hits }
                    }
                }
            }
        }
        return hits
    }

    // MARK: Subjects

    func subject(_ id: String) -> Subject? { subjects.first { $0.id == id } }

    func question(_ id: String) -> Question? { questionsByID[id] }

    func questions(forSubject id: String) -> [Question] { questions.filter { $0.subjectID == id } }

    func questions(forUnit id: String) -> [Question] { questions.filter { $0.unitID == id } }

    // MARK: Loading

    private static func load<T: Decodable>(_ type: T.Type, named name: String, in bundle: Bundle) -> T? {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            assertionFailure("Missing \(name).json in the app bundle")
            return nil
        }
        do {
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
        } catch {
            assertionFailure("Could not decode \(name).json: \(error)")
            return nil
        }
    }
}
