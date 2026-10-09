import SwiftUI

// What sits on the Library shelves: works → volumes → books → chapter counts.
// This describes structure only, so every chapter can be listed before its text is
// imported. Verse text comes from ContentService, keyed by the same chapter IDs
// ("<volume>.<book>.<number>", for example "bofm.alma.32").

struct LibraryShelf: Identifiable {
    let id: String
    let title: String
    let works: [LibraryWork]

    var caption: String {
        let available = works.filter(\.isAvailable).count
        return available == 0 ? "Coming soon" : "\(available) \(available == 1 ? "book" : "books")"
    }
}

struct LibraryWork: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let coverHex: UInt32
    /// One line under the title inside the book, e.g. "15 books · 239 chapters".
    let summary: String
    let volumes: [LibraryVolume]

    var isAvailable: Bool { !volumes.isEmpty }
    var coverColor: Color { Color(hex: coverHex) }
    var books: [LibraryBook] { volumes.flatMap(\.books) }
    /// Works with one unnamed volume skip straight to their books.
    var hasVolumeLevel: Bool { volumes.count > 1 }
}

struct LibraryVolume: Identifiable, Hashable {
    let id: String
    let title: String
    let books: [LibraryBook]

    var summary: String {
        let chapters = books.reduce(0) { $0 + $1.chapterCount }
        return "\(books.count) books · \(chapters.formatted()) chapters"
    }
}

struct LibraryBook: Identifiable, Hashable {
    enum Unit: Hashable {
        case chapter, section, declaration

        var singular: String {
            switch self {
            case .chapter: "Chapter"
            case .section: "Section"
            case .declaration: "Declaration"
            }
        }

        func count(_ n: Int) -> String {
            let word = switch self {
            case .chapter: n == 1 ? "chapter" : "chapters"
            case .section: n == 1 ? "section" : "sections"
            case .declaration: n == 1 ? "declaration" : "declarations"
            }
            return "\(n.formatted()) \(word)"
        }
    }

    /// "<volume>.<book>", for example "nt.matt".
    let id: String
    let title: String
    let chapterCount: Int
    let unit: Unit

    func chapterID(_ number: Int) -> String { "\(id).\(number)" }

    func contains(chapterID: String) -> Bool { chapterID.hasPrefix(id + ".") }
}

struct LibraryLocation {
    let work: LibraryWork
    let volume: LibraryVolume
    let book: LibraryBook
    let number: Int
}

/// Navigation value for opening a work from the shelf.
struct LibraryRoute: Hashable {
    let workID: String
}

enum LibraryCatalog {
    static let shelves: [LibraryShelf] = [
        LibraryShelf(id: "standard", title: "Standard Works", works: [bible, bookOfMormon, doctrineAndCovenants, pearlOfGreatPrice]),
        LibraryShelf(id: "helps", title: "Study Helps", works: [
            placeholder("bd", "Bible Dictionary", 0x4D3B2E),
            placeholder("tg", "Topical Guide", 0x2F4A4A),
            placeholder("gs", "Guide to the Scriptures", 0x3D3557),
        ]),
        LibraryShelf(id: "history", title: "Church History", works: [
            placeholder("saints1", "Saints, Volume 1", 0x5A3A2A),
            placeholder("saints2", "Saints, Volume 2", 0x2E3F5C),
            placeholder("jsp", "Joseph Smith Papers", 0x3F3F3F),
        ]),
    ]

    static func work(_ id: String) -> LibraryWork? {
        shelves.flatMap(\.works).first { $0.id == id }
    }

    /// The chapter `offset` places away within the same work (Genesis 50 → Exodus 1,
    /// Malachi 4 → Matthew 1), or nil at either end.
    static func adjacentChapter(to id: String, offset: Int) -> String? {
        guard let location = location(ofChapter: id) else { return nil }
        let books = location.work.books
        guard let bookIndex = books.firstIndex(of: location.book) else { return nil }
        let target = location.number + offset
        if target >= 1 && target <= location.book.chapterCount {
            return location.book.chapterID(target)
        }
        if offset > 0, bookIndex + 1 < books.count {
            return books[bookIndex + 1].chapterID(1)
        }
        if offset < 0, bookIndex > 0 {
            let previous = books[bookIndex - 1]
            return previous.chapterID(previous.chapterCount)
        }
        return nil
    }

    /// Where a chapter sits in the library, e.g. Holy Bible › Old Testament › Exodus › 4.
    static func location(ofChapter id: String) -> LibraryLocation? {
        for work in shelves.flatMap(\.works) {
            for volume in work.volumes {
                for book in volume.books where book.contains(chapterID: id) {
                    guard let number = Int(id.dropFirst(book.id.count + 1)) else { return nil }
                    return LibraryLocation(work: work, volume: volume, book: book, number: number)
                }
            }
        }
        return nil
    }

    // MARK: Standard works (real chapter counts)

