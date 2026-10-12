import Foundation
import NaturalLanguage

// Turns a parsed book into chapters of verses (ImportedContent version 2).
//
// Verses are added only when the text doesn't already number them: a chapter whose
// paragraphs start with printed verse numbers keeps them exactly. Otherwise a verse is a
// paragraph, or 2 or 3 sentences of a long one, cut only at sentence ends.
//
// Chapters come from the strongest evidence available: the file's own table of contents,
// then headings found in the text ("Chapter 12", "PSALM 23"), then printed numbering that
// starts again at 1, then even parts of about 1,500 words for whatever is still too long.
//
// Every verse is an exact piece of one source paragraph, and each keeps where it came from
// (VerseOrigin), so highlights made on an older version of a book can be moved onto the new
// verses without losing their place.

/// A chapter as a parser found it, before verses and parts.
nonisolated struct RawChapter: Sendable {
    var title: String?
    var titleSource: ImportedChapter.TitleSource
    var paragraphs: [String]
    /// PDFs: the page (from 1) each paragraph starts on.
    var pages: [Int]?

    init(title: String?, titleSource: ImportedChapter.TitleSource, paragraphs: [String], pages: [Int]? = nil) {
        self.title = title
        self.titleSource = titleSource
        self.paragraphs = paragraphs
        self.pages = pages
    }
}

/// Where a verse's text starts: a raw chapter, a paragraph in it, and a UTF-16 offset.
nonisolated struct VerseOrigin: Sendable, Hashable {
    let chapter: Int
    let paragraph: Int
    let offset: Int
}

nonisolated struct StructuredBook: Sendable {
    var content: ImportedContent
    /// For each chapter of `content`, where each of its verses came from.
    var origins: [[VerseOrigin]]
}

/// The numbers the rules use, in one place so they can be tuned after reading real books.
nonisolated enum VerseRules {
    /// A paragraph up to this many characters is one verse.
    static let maxVerse = 400
    /// A group of sentences keeps growing until it reaches this, even past 3 sentences.
    static let minGroup = 150
    static let maxSentences = 3
    /// A last group shorter than this joins the one before it.
    static let orphan = 60
    /// A single sentence longer than this is cut at a semicolon, colon or dash.
    static let runaway = 600
    /// Poetry: a stanza up to this many lines is one verse; longer ones go 4 lines at a time.
    static let stanzaLines = 6
    static let linesPerVerse = 4
    /// Chapters with more words than this are cut into parts of about `partWords`.
    static let splitAbove = 3_000
    static let partWords = 1_500
    /// The share of a chapter's paragraphs that must start with a printed number.
    static let printedShare = 0.7
}

