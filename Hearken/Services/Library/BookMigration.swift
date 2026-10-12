import Foundation
import SwiftData

/// Moves what the user made in a book (highlights, notes, bookmarks, reading positions) from
/// its old paragraphs onto its new verses when the book is re-prepared.
///
/// Each new verse is an exact piece of one old paragraph and knows where it starts in it
/// (VerseOrigin), so a position in an old paragraph maps to one new verse and an offset in it.
@MainActor
enum BookMigration {
    private struct Key: Hashable {
        let chapter: Int
        let paragraph: Int
    }

    private struct Target {
        let chapter: Int
        let verseIndex: Int
        let start: Int
        let length: Int
    }

    /// A position in the new book.
    private struct Place {
        let chapterID: String
        let chapterIndex: Int
        let verse: Int
        let offset: Int
    }

    static func move(bookID: String, from old: ImportedContent, to new: StructuredBook, in context: ModelContext) {
        let prefix = ImportedLibrary.workID(forBook: bookID) + "."

        var index: [Key: [Target]] = [:]
        for (chapter, origins) in new.origins.enumerated() {
            let verses = new.content.chapters[chapter].paragraphs
            for (verse, origin) in origins.enumerated() {
                let length = verses.indices.contains(verse) ? verses[verse].utf16.count : 0
                index[Key(chapter: origin.chapter, paragraph: origin.paragraph), default: []]
                    .append(Target(chapter: chapter, verseIndex: verse, start: origin.offset, length: length))
            }
        }
        for key in index.keys { index[key]?.sort { $0.start < $1.start } }

        func number(_ chapter: Int, _ verseIndex: Int) -> Int {
            let source = new.content.chapters[chapter]
            if let numbers = source.verseNumbers, numbers.count == source.paragraphs.count { return numbers[verseIndex] }
            return verseIndex + 1
        }

        func place(_ target: Target, offset: Int) -> Place {
            Place(
                chapterID: ImportedLibrary.chapterID(book: bookID, number: target.chapter + 1),
                chapterIndex: target.chapter,
                verse: number(target.chapter, target.verseIndex),
                offset: offset
            )
        }

        /// Old (chapter ID, paragraph number, offset) → new place. An offset of -1 means the
        /// end of the paragraph, and maps to the end of its last verse.
        func locate(_ chapterID: String, _ paragraph: Int, _ offset: Int) -> Place? {
            guard let parsed = ImportedLibrary.parse(chapterID) else { return nil }
            let oldChapter = parsed.number - 1
            if let targets = index[Key(chapter: oldChapter, paragraph: paragraph - 1)], let first = targets.first {
                if offset < 0, let last = targets.last { return place(last, offset: -1) }
                let target = targets.last { $0.start <= offset } ?? first
                return place(target, offset: min(max(0, offset - target.start), target.length))
            }
            // That paragraph didn't become a verse (a heading or a scene break): the next one that did.
            let count = old.chapters.indices.contains(oldChapter) ? old.chapters[oldChapter].paragraphs.count : 0
            if paragraph < count {
                for next in paragraph..<count {
                    if let target = index[Key(chapter: oldChapter, paragraph: next)]?.first { return place(target, offset: 0) }
                }
            }
            for previous in stride(from: paragraph - 2, through: 0, by: -1) {
                if let target = index[Key(chapter: oldChapter, paragraph: previous)]?.last { return place(target, offset: -1) }
            }
            return nil
        }

        // Highlights: both ends move; one that would now span two chapters stops at the end of the first.
        let highlights = (try? context.fetch(FetchDescriptor<Highlight>(predicate: #Predicate { $0.chapterID.starts(with: prefix) }))) ?? []
        for highlight in highlights {
            guard let start = locate(highlight.chapterID, highlight.startVerse, highlight.startOffset),
                  var end = locate(highlight.chapterID, highlight.endVerse, highlight.endOffset) else { continue }
            if end.chapterIndex != start.chapterIndex {
                let lastIndex = max(new.content.chapters[start.chapterIndex].paragraphs.count - 1, 0)
                end = Place(chapterID: start.chapterID, chapterIndex: start.chapterIndex, verse: number(start.chapterIndex, lastIndex), offset: -1)
            }
            highlight.chapterID = start.chapterID
            highlight.startVerse = start.verse
            highlight.startOffset = start.offset
            highlight.endVerse = end.verse
            highlight.endOffset = end.offset
            highlight.updatedAt = .now
        }

        let notes = (try? context.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.chapterID.starts(with: prefix) }))) ?? []
        for note in notes {
            guard let place = locate(note.chapterID, note.verse, 0) else { continue }
            note.chapterID = place.chapterID
            note.verse = place.verse
            note.updatedAt = .now
        }

        let bookmarks = (try? context.fetch(FetchDescriptor<Bookmark>(predicate: #Predicate { $0.chapterID.starts(with: prefix) }))) ?? []
        for bookmark in bookmarks {
            guard let place = locate(bookmark.chapterID, max(bookmark.verse, 1), 0) else { continue }
            bookmark.chapterID = place.chapterID
            bookmark.verse = place.verse
            bookmark.updatedAt = .now
        }

        // Reading positions: one record per new chapter. A chapter read in full marks every
        // chapter made from it as read.
        let records = (try? context.fetch(FetchDescriptor<ReadingProgress>(predicate: #Predicate { $0.chapterID.starts(with: prefix) }))) ?? []
        var kept: [String: ReadingProgress] = [:]
        var completedOld: [(chapter: Int, date: Date)] = []
        for record in records {
            if let completed = record.completedAt, let parsed = ImportedLibrary.parse(record.chapterID) {
                completedOld.append((parsed.number - 1, completed))
            }
            guard let place = locate(record.chapterID, max(record.lastVerse, 1), 0) else { continue }
            if let existing = kept[place.chapterID] {
                // Two old chapters now share one: keep the more recent position.
                if record.updatedAt > existing.updatedAt {
                    existing.lastVerse = place.verse
                    existing.updatedAt = record.updatedAt
                }
                existing.completedAt = existing.completedAt ?? record.completedAt
                existing.hasEarnedReadXP = existing.hasEarnedReadXP || record.hasEarnedReadXP
                context.delete(record)
                continue
            }
            record.chapterID = place.chapterID
            record.lastVerse = place.verse
            kept[place.chapterID] = record
        }
        for (oldChapter, date) in completedOld {
            let newChapters = Set(index.filter { $0.key.chapter == oldChapter }.flatMap { $0.value.map(\.chapter) })
            for chapter in newChapters {
                let id = ImportedLibrary.chapterID(book: bookID, number: chapter + 1)
                if let record = kept[id] {
                    record.completedAt = record.completedAt ?? date
                } else {
                    let record = ReadingProgress(chapterID: id, lastVerse: 1)
                    record.completedAt = date
                    // Reading XP was already earned for the old chapter.
                    record.hasEarnedReadXP = true
                    context.insert(record)
                    kept[id] = record
                }
            }
        }
    }
}