    static let bible = LibraryWork(
        id: "bible", title: "Holy Bible", subtitle: "King James Version", coverHex: 0x3B2A22,
        summary: "2 volumes · 66 books · 1,189 chapters",
        volumes: [
            LibraryVolume(id: "ot", title: "Old Testament", books: books("ot", [
                ("gen", "Genesis", 50), ("ex", "Exodus", 40), ("lev", "Leviticus", 27), ("num", "Numbers", 36),
                ("deut", "Deuteronomy", 34), ("josh", "Joshua", 24), ("judg", "Judges", 21), ("ruth", "Ruth", 4),
                ("1-sam", "1 Samuel", 31), ("2-sam", "2 Samuel", 24), ("1-kgs", "1 Kings", 22), ("2-kgs", "2 Kings", 25),
                ("1-chr", "1 Chronicles", 29), ("2-chr", "2 Chronicles", 36), ("ezra", "Ezra", 10), ("neh", "Nehemiah", 13),
                ("esth", "Esther", 10), ("job", "Job", 42), ("ps", "Psalms", 150), ("prov", "Proverbs", 31),
                ("eccl", "Ecclesiastes", 12), ("song", "Song of Solomon", 8), ("isa", "Isaiah", 66), ("jer", "Jeremiah", 52),
                ("lam", "Lamentations", 5), ("ezek", "Ezekiel", 48), ("dan", "Daniel", 12), ("hosea", "Hosea", 14),
                ("joel", "Joel", 3), ("amos", "Amos", 9), ("obad", "Obadiah", 1), ("jonah", "Jonah", 4),
                ("micah", "Micah", 7), ("nahum", "Nahum", 3), ("hab", "Habakkuk", 3), ("zeph", "Zephaniah", 3),
                ("hag", "Haggai", 2), ("zech", "Zechariah", 14), ("mal", "Malachi", 4),
            ])),
            LibraryVolume(id: "nt", title: "New Testament", books: books("nt", [
                ("matt", "Matthew", 28), ("mark", "Mark", 16), ("luke", "Luke", 24), ("john", "John", 21),
                ("acts", "Acts", 28), ("rom", "Romans", 16), ("1-cor", "1 Corinthians", 16), ("2-cor", "2 Corinthians", 13),
                ("gal", "Galatians", 6), ("eph", "Ephesians", 6), ("philip", "Philippians", 4), ("col", "Colossians", 4),
                ("1-thes", "1 Thessalonians", 5), ("2-thes", "2 Thessalonians", 3), ("1-tim", "1 Timothy", 6), ("2-tim", "2 Timothy", 4),
                ("titus", "Titus", 3), ("philem", "Philemon", 1), ("heb", "Hebrews", 13), ("james", "James", 5),
                ("1-pet", "1 Peter", 5), ("2-pet", "2 Peter", 3), ("1-jn", "1 John", 5), ("2-jn", "2 John", 1),
                ("3-jn", "3 John", 1), ("jude", "Jude", 1), ("rev", "Revelation", 22),
            ])),
        ]
    )

    static let bookOfMormon = LibraryWork(
        id: "bofm", title: "Book of Mormon", subtitle: "Another Testament of Jesus Christ", coverHex: 0x1E3666,
        summary: "15 books · 239 chapters",
        volumes: [LibraryVolume(id: "bofm", title: "Book of Mormon", books: books("bofm", [
            ("1-ne", "1 Nephi", 22), ("2-ne", "2 Nephi", 33), ("jacob", "Jacob", 7), ("enos", "Enos", 1),
            ("jarom", "Jarom", 1), ("omni", "Omni", 1), ("w-of-m", "Words of Mormon", 1), ("mosiah", "Mosiah", 29),
            ("alma", "Alma", 63), ("hel", "Helaman", 16), ("3-ne", "3 Nephi", 30), ("4-ne", "4 Nephi", 1),
            ("morm", "Mormon", 9), ("ether", "Ether", 15), ("moro", "Moroni", 10),
        ]))]
    )

    static let doctrineAndCovenants = LibraryWork(
        id: "dc-testament", title: "Doctrine and Covenants", subtitle: "", coverHex: 0x3A3F55,
        summary: "138 sections",
        // The Official Declarations aren't in the public-domain source; add them with the Church content license.
        volumes: [LibraryVolume(id: "dc-testament", title: "Doctrine and Covenants", books: [
            LibraryBook(id: "dc-testament.dc", title: "Sections", chapterCount: 138, unit: .section),
        ])]
    )

    static let pearlOfGreatPrice = LibraryWork(
        id: "pgp", title: "Pearl of Great Price", subtitle: "", coverHex: 0x5B4026,
        summary: "5 books · 16 chapters",
        volumes: [LibraryVolume(id: "pgp", title: "Pearl of Great Price", books: books("pgp", [
            ("moses", "Moses", 8), ("abr", "Abraham", 5), ("js-m", "Joseph Smith—Matthew", 1),
            ("js-h", "Joseph Smith—History", 1), ("a-of-f", "Articles of Faith", 1),
        ]))]
    )

    private static func books(_ volume: String, _ list: [(String, String, Int)]) -> [LibraryBook] {
        list.map { LibraryBook(id: "\(volume).\($0.0)", title: $0.1, chapterCount: $0.2, unit: .chapter) }
    }

    private static func placeholder(_ id: String, _ title: String, _ hex: UInt32) -> LibraryWork {
        LibraryWork(id: id, title: title, subtitle: "", coverHex: hex, summary: "", volumes: [])
    }
}

/// The user's reading state, reduced to what the Library draws.
struct LibraryProgress {
    var read: Set<String> = []
    var current: String?
    var marked: Set<String> = []

    init(progress: [ReadingProgress], highlights: [Highlight]) {
        read = Set(progress.filter { $0.completedAt != nil }.map(\.chapterID))
        current = progress
            .filter { $0.completedAt == nil }
            .max { $0.updatedAt < $1.updatedAt }?
            .chapterID
        marked = Set(highlights.map(\.chapterID))
    }

    func isReading(_ book: LibraryBook) -> Bool {
        guard let current else { return false }
        return book.contains(chapterID: current)
    }

    func isReading(_ work: LibraryWork) -> Bool {
        work.books.contains { isReading($0) }
    }
}