nonisolated enum BookStructurer {
    /// A paragraph as it moves through the rules, with where it came from.
    private struct Para {
        var text: String
        let chapter: Int
        let paragraph: Int
        /// UTF-16 offset of `text` within the source paragraph.
        var offset: Int
        let page: Int?
        /// A scene break ("* * *") came just before it.
        var afterBreak = false
    }

    private struct Verse {
        let text: String
        let origin: VerseOrigin
        let page: Int?
        var number: Int?
        /// Starts a source paragraph (or follows a scene break): a good place to start a part.
        var startsParagraph: Bool
        var afterBreak: Bool
    }

    private struct WorkChapter {
        var title: String?
        var source: ImportedChapter.TitleSource
        var number: Int?
        var summary: String?
        var paras: [Para] = []
        var verses: [Verse] = []
        var printed = false
    }

    // MARK: Entry point

    static func structure(_ raws: [RawChapter], progress: @Sendable (Double) -> Void = { _ in }) -> StructuredBook {
        // Consecutive untitled chapters (a PDF's "Pages 1–10" blocks) become one run of text,
        // so parts can be cut at real breaks instead of every 10 pages.
        var chapters = mergeGeneric(raws.enumerated().map { index, raw in work(from: raw, index: index) })
        progress(0.15)

        chapters = chapters.flatMap(splitAtHeadings)
        progress(0.3)

        var output: [WorkChapter] = []
        for (index, chapter) in chapters.enumerated() {
            output += versify(chapter)
            progress(0.3 + 0.6 * Double(index + 1) / Double(max(chapters.count, 1)))
        }
        output = output.filter { !$0.verses.isEmpty }
        output = output.flatMap(splitLong)
        output = mergeTiny(output)
        progress(1)

        let printedCount = output.filter(\.printed).count
        var genericCount = 0
        var importedChapters: [ImportedChapter] = []
        var origins: [[VerseOrigin]] = []
        for chapter in output {
            var title = chapter.title
            var source = chapter.source
            if title == nil || title?.isEmpty == true {
                if let number = chapter.number {
                    title = "Chapter \(number)"
                    source = .heading
                } else {
                    genericCount += 1
                    title = "Part \(genericCount)"
                    source = .generic
                }
            }
            let numbers = chapter.verses.map(\.number)
            let printedNumbers: [Int]? = chapter.printed && numbers.allSatisfy({ $0 != nil }) && isIncreasing(numbers.compactMap { $0 })
                ? numbers.compactMap { $0 } : nil
            importedChapters.append(ImportedChapter(
                title: title ?? "",
                paragraphs: chapter.verses.map(\.text),
                startPage: chapter.verses.first?.page,
                number: chapter.number,
                titleSource: source,
                verseNumbers: printedNumbers,
                summary: chapter.summary
            ))
            origins.append(chapter.verses.map(\.origin))
        }
        let numbering: ImportedContent.Numbering = printedCount * 2 > output.count ? .printed : .generated
        return StructuredBook(content: ImportedContent(numbering: numbering, chapters: importedChapters), origins: origins)
    }

    // MARK: Chapters from the parser

    private static func work(from raw: RawChapter, index: Int) -> WorkChapter {
        var chapter = WorkChapter(title: raw.title, source: raw.titleSource)
        if let title = raw.title, let parsed = ChapterHeading.parse(title) {
            chapter.number = parsed.number
            chapter.title = parsed.title
        }
        if raw.title.map(isPageRangeTitle) == true {
            chapter.title = nil
            chapter.source = .generic
        }
        var afterBreak = false
        for (p, text) in raw.paragraphs.enumerated() {
            if isSceneBreak(text) {
                afterBreak = true
                continue
            }
            var para = Para(text: text, chapter: index, paragraph: p, offset: 0, page: raw.pages?[safe: p])
            para.afterBreak = afterBreak
            afterBreak = false
            chapter.paras.append(para)
        }
        // The title repeated as the first paragraph.
        if let first = chapter.paras.first, let title = raw.title, sameWords(first.text, title) {
            chapter.paras.removeFirst()
        }
        return chapter
    }

    private static func mergeGeneric(_ chapters: [WorkChapter]) -> [WorkChapter] {
        var result: [WorkChapter] = []
        for chapter in chapters {
            if chapter.source == .generic, chapter.title == nil, let last = result.last, last.source == .generic, last.title == nil {
                result[result.count - 1].paras += chapter.paras
            } else {
                result.append(chapter)
            }
        }
        return result
    }

    /// Starts a new chapter at each heading line inside a chapter.
    private static func splitAtHeadings(_ chapter: WorkChapter) -> [WorkChapter] {
        let words = chapter.paras.reduce(0) { $0 + wordCount($1.text) }
        let allowsWeak = words > VerseRules.splitAbove
        var result: [WorkChapter] = []
        var current = chapter
        current.paras = []

        for (index, para) in chapter.paras.enumerated() {
            let next = index + 1 < chapter.paras.count ? chapter.paras[index + 1].text : nil
            guard let heading = ChapterHeading.detect(para.text, next: next, allowsWeak: allowsWeak) else {
                current.paras.append(para)
                continue
            }
            if current.paras.isEmpty {
                // A heading at the very start, or right after another heading ("BOOK I", then
                // "CHAPTER 1"): it names this chapter.
                if current.title == nil || current.source == .generic || result.isEmpty && current.source != .file {
                    current.title = heading.title
                    current.source = .heading
                } else if current.summary == nil, !sameWords(current.title ?? "", heading.title ?? "") {
                    current.summary = heading.title
                }
                if let number = heading.number { current.number = number }
                continue
            }
            result.append(current)
            current = WorkChapter(title: heading.title, source: .heading, number: heading.number)
        }
        result.append(current)
        return result.filter { !$0.paras.isEmpty || $0.summary != nil }
    }

    // MARK: Verses

    /// One chapter's verses: printed ones when the text has them, generated otherwise. A
    /// printed chapter whose numbering starts again at 1 becomes two chapters.
    private static func versify(_ chapter: WorkChapter) -> [WorkChapter] {
        if PrintedVerses.isNumbered(chapter.paras.map(\.text)) {
            return printedVerses(chapter)
        }
        var result = chapter
        result.verses = chapter.paras.flatMap { para in
            VerseSplitter.split(para.text).enumerated().map { index, piece in
                Verse(
                    text: piece.text,
                    origin: VerseOrigin(chapter: para.chapter, paragraph: para.paragraph, offset: para.offset + piece.offset),
                    page: para.page,
                    startsParagraph: index == 0,
                    afterBreak: index == 0 && para.afterBreak
                )
            }
        }
        return [result]
    }

    private static func printedVerses(_ chapter: WorkChapter) -> [WorkChapter] {
        var chapters: [WorkChapter] = []
        var current = chapter
        current.verses = []
        current.printed = true
        var summary: [String] = []

        func finish() {
            if !summary.isEmpty {
                let text = summary.joined(separator: " ")
                current.summary = current.summary.map { "\($0) \(text)" } ?? text
                summary = []
            }
            chapters.append(current)
        }

        func append(_ piece: PrintedVerses.Piece, _ para: Para) {
            guard let number = piece.number else { return }
            if number == 1, let last = current.verses.last?.number, last > 1 {
                // The numbering starts again at 1: a new chapter.
                if current.number == nil && chapters.isEmpty { current.number = 1 }
                finish()
                let previous = current.number ?? chapters.count
                current = WorkChapter(title: nil, source: .heading, number: previous + 1)
                current.printed = true
            }
            current.verses.append(Verse(
                text: piece.text,
                origin: VerseOrigin(chapter: para.chapter, paragraph: para.paragraph, offset: para.offset + piece.offset),
                page: para.page,
                number: number,
                startsParagraph: true,
                afterBreak: para.afterBreak
            ))
        }

        for para in chapter.paras {
            let pieces = PrintedVerses.split(para.text)
            guard let first = pieces.first, first.number == nil else {
                for piece in pieces { append(piece, para) }
                continue
            }
            // Text with no number of its own: a summary before verse 1, or the rest of the
            // verse before it (a PDF line break), joined back on.
            if !first.text.isEmpty {
                if current.verses.isEmpty {
                    summary.append(first.text)
                } else {
                    let last = current.verses.removeLast()
                    current.verses.append(Verse(
                        text: last.text + " " + first.text, origin: last.origin, page: last.page, number: last.number,
                        startsParagraph: last.startsParagraph, afterBreak: last.afterBreak
                    ))
                }
            }
            for piece in pieces.dropFirst() { append(piece, para) }
        }

        finish()
        return chapters
    }

    // MARK: Parts

    /// Cuts a long chapter of generated verses into parts of about 1,500 words, at a scene
    /// break where there is one near the target, else at the start of a paragraph. Printed
    /// chapters are never cut.
    private static func splitLong(_ chapter: WorkChapter) -> [WorkChapter] {
        guard !chapter.printed else { return [chapter] }
        let counts = chapter.verses.map { wordCount($0.text) }
        let total = counts.reduce(0, +)
        guard total > VerseRules.splitAbove else { return [chapter] }

        let partCount = max(2, Int((Double(total) / Double(VerseRules.partWords)).rounded()))
        let target = Double(total) / Double(partCount)
        var cuts: [Int] = []
        var start = 0
        while cuts.count < partCount - 1 {
            var sum = 0.0
            var bestBreak: Int?
            var firstParagraph: Int?
            var fallback: Int?
            var index = start
            while index < chapter.verses.count {
                sum += Double(counts[index])
                let next = index + 1
                guard next < chapter.verses.count else { break }
                let verse = chapter.verses[next]
                if sum >= target * 0.8 && sum <= target * 1.2 && verse.afterBreak && bestBreak == nil { bestBreak = next }
                if sum >= target && verse.startsParagraph && firstParagraph == nil { firstParagraph = next }
                if sum >= target * 1.2 && fallback == nil { fallback = next }
                if sum > target * 1.2 && (bestBreak != nil || firstParagraph != nil || fallback != nil) { break }
                index += 1
            }
            guard let cut = bestBreak ?? (firstParagraph.map { $0 } ?? fallback), cut > start, cut < chapter.verses.count else { break }
            cuts.append(cut)
            start = cut
        }
        guard !cuts.isEmpty else { return [chapter] }

        let bounds = [0] + cuts + [chapter.verses.count]
        let count = bounds.count - 1
        return (0..<count).map { part in
            var piece = chapter
            piece.verses = Array(chapter.verses[bounds[part]..<bounds[part + 1]])
            if let title = chapter.title, chapter.source != .generic {
                piece.title = "\(title) (\(part + 1) of \(count))"
            } else {
                piece.title = nil
                piece.source = .generic
            }
            if part > 0 { piece.summary = nil }
            // Parts share the chapter's printed number, so references number them by position instead.
            piece.number = nil
            return piece
        }
    }

    /// A tiny untitled part (a stray title page) joins the chapter after it.
    private static func mergeTiny(_ chapters: [WorkChapter]) -> [WorkChapter] {
        var result: [WorkChapter] = []
        var carry: WorkChapter?
        for var chapter in chapters {
            if let pending = carry {
                if chapter.printed {
                    result.append(pending)
                } else {
                    chapter.verses = pending.verses + chapter.verses
                }
                carry = nil
            }
            let words = chapter.verses.reduce(0) { $0 + wordCount($1.text) }
            if words < 150, chapter.source == .generic, chapter.title == nil, !chapter.printed {
                carry = chapter
            } else {
                result.append(chapter)
            }
        }
        if let pending = carry {
            if let last = result.indices.last, !result[last].printed {
                result[last].verses += pending.verses
            } else {
                result.append(pending)
            }
        }
        return result
    }

    // MARK: Helpers

    static func wordCount(_ text: String) -> Int {
        var count = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            let isSpace = CharacterSet.whitespacesAndNewlines.contains(scalar)
            if !isSpace && !inWord { count += 1 }
            inWord = !isSpace
        }
        return count
    }

    private static func isIncreasing(_ numbers: [Int]) -> Bool {
        zip(numbers, numbers.dropFirst()).allSatisfy { $0 < $1 }
    }

    static func isSceneBreak(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 12 else { return false }
        return trimmed.allSatisfy { "*·•⁂§#~—–-_=+◆◇❦✠†. ".contains($0) }
    }

    private static func isPageRangeTitle(_ title: String) -> Bool {
        title.range(of: #"^Pages? \d+(–\d+)?$"#, options: .regularExpression) != nil
    }

    static func sameWords(_ a: String, _ b: String) -> Bool {
        let fold = { (s: String) in s.lowercased().filter { $0.isLetter || $0.isNumber } }
        let x = fold(a), y = fold(b)
        return !x.isEmpty && x == y
    }
}

