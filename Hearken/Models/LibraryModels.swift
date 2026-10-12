import Foundation
import SwiftData

// The Library's layout and the user's own books, stored with SwiftData and synced through
// CloudKit like the rest of the user's data (every property has a default, no unique
// constraints).
//
// The three starting shelves have fixed IDs ("standard", "helps", "history") so two devices
// that each seed them end up with the same records; LibraryStore.tidy merges the copies.
// Removing one of those shelves keeps its record with `isRemoved` set, so a new device
// seeding the defaults can't bring it back.

/// One shelf in the Library.
@Model
final class LibraryShelfRecord {
    var id: String = UUID().uuidString
    var name: String = ""
    /// Shelves are drawn in ascending order.
    var order: Double = 0
    /// The Standard Works: can be moved, not renamed or deleted.
    var isLocked: Bool = false
    var isRemoved: Bool = false
    var createdAt: Date = Date.now
    /// When the user last changed it. Seeded shelves start at the distant past, so any
    /// change made on another device wins when the copies are merged.
    var updatedAt: Date = Date.now

    init(id: String = UUID().uuidString, name: String, order: Double, isLocked: Bool = false, updatedAt: Date = .now) {
        self.id = id
        self.name = name
        self.order = order
        self.isLocked = isLocked
        self.updatedAt = updatedAt
    }
}

/// Which shelf one of Hearken's own works (Study Helps, Church History) sits on. The
/// Standard Works always stay on their shelf and have no placement.
@Model
final class ShelfPlacement {
    var workID: String = ""
    /// Empty when the user removed the work from the Library.
    var shelfID: String = ""
    var order: Double = 0
    var updatedAt: Date = Date.now

    init(workID: String, shelfID: String, order: Double, updatedAt: Date = .now) {
        self.workID = workID
        self.shelfID = shelfID
        self.order = order
        self.updatedAt = updatedAt
    }
}

/// A book the user imported from an EPUB or PDF file.
///
/// The prepared text (chapters of paragraphs, see ImportedContent) and the cover sync with
/// the record. The original file stays on the device it was imported on, under
/// Application Support/ImportedBooks/<id>/, for the PDF Original Pages view.
@Model
final class ImportedBook {
    nonisolated enum Format: String, Codable, Sendable {
        case epub, pdf

        var title: String { rawValue.uppercased() }
        var fileExtension: String { rawValue }
    }

    nonisolated enum Status: String, Codable, Sendable {
        /// The chapters are being prepared.
        case preparing
        case ready
        /// The file couldn't be read.
        case failed
    }

    var id: String = UUID().uuidString
    var title: String = ""
    var author: String = ""
    var formatRaw: String = Format.epub.rawValue
    var statusRaw: String = Status.preparing.rawValue
    var shelfID: String = ""
    var order: Double = 0
    var addedAt: Date = Date.now
    var updatedAt: Date = Date.now
    /// SHA-256 of the original file, for spotting a book that's already in the library.
    var fileHash: String = ""
    var fileName: String = ""
    var fileSize: Int = 0
    var chapterCount: Int = 0
    /// PDFs only.
    var pageCount: Int = 0
    /// The generated cover's cloth color, used when the file has no cover art.
    var coverHex: Int = 0
    @Attribute(.externalStorage) var coverData: Data?
    /// JSON-encoded ImportedContent.
    @Attribute(.externalStorage) var contentData: Data?

    init(id: String, title: String, author: String, format: Format, shelfID: String, order: Double) {
        self.id = id
        self.title = title
        self.author = author
        self.formatRaw = format.rawValue
        self.shelfID = shelfID
        self.order = order
    }

    var format: Format {
        get { Format(rawValue: formatRaw) ?? .epub }
        set { formatRaw = newValue.rawValue }
    }

    var status: Status {
        get { Status(rawValue: statusRaw) ?? .preparing }
        set { statusRaw = newValue.rawValue }
    }

    /// "user.<id>": the prefix of every chapter ID in this book.
    var workID: String { ImportedLibrary.workID(forBook: id) }
}

/// An imported book's text, prepared for the reader: chapters of paragraphs. Paragraphs
/// play the part of verses (numbered from 1, numbers hidden), so highlights, notes,
/// bookmarks, Listen and Explain work as they do in scripture.
nonisolated struct ImportedContent: Codable, Sendable {
    var version = 1
    var chapters: [ImportedChapter]
}

nonisolated struct ImportedChapter: Codable, Sendable, Hashable {
    var title: String
    var paragraphs: [String]
    /// PDFs: the page (from 1) the chapter starts on.
    var startPage: Int?
}
