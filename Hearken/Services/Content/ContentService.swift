import Foundation
import Observation

/// Loads the bundled content and answers lookups.
///
/// Scripture ships as one JSON file per volume (8 MB in all). `preloadVolumes()` decodes them
/// off the main thread soon after launch; anything asked for before that loads on demand.
/// Search always runs off the main thread. The plan is to compile this into a SQLite store
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
    @ObservationIgnored private var preloading: Task<Void, Never>?

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
        // Not preloaded yet: decode now (on the main thread, the one time).
        guard let volume = Self.decodeVolume(id, in: bundle) else { return nil }
        install(volume)
        return volume
    }

    /// Decodes every volume that isn't loaded yet, off the main thread. Safe to call more than
    /// once; later calls wait for the first.
    func preloadVolumes() async {
        if let preloading {
            await preloading.value
            return
        }
        let task = Task {
            for id in Self.volumeIDs where loadedVolumes[id] == nil {
                let bundle = self.bundle
                let decoded = await Task.detached(priority: .utility) { Self.decodeVolume(id, in: bundle) }.value
                // Something may have loaded it on demand meanwhile.
                if loadedVolumes[id] == nil, let decoded { install(decoded) }
            }
        }
        preloading = task
        await task.value
    }

    private func install(_ volume: Volume) {
        for book in volume.books {
            for chapter in book.chapters {
                chapters[chapter.id] = chapter
                bookTitles[chapter.id] = book.title
            }
        }
        loadedVolumes[volume.id] = volume
    }

    nonisolated private static func decodeVolume(_ id: String, in bundle: Bundle) -> Volume? {
        guard let url = bundle.url(forResource: "scripture-\(id)", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ScriptureVolumeFile.self, from: data).volume
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

    /// Verses containing `text`, scanning every volume off the main thread.
    func search(_ text: String, limit: Int = 50) async -> [VerseHit] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return [] }
        await preloadVolumes()
        let volumes = Self.volumeIDs.compactMap { loadedVolumes[$0] }
        return await Task.detached(priority: .userInitiated) { Self.scan(volumes, for: query, limit: limit) }.value
    }

    nonisolated private static func scan(_ volumes: [Volume], for query: String, limit: Int) -> [VerseHit] {
        var hits: [VerseHit] = []
        for volume in volumes {
            if Task.isCancelled { return hits }
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
