import Foundation
import Observation
import OSLog
import SwiftData

/// Serves imported books to the rest of the app as if they were scripture.
///
/// An imported book's chapters have IDs like "user.<bookID>.3", and its paragraphs are the
/// chapter's verses. ContentService and LibraryCatalog hand any "user." ID to this class, so
/// the reader, highlights, notes, bookmarks, Listen and the Notebook need nothing special.
@MainActor
@Observable
final class ImportedLibrary {
    static let shared = ImportedLibrary()
    nonisolated static let prefix = "user."

    /// Preparing books' progress, 0...1, by book ID.
    var progress: [String: Double] = [:]
    /// What each book being prepared (or titled) is doing now, by book ID.
    var stage: [String: PrepStage] = [:]

    /// The steps of preparing a book, shown under its cover.
    nonisolated enum PrepStage: Equatable, Sendable {
        case reading
        case chapters
        case verses
        /// The on-device model is titling untitled parts; the book is already readable.
        case naming

        func title(for format: ImportedBook.Format) -> String {
            switch self {
            case .reading: format == .pdf ? "Reading pages" : "Reading file"
            case .chapters: "Finding chapters"
            case .verses: "Adding verses"
            case .naming: "Naming parts"
            }
        }
    }

    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var books: [String: BookInfo] = [:]
    @ObservationIgnored private var contents: [String: (stamp: Date, content: ImportedContent)] = [:]
    @ObservationIgnored private var chapters: [String: Chapter] = [:]
    private let log = Logger(subsystem: "com.stephenwarren.hearken", category: "library")

    /// What the rest of the app needs to know about a book, without holding its model.
    struct BookInfo {
        let id: String
        let title: String
        let author: String
        let format: ImportedBook.Format
        let coverHex: Int
        let chapterCount: Int
        let stamp: Date
    }

    func attach(container: ModelContainer) {
        self.container = container
        refresh()
    }

    /// The app's main context, for services that look up books.
    var modelContext: ModelContext? { container?.mainContext }

    // MARK: IDs

    nonisolated static func isImported(_ chapterID: String) -> Bool { chapterID.hasPrefix(prefix) }

    nonisolated static func workID(forBook bookID: String) -> String { prefix + bookID }

    nonisolated static func chapterID(book bookID: String, number: Int) -> String { "\(prefix)\(bookID).\(number)" }

    /// "user.<book>.<n>" → (book, n)
    nonisolated static func parse(_ chapterID: String) -> (bookID: String, number: Int)? {
        guard isImported(chapterID) else { return nil }
        let rest = chapterID.dropFirst(prefix.count)
        guard let dot = rest.lastIndex(of: "."), let number = Int(rest[rest.index(after: dot)...]) else { return nil }
        return (String(rest[..<dot]), number)
    }

    /// "user.<book>" or "user.<book>.<n>" → book
    nonisolated static func bookID(fromWorkOrChapter id: String) -> String? {
        guard isImported(id) else { return nil }
        if let parsed = parse(id) { return parsed.bookID }
        return String(id.dropFirst(prefix.count))
    }

    // MARK: Books

    /// Reloads what's known about every ready book. Called at launch and whenever the
    /// Library sees its books change (an import, a delete, or a sync from another device).
    func refresh() {
        guard let context = container?.mainContext else { return }
        let all = (try? context.fetch(FetchDescriptor<ImportedBook>())) ?? []
        var next: [String: BookInfo] = [:]
        for book in all where book.status == .ready {
            next[book.id] = info(book)
        }
        // Drop cached text for books that changed or went away.
        for (id, cached) in contents where next[id]?.stamp != cached.stamp {
            contents[id] = nil
            chapters = chapters.filter { !$0.key.hasPrefix(Self.workID(forBook: id) + ".") }
        }
        books = next
    }

