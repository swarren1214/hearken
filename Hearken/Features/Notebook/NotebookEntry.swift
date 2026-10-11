import Foundation
import SwiftData

/// One card in the Notebook.
///
/// Highlights and notes are separate things: a highlight can stand alone, a note can stand
/// alone, and when a note sits on a verse that a highlight covers, the two share one card.
struct NotebookEntry: Identifiable {
    enum Kind {
        case highlight, note, both
    }

    enum ID: Hashable {
        case highlight(PersistentIdentifier)
        case note(PersistentIdentifier)
    }

    let id: ID
    let chapterID: String
    /// The LibraryBook ID, e.g. "bofm.alma".
    let bookID: String
    let bookTitle: String
    let startVerse: Int
    let endVerse: Int
    /// "Alma 32:21" or "Alma 32:27–28".
    let reference: String
    let highlight: Highlight?
    let note: Note?
    /// For a highlight: the highlighted words with context. For a note alone: the verse.
    let quote: NotebookQuote
    /// Sorts entries in canon order: Genesis before Matthew before 1 Nephi.
    let canonKey: Int

    var kind: Kind {
        switch (highlight, note) {
        case (.some, .some): .both
        case (.some, nil): .highlight
        default: .note
        }
    }

    var hasHighlight: Bool { highlight != nil }
    var hasNote: Bool { note.map { !$0.body.isEmpty } ?? false }
    var hue: HighlightHue? { highlight?.hue }

    /// The most recent change to either part.
    var date: Date {
        max(highlight?.updatedAt ?? .distantPast, note?.updatedAt ?? .distantPast)
    }

    /// The verse to open the reader on.
    var target: BookmarkTarget { BookmarkTarget(chapterID: chapterID, verse: note?.verse ?? startVerse) }

    func matches(_ query: String) -> Bool {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let fields = [quote.fullText, note?.body ?? "", reference, note?.tags.joined(separator: " ") ?? ""]
        return fields.contains { $0.range(of: query, options: options) != nil }
    }
}

/// Text shown on a card: the marked words and a little context on either side.
struct NotebookQuote {
    var before: String
    var marked: String
    var after: String
    /// False when the chapter's text isn't in the app yet.
    var isAvailable: Bool

    var fullText: String { before + marked + after }

    static let unavailable = NotebookQuote(before: "", marked: "", after: "", isAvailable: false)
}

/// Turns the stored highlights and notes into Notebook entries.
@MainActor
final class NotebookBuilder {
    private struct CachedQuote {
        let updatedAt: Date
        let quote: NotebookQuote
    }

    /// Quotes by highlight, so filtering and searching never re-cut verse text.
    private var quotes: [PersistentIdentifier: CachedQuote] = [:]

    /// Each book's position across the whole library, in shelf order.
    private static let bookOrder: [String: Int] = {
        let books = LibraryCatalog.shelves.flatMap(\.works).flatMap(\.books)
        var order: [String: Int] = [:]
        for (index, book) in books.enumerated() where order[book.id] == nil {
            order[book.id] = index
        }
        return order
    }()

    func entries(highlights: [Highlight], notes: [Note], content: ContentService) -> [NotebookEntry] {
        // A note joins the earliest highlight covering its verse in the same chapter; each
        // highlight takes at most one note, so any others on it get their own cards.
        var highlightsByChapter: [String: [Highlight]] = [:]
        for highlight in highlights {
            highlightsByChapter[highlight.chapterID, default: []].append(highlight)
        }
        for key in highlightsByChapter.keys {
            highlightsByChapter[key]?.sort {
                ($0.startVerse, $0.startOffset, $0.createdAt) < ($1.startVerse, $1.startOffset, $1.createdAt)
            }
        }

        var noteFor: [PersistentIdentifier: Note] = [:]
        var looseNotes: [Note] = []
        for note in notes.sorted(by: { ($0.chapterID, $0.verse) < ($1.chapterID, $1.verse) }) {
            guard !note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let covering = highlightsByChapter[note.chapterID]?.first {
                $0.covers(verse: note.verse) && noteFor[$0.persistentModelID] == nil
            }
            if let covering {
                noteFor[covering.persistentModelID] = note
            } else {
                looseNotes.append(note)
            }
        }

        var result: [NotebookEntry] = []
        result.reserveCapacity(highlights.count + looseNotes.count)
        for highlight in highlights {
            result.append(entry(for: highlight, note: noteFor[highlight.persistentModelID], content: content))
        }
        for note in looseNotes {
            result.append(entry(for: note, content: content))
        }
        return result
    }

    private func entry(for highlight: Highlight, note: Note?, content: ContentService) -> NotebookEntry {
        let chapterID = highlight.chapterID
        let reference = Self.reference(chapterID: chapterID, start: highlight.startVerse, end: highlight.endVerse, content: content)
        return NotebookEntry(
            id: .highlight(highlight.persistentModelID),
            chapterID: chapterID,
            bookID: Self.bookID(of: chapterID),
            bookTitle: Self.bookTitle(of: chapterID, content: content),
            startVerse: highlight.startVerse,
            endVerse: highlight.endVerse,
            reference: reference,
            highlight: highlight,
            note: note,
            quote: quote(for: highlight, content: content),
            canonKey: Self.canonKey(chapterID: chapterID, verse: highlight.startVerse)
        )
    }