// MARK: - Headings

nonisolated enum ChapterHeading {
    struct Found {
        var title: String?
        var number: Int?
    }

    private static let words = "chapter|chap\\.|psalm|section|book|part|canto|sura|epistle"

    /// "Chapter 12", "CHAPTER XII. OF THE WATCHERS", "Psalm 23", "Book II" → its number and
    /// the words after it (or the heading itself, tidied, when there are none).
    static func parse(_ text: String) -> Found? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = "^(\(words))\\s+([0-9]{1,4}|[IVXLCDM]{1,8}|[ivxlcdm]{1,8})\\b\\.?[:.—–-]?\\s*(.*)$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let wordRange = Range(match.range(at: 1), in: trimmed),
              let numberRange = Range(match.range(at: 2), in: trimmed) else {
            // A bare number or roman numeral ("12", "XII.") as a title.
            let bare = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            // Roman numerals only in capitals ("XII"), so words like "Civil" aren't read as numbers.
            let romanValue = bare == bare.uppercased() ? roman(bare) : nil
            if let number = Int(bare) ?? romanValue, bare.count <= 6 {
                return Found(title: "Chapter \(number)", number: number)
            }
            return nil
        }
        let word = String(trimmed[wordRange])
        let numberText = String(trimmed[numberRange])
        guard let number = Int(numberText) ?? roman(numberText) else { return nil }
        let rest = match.range(at: 3).length > 0 ? Range(match.range(at: 3), in: trimmed).map { String(trimmed[$0]) } : nil
        let cleanRest = rest?.trimmingCharacters(in: CharacterSet(charactersIn: " .:—–-")).nilIfEmpty
        let label = word.lowercased().hasPrefix("chap") ? "Chapter" : word.prefix(1).uppercased() + word.dropFirst().lowercased()
        return Found(title: cleanRest.map(titleCase) ?? "\(label) \(number)", number: label == "Chapter" || label == "Psalm" ? number : nil)
    }

    /// A paragraph that reads as a heading: a numbered one ("Chapter 12") always; an
    /// all-capitals short line followed by ordinary prose only in long chapters.
    static func detect(_ text: String, next: String?, allowsWeak: Bool) -> Found? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 80, !trimmed.contains("\n") else { return nil }
        if let found = parse(trimmed), trimmed.range(of: "^(\(words))\\s", options: [.regularExpression, .caseInsensitive]) != nil,
           (found.title?.count ?? 0) <= 50, trimmed.split(separator: " ").count <= 10 {
            return found
        }
        guard allowsWeak, trimmed.count <= 60, let next, next.count > 80 else { return nil }
        let letters = trimmed.filter(\.isLetter)
        guard letters.count >= 4, letters.allSatisfy({ !$0.isLowercase }), !".,;".contains(trimmed.last ?? " ") else { return nil }
        return Found(title: titleCase(trimmed), number: nil)
    }

    static func roman(_ text: String) -> Int? {
        let values: [Character: Int] = ["i": 1, "v": 5, "x": 10, "l": 50, "c": 100, "d": 500, "m": 1000]
        let chars = Array(text.lowercased())
        guard !chars.isEmpty, chars.allSatisfy({ values[$0] != nil }) else { return nil }
        var total = 0
        for (index, char) in chars.enumerated() {
            let value = values[char] ?? 0
            let next = index + 1 < chars.count ? values[chars[index + 1]] ?? 0 : 0
            total += value < next ? -value : value
        }
        return total > 0 ? total : nil
    }

    /// "OF THE WATCHERS" → "Of the Watchers"; mixed-case text is left alone.
    static func titleCase(_ text: String) -> String {
        guard text == text.uppercased(), text.contains(where: \.isLetter) else { return text }
        let small: Set<String> = ["a", "an", "and", "as", "at", "but", "by", "for", "in", "nor", "of", "on", "or", "the", "to", "unto", "with"]
        return text.lowercased().split(separator: " ").enumerated().map { index, word in
            let w = String(word)
            if index > 0 && small.contains(w) { return w }
            // Roman numerals ("xii") back to capitals; real words ("did", "mix") stay words.
            let numerals: Set<String> = ["ii", "iii", "iv", "vi", "vii", "viii", "ix", "xi", "xii", "xiii", "xiv", "xv", "xvi", "xvii", "xviii", "xix", "xx"]
            if numerals.contains(w) { return w.uppercased() }
            return w.prefix(1).uppercased() + w.dropFirst()
        }.joined(separator: " ")
    }
}