    func book(_ bookID: String) -> BookInfo? {
        if let info = books[bookID] { return info }
        // Not known yet (a book synced in since the last refresh): look it up.
        guard let model = model(bookID), model.status == .ready else { return nil }
        let info = info(model)
        books[bookID] = info
        return info
    }

    func model(_ bookID: String) -> ImportedBook? {
        guard let context = container?.mainContext else { return nil }
        var descriptor = FetchDescriptor<ImportedBook>(predicate: #Predicate { $0.id == bookID })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func info(_ book: ImportedBook) -> BookInfo {
        BookInfo(
            id: book.id, title: book.title, author: book.author, format: book.format,
            coverHex: book.coverHex, chapterCount: book.chapterCount, stamp: book.updatedAt
        )
    }

    /// Every ready book as a LibraryWork with one volume and one book, so the location
    /// panel, Listen and the Notebook can treat it like a scripture work.
    var works: [LibraryWork] {
        books.values.sorted { $0.title < $1.title }.map { work($0) }
    }

    func work(forBook bookID: String) -> LibraryWork? {
        book(bookID).map { work($0) }
    }

    private func work(_ info: BookInfo) -> LibraryWork {
        let id = Self.workID(forBook: info.id)
        let book = LibraryBook(id: id, title: info.title, chapterCount: max(info.chapterCount, 1), unit: .chapter)
        return LibraryWork(
            id: id, title: info.title, subtitle: info.author, coverHex: UInt32(truncatingIfNeeded: info.coverHex),
            summary: LibraryBook.Unit.chapter.count(info.chapterCount),
            volumes: [LibraryVolume(id: id, title: info.title, books: [book])]
        )
    }

    // MARK: Text

    func content(_ bookID: String) -> ImportedContent? {
        guard let info = book(bookID) else { return nil }
        if let cached = contents[bookID], cached.stamp == info.stamp { return cached.content }
        guard let data = model(bookID)?.contentData else { return nil }
        do {
            let content = try JSONDecoder().decode(ImportedContent.self, from: data)
            contents[bookID] = (info.stamp, content)
            return content
        } catch {
            log.error("Couldn't read the prepared text of \(bookID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func chapter(_ id: String) -> Chapter? {
        if let chapter = chapters[id] { return chapter }
        guard let parsed = Self.parse(id),
              let loaded = self.content(parsed.bookID),
              loaded.chapters.indices.contains(parsed.number - 1) else { return nil }
        let number = parsed.number
        let source = loaded.chapters[number - 1]
        // Printed verse numbers when the book has them, else 1, 2, 3.
        let printed = source.verseNumbers.flatMap { $0.count == source.paragraphs.count ? $0 : nil }
        let verses = source.paragraphs.enumerated().map { index, text in
            let verse = printed?[index] ?? index + 1
            return Verse(id: "\(id).\(verse)", number: verse, text: text)
        }
        let chapter = Chapter(id: id, number: number, heading: source.title, verses: verses)
        chapters[id] = chapter
        return chapter
    }

    /// The chapter's own title ("The Parable of Enoch").
    func chapterTitle(_ id: String) -> String? {
        guard let parsed = Self.parse(id), let loaded = self.content(parsed.bookID),
              loaded.chapters.indices.contains(parsed.number - 1) else { return nil }
        return loaded.chapters[parsed.number - 1].title
    }

    /// PDFs: the page (from 1) the chapter starts on.
    func startPage(_ id: String) -> Int? {
        guard let parsed = Self.parse(id), let loaded = self.content(parsed.bookID),
              loaded.chapters.indices.contains(parsed.number - 1) else { return nil }
        return loaded.chapters[parsed.number - 1].startPage
    }

    func bookTitle(forChapter id: String) -> String {
        Self.parse(id).flatMap { book($0.bookID) }?.title ?? ""
    }

    /// A chapter's unnumbered opening text (a summary before verse 1), when it has one.
    func chapterSummary(_ id: String) -> String? {
        guard let parsed = Self.parse(id), let loaded = self.content(parsed.bookID),
              loaded.chapters.indices.contains(parsed.number - 1) else { return nil }
        return loaded.chapters[parsed.number - 1].summary
    }

    /// Whether the book has real verses (version 2): numbers show and references use "3:7".
    /// Books prepared before verses existed show paragraphs, numbers hidden, until upgraded.
    func hasVerses(_ chapterID: String) -> Bool {
        guard let parsed = Self.parse(chapterID) else { return true }
        return content(parsed.bookID)?.hasVerses ?? false
    }

    /// Listen reads verse numbers aloud only when the book printed them.
    func readsVerseNumbers(_ chapterID: String) -> Bool {
        guard let parsed = Self.parse(chapterID) else { return true }
        return content(parsed.bookID)?.numbering == .printed
    }

    /// The number references use: the book's printed chapter number, or its position.
    func displayNumber(_ id: String) -> Int? {
        guard let parsed = Self.parse(id) else { return nil }
        guard let loaded = content(parsed.bookID), loaded.chapters.indices.contains(parsed.number - 1) else { return parsed.number }
        return loaded.chapters[parsed.number - 1].number ?? parsed.number
    }

    /// "Enoch 6" (or, for a book prepared before verses, "The Book of Enoch · 6").
    func title(forChapter id: String) -> String {
        guard let parsed = Self.parse(id), let info = book(parsed.bookID) else { return "" }
        guard hasVerses(id) else { return "\(info.title) · \(parsed.number)" }
        return "\(Self.shortTitle(info.title)) \(displayNumber(id) ?? parsed.number)"
    }

    /// "Enoch 6:3" (older books: "The Book of Enoch · 6 ¶3").
    func reference(chapterID: String, verse: Int) -> String {
        hasVerses(chapterID)
            ? "\(title(forChapter: chapterID)):\(verse)"
            : "\(title(forChapter: chapterID)) ¶\(verse)"
    }

    /// A book's title cut down for references: "The Book of Enoch" → "Enoch",
    /// "The Wisdom of Solomon" → "Wisdom of Solomon", at most 3 words.
    nonisolated static func shortTitle(_ title: String) -> String {
        var words = title.split(separator: " ").map(String.init)
        for lead in [["The", "Book", "of"], ["Book", "of"], ["The"]] where words.count > lead.count {
            if zip(words, lead).allSatisfy({ $0.caseInsensitiveCompare($1) == .orderedSame }) {
                words.removeFirst(lead.count)
                break
            }
        }
        if words.count > 3 {
            words = Array(words.prefix(3))
            while let last = words.last, ["of", "the", "and", "a", "an", "to"].contains(last.lowercased()), words.count > 1 {
                words.removeLast()
            }
        }
        // Drop a subtitle after a colon.
        let short = words.joined(separator: " ").split(separator: ":").first.map(String.init) ?? title
        return short.isEmpty ? title : short
    }

    // MARK: Files

    /// Where the original file of a book imported on this device is kept.
    nonisolated static func folder(forBook bookID: String) -> URL {
        URL.applicationSupportDirectory
            .appending(path: "ImportedBooks", directoryHint: .isDirectory)
            .appending(path: bookID, directoryHint: .isDirectory)
    }

    nonisolated static func originalFile(forBook bookID: String, format: ImportedBook.Format) -> URL {
        folder(forBook: bookID).appending(path: "original.\(format.fileExtension)")
    }

    /// The original file, when this device has it.
    func originalFile(forBook bookID: String) -> URL? {
        guard let format = book(bookID)?.format ?? model(bookID)?.format else { return nil }
        let url = Self.originalFile(forBook: bookID, format: format)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    func forget(_ bookID: String) {
        books[bookID] = nil
        contents[bookID] = nil
        progress[bookID] = nil
        stage[bookID] = nil
        chapters = chapters.filter { !$0.key.hasPrefix(Self.workID(forBook: bookID) + ".") }
        try? FileManager.default.removeItem(at: Self.folder(forBook: bookID))
    }
}