    private func entry(for note: Note, content: ContentService) -> NotebookEntry {
        let chapterID = note.chapterID
        let text = content.chapter(chapterID)?.verses.first { $0.number == note.verse }?.text
        return NotebookEntry(
            id: .note(note.persistentModelID),
            chapterID: chapterID,
            bookID: Self.bookID(of: chapterID),
            bookTitle: Self.bookTitle(of: chapterID, content: content),
            startVerse: note.verse,
            endVerse: note.verse,
            reference: Self.reference(chapterID: chapterID, start: note.verse, end: note.verse, content: content),
            highlight: nil,
            note: note,
            quote: text.map { NotebookQuote(before: $0, marked: "", after: "", isAvailable: true) } ?? .unavailable,
            canonKey: Self.canonKey(chapterID: chapterID, verse: note.verse)
        )
    }

    // MARK: Quotes

    private func quote(for highlight: Highlight, content: ContentService) -> NotebookQuote {
        let id = highlight.persistentModelID
        if let cached = quotes[id], cached.updatedAt == highlight.updatedAt { return cached.quote }
        let quote = Self.cutQuote(for: highlight, verses: content.chapter(highlight.chapterID)?.verses ?? [])
        quotes[id] = CachedQuote(updatedAt: highlight.updatedAt, quote: quote)
        return quote
    }

    /// Cuts the highlighted words out of the verse text using the stored UTF-16 offsets
    /// (an end offset of -1 means the end of the verse), with about 60 characters of context.
    static func cutQuote(for highlight: Highlight, verses: [Verse], context: Int = 60) -> NotebookQuote {
        let inRange = verses.filter { $0.number >= highlight.startVerse && $0.number <= highlight.endVerse }
        guard let first = inRange.first, let last = inRange.last else { return .unavailable }
        let firstLength = first.text.utf16.count
        let lastLength = last.text.utf16.count
        let start = min(max(highlight.startOffset, 0), firstLength)
        let end = highlight.endOffset < 0 ? lastLength : min(highlight.endOffset, lastLength)

        var marked: [String] = []
        for verse in inRange {
            let length = verse.text.utf16.count
            let lower = verse.number == first.number ? start : 0
            let upper = verse.number == last.number ? end : length
            let piece = verse.text.utf16Slice(lower, upper)
            if !piece.isEmpty { marked.append(piece) }
        }
        let before = tail(first.text.utf16Slice(0, start), limit: context)
        let after = head(last.text.utf16Slice(end, lastLength), limit: context)
        return NotebookQuote(before: before, marked: marked.joined(separator: " "), after: after, isAvailable: true)
    }

    /// The last `limit` or so characters, starting at a word break.
    static func tail(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        var start = text.index(text.endIndex, offsetBy: -limit)
        while start < text.endIndex, !text[start].isWhitespace { start = text.index(after: start) }
        let trimmed = text[start...].drop(while: \.isWhitespace)
        return "…" + trimmed
    }

    /// The first `limit` or so characters, ending at a word break.
    static func head(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        var end = text.index(text.startIndex, offsetBy: limit)
        while end > text.startIndex, !text[text.index(before: end)].isWhitespace { end = text.index(before: end) }
        if end == text.startIndex { end = text.index(text.startIndex, offsetBy: limit) }
        let trimmed = text[..<end].reversed().drop(while: \.isWhitespace).reversed()
        return String(trimmed) + "…"
    }

    // MARK: Places

    /// "bofm.alma.32" → "bofm.alma".
    static func bookID(of chapterID: String) -> String {
        guard let dot = chapterID.lastIndex(of: ".") else { return chapterID }
        return String(chapterID[..<dot])
    }

    static func bookTitle(of chapterID: String, content: ContentService) -> String {
        let title = content.bookTitle(forChapter: chapterID)
        if !title.isEmpty { return title }
        return LibraryCatalog.location(ofChapter: chapterID)?.book.title ?? "Other"
    }

    static func canonKey(chapterID: String, verse: Int) -> Int {
        let book = bookOrder[bookID(of: chapterID)] ?? 9_999
        let chapter = Int(chapterID.split(separator: ".").last ?? "") ?? 0
        return book * 1_000_000 + chapter * 1_000 + verse
    }

    static func reference(chapterID: String, start: Int, end: Int, content: ContentService) -> String {
        var title = content.title(forChapter: chapterID)
        if title.isEmpty, let location = LibraryCatalog.location(ofChapter: chapterID) {
            title = "\(location.book.title) \(location.number)"
        }
        return end > start ? "\(title):\(start)–\(end)" : "\(title):\(start)"
    }
}

extension String {
    /// The text between two UTF-16 offsets, clamped to the string.
    nonisolated func utf16Slice(_ lower: Int, _ upper: Int) -> String {
        let units = utf16
        let count = units.count
        let low = min(max(lower, 0), count)
        let high = min(max(upper, low), count)
        let from = units.index(units.startIndex, offsetBy: low)
        let to = units.index(units.startIndex, offsetBy: high)
        return String(decoding: Array(units[from..<to]), as: UTF16.self)
    }
}