// MARK: - Printed verse numbers

nonisolated enum PrintedVerses {
    struct Piece {
        let number: Int?
        let text: String
        /// UTF-16 offset of `text` in the paragraph.
        let offset: Int
    }

    /// "7 For the", "7. For the", "7For the" (a superscript run together).
    private static let leading = try? NSRegularExpression(pattern: #"^\s*(\d{1,3})(?:[.:)]?\s+|(?=[A-Z‘“"'(\[¶]))(?=\S)"#)
    /// A number after a sentence end, inside a paragraph: "…streets. 2 And it came…".
    private static let inner = try? NSRegularExpression(pattern: #"(?<=[.;:?!’”"'\)\]])\s*(\d{1,3})\s*(?=[A-Z‘“"'(\[¶])"#)

    static func leadingNumber(_ text: String) -> Int? {
        let ns = text as NSString
        guard let match = leading?.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return Int(ns.substring(with: match.range(at: 1)))
    }

    /// Whether a chapter's paragraphs carry printed verse numbers: most start with a number,
    /// and those numbers mostly count up by one (or start again at 1).
    static func isNumbered(_ paragraphs: [String]) -> Bool {
        let substantial = paragraphs.filter { $0.count > 3 }
        guard substantial.count >= 3 else {
            // A short chapter: numbered only if every paragraph runs 1, 2, 3.
            let numbers = substantial.compactMap(leadingNumber)
            return numbers.count == substantial.count && numbers.count >= 2 && numbers.first == 1
                && zip(numbers, numbers.dropFirst()).allSatisfy { $1 == $0 + 1 }
        }
        let numbers = substantial.map(leadingNumber)
        let numbered = numbers.compactMap { $0 }
        guard Double(numbered.count) / Double(substantial.count) >= VerseRules.printedShare else {
            // PDFs often run several verses into one paragraph; count those too.
            let inline = substantial.reduce(0) { $0 + PrintedVerses.split($1).filter { $0.number != nil }.count }
            return inline >= substantial.count * 2 && inline >= 6
        }
        var previous = 0
        var steps = 0
        for number in numbered {
            if number == previous + 1 || number == 1 { steps += 1 }
            previous = number
        }
        return Double(steps) / Double(numbered.count) >= 0.8
    }

    /// A paragraph cut at each printed verse number, numbers removed. The first piece has no
    /// number when the paragraph doesn't start with one.
    static func split(_ text: String) -> [Piece] {
        let ns = text as NSString
        let length = ns.length
        var pieces: [Piece] = []
        var start = 0
        var number: Int?

        if let match = leading?.firstMatch(in: text, range: NSRange(location: 0, length: length)),
           let value = Int(ns.substring(with: match.range(at: 1))) {
            number = value
            start = match.range.location + match.range.length
        }
        var expected = (number ?? 0) + 1
        var searchFrom = start
        while searchFrom < length, let match = inner?.firstMatch(in: text, range: NSRange(location: searchFrom, length: length - searchFrom)) {
            let value = Int(ns.substring(with: match.range(at: 1))) ?? -1
            if value == expected {
                pieces.append(piece(ns, from: start, to: match.range.location, number: number))
                number = value
                start = match.range.location + match.range.length
                expected = value + 1
            }
            searchFrom = match.range.location + max(match.range.length, 1)
        }
        pieces.append(piece(ns, from: start, to: length, number: number))
        return pieces.filter { !$0.text.isEmpty || $0.number != nil }
    }

    private static func piece(_ ns: NSString, from: Int, to: Int, number: Int?) -> Piece {
        let trimmed = VerseSplitter.trimmed(ns, NSRange(location: from, length: max(0, to - from)))
        return Piece(number: number, text: trimmed.text, offset: trimmed.offset)
    }
}

// MARK: - Generated verses

nonisolated enum VerseSplitter {
    /// A paragraph as verses: whole when short, otherwise groups of 2 or 3 sentences. Each
    /// piece is an exact, trimmed substring, with its UTF-16 offset in the paragraph.
    static func split(_ text: String) -> [(text: String, offset: Int)] {
        let ns = text as NSString
        let whole = NSRange(location: 0, length: ns.length)
        guard ns.length > 0 else { return [] }

        if text.contains("\n") {
            return poetry(ns)
        }
        if ns.length <= VerseRules.maxVerse {
            let piece = trimmed(ns, whole)
            return piece.text.isEmpty ? [] : [piece]
        }

        var segments = sentences(text, ns).flatMap { runaway(ns, $0) }
        if segments.isEmpty { segments = [whole] }

        var groups: [[NSRange]] = []
        var current: [NSRange] = []
        var length = 0
        for segment in segments {
            let full = length + segment.length > VerseRules.maxVerse
            let enough = current.count >= VerseRules.maxSentences && length >= VerseRules.minGroup
            if !current.isEmpty && (full || enough) {
                groups.append(current)
                current = []
                length = 0
            }
            current.append(segment)
            length += segment.length
        }
        if !current.isEmpty {
            if length < VerseRules.orphan, !groups.isEmpty {
                groups[groups.count - 1] += current
            } else {
                groups.append(current)
            }
        }
        return groups.compactMap { group in
            guard let first = group.first, let last = group.last else { return nil }
            let range = NSRange(location: first.location, length: last.location + last.length - first.location)
            let piece = trimmed(ns, range)
            return piece.text.isEmpty ? nil : piece
        }
    }

    /// Sentence ranges that together cover the whole paragraph.
    private static func sentences(_ text: String, _ ns: NSString) -> [NSRange] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var starts: [Int] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            starts.append(NSRange(range, in: text).location)
            return true
        }
        guard !starts.isEmpty else { return [] }
        starts[0] = 0
        return starts.enumerated().map { index, start in
            let end = index + 1 < starts.count ? starts[index + 1] : ns.length
            return NSRange(location: start, length: end - start)
        }
    }

    /// A sentence too long to be a verse, cut at the semicolon, colon or dash nearest its middle.
    private static func runaway(_ ns: NSString, _ range: NSRange) -> [NSRange] {
        guard range.length > VerseRules.runaway else { return [range] }
        let middle = range.location + range.length / 2
        var best: Int?
        for mark in ["; ", ": ", " — ", " – ", ", "] {
            var search = NSRange(location: range.location + range.length / 5, length: range.length * 3 / 5)
            while search.length > 0 {
                let found = ns.range(of: mark, options: [], range: search)
                guard found.location != NSNotFound else { break }
                let cut = found.location + found.length
                if best == nil || abs(cut - middle) < abs((best ?? 0) - middle) { best = cut }
                let next = found.location + found.length
                search = NSRange(location: next, length: range.location + range.length * 4 / 5 - next)
            }
            if best != nil { break }
        }
        guard let cut = best, cut > range.location, cut < range.location + range.length else { return [range] }
        return runaway(ns, NSRange(location: range.location, length: cut - range.location))
            + runaway(ns, NSRange(location: cut, length: range.location + range.length - cut))
    }

    /// Lines kept together: a short stanza is one verse, a long one goes 4 lines at a time.
    private static func poetry(_ ns: NSString) -> [(text: String, offset: Int)] {
        var lines: [NSRange] = []
        var start = 0
        while start <= ns.length {
            let found = ns.range(of: "\n", options: [], range: NSRange(location: start, length: ns.length - start))
            let end = found.location == NSNotFound ? ns.length : found.location
            lines.append(NSRange(location: start, length: end - start))
            if found.location == NSNotFound { break }
            start = end + 1
        }
        lines = lines.filter { trimmed(ns, $0).text.isEmpty == false }
        guard !lines.isEmpty else { return [] }
        let total = lines.reduce(0) { $0 + $1.length }
        let perVerse = lines.count <= VerseRules.stanzaLines && total <= VerseRules.runaway ? lines.count : VerseRules.linesPerVerse
        return stride(from: 0, to: lines.count, by: perVerse).map { index in
            let first = lines[index]
            let last = lines[min(index + perVerse, lines.count) - 1]
            return trimmed(ns, NSRange(location: first.location, length: last.location + last.length - first.location))
        }
    }

    /// The substring with surrounding whitespace removed, and where it starts.
    static func trimmed(_ ns: NSString, _ range: NSRange) -> (text: String, offset: Int) {
        var start = range.location
        var end = range.location + range.length
        let space = CharacterSet.whitespacesAndNewlines
        while start < end, let scalar = Unicode.Scalar(ns.character(at: start)), space.contains(scalar) { start += 1 }
        while end > start, let scalar = Unicode.Scalar(ns.character(at: end - 1)), space.contains(scalar) { end -= 1 }
        return (ns.substring(with: NSRange(location: start, length: end - start)), start)
    }
}

private nonisolated extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private nonisolated extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
