import SwiftUI

/// A reading plan: an ordered list of chapters spread over a number of reading days.
struct ReadingPlan: Identifiable, Hashable {
    static let customID = "custom"

    let id: String
    let title: String
    let subtitle: String
    /// Reading days, not calendar days (a weekdays-only plan takes longer on the calendar).
    let days: Int
    let coverHex: UInt32
    let chapterIDs: [String]

    var isCustom: Bool { id == Self.customID }
    var coverColor: Color { Color(hex: coverHex) }
}

/// The plans Hearken offers, built from the Library's real chapter lists.
enum ReadingPlanCatalog {
    static let plans: [ReadingPlan] = [
        ReadingPlan(id: "bofm-90", title: "Book of Mormon in 90 Days", subtitle: "1 Nephi to Moroni",
                    days: 90, coverHex: LibraryCatalog.bookOfMormon.coverHex, chapterIDs: chapters(of: LibraryCatalog.bookOfMormon.books)),
        ReadingPlan(id: "bofm-180", title: "Book of Mormon in 6 Months", subtitle: "1 Nephi to Moroni",
                    days: 180, coverHex: LibraryCatalog.bookOfMormon.coverHex, chapterIDs: chapters(of: LibraryCatalog.bookOfMormon.books)),
        ReadingPlan(id: "nt-180", title: "New Testament in 6 Months", subtitle: "Matthew to Revelation",
                    days: 180, coverHex: 0x6B2A2A, chapterIDs: chapters(of: volume("nt"))),
        ReadingPlan(id: "dc-120", title: "Doctrine and Covenants in 120 Days", subtitle: "Sections 1–138",
                    days: 120, coverHex: LibraryCatalog.doctrineAndCovenants.coverHex, chapterIDs: chapters(of: LibraryCatalog.doctrineAndCovenants.books)),
        ReadingPlan(id: "ot-365", title: "Old Testament in a Year", subtitle: "Genesis to Malachi",
                    days: 365, coverHex: LibraryCatalog.bible.coverHex, chapterIDs: chapters(of: volume("ot"))),
        ReadingPlan(id: "pgp-14", title: "Pearl of Great Price in 2 Weeks", subtitle: "Moses to the Articles of Faith",
                    days: 14, coverHex: LibraryCatalog.pearlOfGreatPrice.coverHex, chapterIDs: chapters(of: LibraryCatalog.pearlOfGreatPrice.books)),
    ]

    /// Placeholder for the Custom Plan row; the real plan is built in the start sheet.
    static let custom = ReadingPlan(id: ReadingPlan.customID, title: "Custom Plan", subtitle: "Pick books and how many days",
                                    days: 30, coverHex: 0x8E8E93, chapterIDs: [])

    /// The plan an enrollment follows. Custom plans carry their own chapters and title.
    static func plan(for enrollment: PlanEnrollment) -> ReadingPlan? {
        if enrollment.planID == ReadingPlan.customID {
            guard !enrollment.customChapterIDs.isEmpty else { return nil }
            return ReadingPlan(id: ReadingPlan.customID, title: enrollment.customTitle.isEmpty ? "Custom Plan" : enrollment.customTitle,
                               subtitle: PlanFormat.range(enrollment.customChapterIDs), days: enrollment.totalDays,
                               coverHex: 0x5A5A63, chapterIDs: enrollment.customChapterIDs)
        }
        return plans.first { $0.id == enrollment.planID }
    }

    static func chapters(of books: [LibraryBook]) -> [String] {
        books.flatMap { book in (1...book.chapterCount).map(book.chapterID) }
    }

    private static func volume(_ id: String) -> [LibraryBook] {
        LibraryCatalog.bible.volumes.first { $0.id == id }?.books ?? []
    }
}

/// Names for chapters and runs of chapters, e.g. "Alma 5–7" or "Mosiah 29 – Alma 2".
enum PlanFormat {
    static func bookName(_ book: LibraryBook) -> String {
        book.id == "dc-testament.dc" ? "D&C" : book.title
    }

    static func chapterName(_ id: String) -> String {
        guard let location = LibraryCatalog.location(ofChapter: id) else { return id }
        return "\(bookName(location.book)) \(location.number)"
    }

    static func range(_ ids: [String]) -> String {
        guard let first = ids.first, let last = ids.last,
              let a = LibraryCatalog.location(ofChapter: first),
              let b = LibraryCatalog.location(ofChapter: last) else { return "" }
        if ids.count == 1 { return "\(bookName(a.book)) \(a.number)" }
        if a.book == b.book { return "\(bookName(a.book)) \(a.number)–\(b.number)" }
        return "\(bookName(a.book)) \(a.number) – \(bookName(b.book)) \(b.number)"
    }

    /// "2–3" or "3": chapters per day.
    static func perDay(chapters: Int, days: Int) -> String {
        guard days > 0 else { return "–" }
        let low = chapters / days
        let high = (chapters + days - 1) / days
        return low == high ? "\(low)" : "\(max(low, 1))–\(high)"
    }

    /// "Jan 6", or "Jan 6, 2028" when it isn't this year.
    static func shortDate(_ date: Date, now: Date = .now) -> String {
        Calendar.current.isDate(date, equalTo: now, toGranularity: .year)
            ? date.formatted(.dateTime.month(.abbreviated).day())
            : date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}
