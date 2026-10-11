import Foundation

// Read-only study content that ships in the app bundle (Resources/Content).
// The scripture types are nonisolated and Sendable so volumes decode and search off the main thread.
// Every item has a stable string ID. Never renumber an ID once it ships:
// user highlights, notes and reviews point at these IDs.

/// One bundled volume file, e.g. scripture-bofm.json (built by scripts/import_standard_works.py).
nonisolated struct ScriptureVolumeFile: Decodable, Sendable {
    let contentVersion: Int
    let volume: Volume
}

nonisolated struct Volume: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let books: [Book]
}

nonisolated struct Book: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let chapters: [Chapter]
}

nonisolated struct Chapter: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let number: Int
    let heading: String?
    let verses: [Verse]
}

nonisolated struct Verse: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let number: Int
    let text: String
}

struct SubjectCatalog: Decodable {
    let contentVersion: Int
    let subjects: [Subject]
    let questions: [Question]
}

struct Subject: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let symbol: String
    let summary: String
    let units: [StudyUnit]
    let resources: [Resource]
}

/// A unit inside a subject. Named StudyUnit because Foundation already has a `Unit` type.
struct StudyUnit: Decodable, Identifiable, Hashable {
    let id: String
    let number: Int
    let title: String
    let range: String
    let readingChapterIDs: [String]
}

struct Resource: Decodable, Identifiable, Hashable {
    enum Kind: String, Decodable, CaseIterable {
        case scripture, article, manual, book, video, website, reference

        var title: String {
            switch self {
            case .scripture: "Scripture"
            case .article: "Articles"
            case .manual: "Manuals"
            case .book: "Books"
            case .video: "Video"
            case .website: "Websites"
            case .reference: "Reference"
            }
        }

        var symbol: String {
            switch self {
            case .scripture: "book.closed"
            case .article: "doc.text"
            case .manual: "text.book.closed"
            case .book: "books.vertical"
            case .video: "play.rectangle"
            case .website: "safari"
            case .reference: "character.book.closed"
            }
        }
    }

    let id: String
    let kind: Kind
    let title: String
    let author: String
    let note: String?
    let url: URL?
    let chapterID: String?
}

struct Question: Decodable, Identifiable, Hashable {
    let id: String
    let subjectID: String
    let unitID: String
    let prompt: String
    let options: [String]
    /// Index into `options`.
    let answer: Int
    let reference: String
    let explanation: String
    let chapterID: String?
}

nonisolated struct VerseHit: Identifiable, Hashable, Sendable {
    let chapterID: String
    let reference: String
    let verse: Verse
    var id: String { verse.id }
}
