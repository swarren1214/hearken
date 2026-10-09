import Foundation
import Observation

/// Loads the bundled content and answers lookups.
///
/// Scripture ships as one JSON file per volume and each volume loads the first time
/// something inside it is asked for. The plan is to compile this into a SQLite store
/// with full-text search at build time; keep callers on this API so that swap stays
/// invisible to views.
@Observable
final class ContentService {
    static let volumeIDs = ["ot", "nt", "bofm", "dc-testament", "pgp"]

    let subjects: [Subject]
    let questions: [Question]

    private let bundle: Bundle
    private let questionsByID: [String: Question]

    // Caches fill lazily and the content never changes, so views needn't observe them.
    @ObservationIgnored private var loadedVolumes: [String: Volume] = [:]
    @ObservationIgnored private var chapters: [String: Chapter] = [:]
    @ObservationIgnored private var bookTitles: [String: String] = [:]

    init(bundle: Bundle = .main) {
        let catalog = Self.load(SubjectCatalog.self, named: "subjects", in: bundle)
        let loadedQuestions = catalog?.questions ?? []

        self.bundle = bundle
        subjects = catalog?.subjects ?? []
        questions = loadedQuestions
        questionsByID = Dictionary(loadedQuestions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Every volume, loading any that haven't been read yet.
    var volumes: [Volume] { Self.volumeIDs.compactMap { volume($0) } }

    func volume(_ id: String) -> Volume? {
        if let volume = loadedVolumes[id] { return volume }
        guard let file = Self.load(ScriptureVolumeFile.self, named: "scripture-\(id)", in: bundle) else { return nil }
        let volume = file.volume
        for book in volume.books {
            for chapter in book.chapters {
                chapters[chapter.id] = chapter
                bookTitles[chapter.id] = book.title
            }
        }
        loadedVolumes[id] = volume
        return volume
    }

    // MARK: Scripture

    var defaultChapterID: String { "bofm.alma.32" }

    func chapter(_ id: String) -> Chapter? {
        if let chapter = chapters[id] { return chapter }
        // "bofm.alma.32" lives in volume "bofm".
        let volumeID = String(id.prefix { $0 != "." })
        guard Self.volumeIDs.contains(volumeID) else { return nil }
        _ = volume(volumeID)
        return chapters[id]
    }

    /// "Alma 32"
    func title(forChapter id: String) -> String {
        guard let chapter = chapter(id), let book = bookTitles[id] else { return "" }
        return "\(book) \(chapter.number)"
    }

    func bookTitle(forChapter id: String) -> String {
        _ = chapter(id)
        return bookTitles[id] ?? ""
    }

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
