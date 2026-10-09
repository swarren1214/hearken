import Testing
@testable import Hearken

@MainActor
struct LibraryCatalogTests {
    private func chapters(_ work: LibraryWork) -> Int {
        work.books.reduce(0) { $0 + $1.chapterCount }
    }

    @Test func standardWorksHaveTheirRealChapterCounts() {
        #expect(LibraryCatalog.bible.volumes.map { $0.books.count } == [39, 27])
        #expect(chapters(LibraryCatalog.bible) == 1_189)
        #expect(chapters(LibraryCatalog.bookOfMormon) == 239)
        #expect(LibraryCatalog.bookOfMormon.books.count == 15)
        #expect(chapters(LibraryCatalog.doctrineAndCovenants) == 138)
        #expect(chapters(LibraryCatalog.pearlOfGreatPrice) == 16)
    }

    @Test func chapterIDsMatchTheContentScheme() {
        let alma = LibraryCatalog.bookOfMormon.books.first { $0.title == "Alma" }
        #expect(alma?.chapterID(32) == "bofm.alma.32")
        let psalms = LibraryCatalog.bible.books.first { $0.title == "Psalms" }
        #expect(psalms?.chapterID(23) == "ot.ps.23")
        #expect(alma?.contains(chapterID: "bofm.alma.32") == true)
        #expect(alma?.contains(chapterID: "bofm.almanac.1") == false)
    }

    @Test func bookIDsAreUnique() {
        let ids = LibraryCatalog.shelves.flatMap(\.works).flatMap(\.books).map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func onlyMultiVolumeWorksShowTheVolumeLevel() {
        #expect(LibraryCatalog.bible.hasVolumeLevel)
        #expect(!LibraryCatalog.bookOfMormon.hasVolumeLevel)
    }

    @Test func pageTurnsCrossBooksButNotWorks() {
        #expect(LibraryCatalog.adjacentChapter(to: "ot.gen.50", offset: 1) == "ot.ex.1")
        #expect(LibraryCatalog.adjacentChapter(to: "ot.ex.1", offset: -1) == "ot.gen.50")
        #expect(LibraryCatalog.adjacentChapter(to: "ot.mal.4", offset: 1) == "nt.matt.1")
        #expect(LibraryCatalog.adjacentChapter(to: "bofm.alma.32", offset: 1) == "bofm.alma.33")
        #expect(LibraryCatalog.adjacentChapter(to: "ot.gen.1", offset: -1) == nil)
        #expect(LibraryCatalog.adjacentChapter(to: "nt.rev.22", offset: 1) == nil)
    }

    @Test func typedReferencesResolve() {
        #expect(LibraryCatalog.parseReference("Alma 32:27")?.chapterID == "bofm.alma.32")
        #expect(LibraryCatalog.parseReference("alma 32:27")?.verse == 27)
        #expect(LibraryCatalog.parseReference("1 ne 3")?.chapterID == "bofm.1-ne.3")
        #expect(LibraryCatalog.parseReference("mt 5:3")?.chapterID == "nt.matt.5")
        #expect(LibraryCatalog.parseReference("D&C 76:22")?.chapterID == "dc-testament.dc.76")
        #expect(LibraryCatalog.parseReference("Psalm 23")?.chapterID == "ot.ps.23")
        #expect(LibraryCatalog.parseReference("Alma 99") == nil)
        #expect(LibraryCatalog.parseReference("faith") == nil)
    }
}
