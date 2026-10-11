import Foundation
import Testing
import UIKit
@testable import Hearken

/// The reader maps between characters on screen and verse positions; highlights, notes and
/// selections are all stored in verse terms, so these mappings must stay exact.
@MainActor
struct ChapterTextLayoutTests {
    private let verses = [
        Verse(id: "test.1.1", number: 1, text: "In the beginning."),
        Verse(id: "test.1.2", number: 2, text: "And the earth was without form."),
        Verse(id: "test.1.10", number: 10, text: "Ten."),
    ]

    private func layout(numbers: Bool = true) -> ChapterTextLayout {
        ChapterTextLayout(verses: verses, fontSize: 19, showNumbers: numbers, tint: .systemBlue, highlights: [], noteVerses: [])
    }

    @Test func spansCoverExactlyTheVerseText() {
        let built = layout()
        let string = built.attributed.string as NSString
        for (span, verse) in zip(built.spans, verses) {
            #expect(string.substring(with: span.text) == verse.text)
        }
    }

    @Test func verseNumbersSitOutsideTheVerseText() {
        let built = layout()
        let string = built.attributed.string as NSString
        for (span, verse) in zip(built.spans, verses) {
            let before = NSRange(location: span.paragraph.location, length: span.text.location - span.paragraph.location)
            #expect(string.substring(with: before).contains("\(verse.number)"))
            #expect(!string.substring(with: span.text).hasPrefix("\(verse.number)"))
        }
    }

    @Test func positionsRoundTrip() throws {
        let built = layout()
        for span in built.spans {
            let index = span.text.location + 3
            let position = try #require(built.position(at: index, preferEnd: false))
            #expect(position == VersePosition(verse: span.verse, offset: 3))
            #expect(built.characterIndex(of: position) == index)
        }
    }

    @Test func anIndexInsideAVerseNumberSnapsToTheStartOfThatVerse() {
        let built = layout()
        let second = built.spans[1]
        #expect(built.position(at: second.paragraph.location + 1, preferEnd: false) == VersePosition(verse: 2, offset: 0))
    }

    @Test func theEndOfAVerseIsStoredAsMinusOne() {
        let built = layout()
        let first = built.spans[0]
        #expect(built.position(at: NSMaxRange(first.text), preferEnd: true) == VersePosition(verse: 1, offset: -1))
    }

    @Test func withoutNumbersTheTextStartsTheParagraph() {
        let built = layout(numbers: false)
        #expect(built.spans[0].text.location == built.spans[0].paragraph.location)
    }
}
