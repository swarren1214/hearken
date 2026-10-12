import Foundation
import PDFKit
import Vision

/// Reads a PDF's text for the Hearken reader: chapters from the outline (or every ten pages),
/// with the printed lines rejoined into paragraphs. Pages without a text layer (scans) are
/// read with Vision's text recognition.
nonisolated enum PDFTextExtractor {
    enum ExtractError: LocalizedError {
        case unreadable
        case locked
        case noText

        var errorDescription: String? {
            switch self {
            case .unreadable: "The PDF couldn't be opened."
            case .locked: "The PDF is password protected."
            case .noText: "Hearken couldn't find any text in this PDF."
            }
        }
    }

    static let pagesPerSection = 10

    static func details(of url: URL) throws -> BookDetails {
        guard let document = PDFDocument(url: url) else { throw ExtractError.unreadable }
        if document.isLocked { throw ExtractError.locked }
        guard document.pageCount > 0 else { throw ExtractError.noText }
        let attributes = document.documentAttributes ?? [:]
        let title = (attributes[PDFDocumentAttribute.titleAttribute] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let author = (attributes[PDFDocumentAttribute.authorAttribute] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sections = outlineSections(document)
        return BookDetails(
            title: usableTitle(title) ?? url.deletingPathExtension().lastPathComponent,
            author: author,
            coverData: document.page(at: 0).flatMap { pageImage($0, longSide: 900) }.flatMap { ImageTools.jpeg($0) },
            chapterCount: sections.isEmpty ? Int((Double(document.pageCount) / Double(pagesPerSection)).rounded(.up)) : sections.count,
            pageCount: document.pageCount
        )
    }

    static func content(of url: URL, progress: @Sendable (Double) -> Void) throws -> ImportedContent {
        guard let document = PDFDocument(url: url) else { throw ExtractError.unreadable }
        if document.isLocked { throw ExtractError.locked }
        let pageCount = document.pageCount
        guard pageCount > 0 else { throw ExtractError.noText }

        // Each page's lines, read once.
        var pages: [[String]] = []
        pages.reserveCapacity(pageCount)
        for index in 0..<pageCount {
            progress(Double(index) / Double(pageCount) * 0.95)
            guard let page = document.page(at: index) else {
                pages.append([])
                continue
            }
            var lines = textLines(page.string ?? "")
            if lines.joined().count < 25 {
                // No text layer, or next to none: probably a scan.
                lines = recognizedLines(page)
            }
            pages.append(lines)
        }
        let cleaned = removingRunningHeads(pages)

        var sections = outlineSections(document)
        if sections.isEmpty {
            sections = stride(from: 0, to: pageCount, by: pagesPerSection).map { start in
                let end = min(start + pagesPerSection, pageCount)
                return (title: start + 1 == end ? "Page \(end)" : "Pages \(start + 1)–\(end)", page: start)
            }
        } else if sections[0].page > 0 {
            // Front matter before the first outline entry.
            sections.insert((title: "Opening Pages", page: 0), at: 0)
        }

        var chapters: [ImportedChapter] = []
        for (i, section) in sections.enumerated() {
            let end = i + 1 < sections.count ? sections[i + 1].page : pageCount
            guard section.page < end else { continue }
            let lines = cleaned[section.page..<end].flatMap { $0 + [""] }
            var paragraphs = rebuildParagraphs(lines)
            if let first = paragraphs.first, first.compare(section.title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
                paragraphs.removeFirst()
            }
            guard !paragraphs.isEmpty else { continue }
            chapters.append(ImportedChapter(title: section.title, paragraphs: paragraphs, startPage: section.page + 1))
        }
        progress(1)
        guard !chapters.isEmpty else { throw ExtractError.noText }
        return ImportedContent(chapters: chapters)
    }

    /// The page as an image, `longSide` pixels on its long side.
    static func pageImage(_ page: PDFPage, longSide: CGFloat) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = longSide / max(bounds.width, bounds.height)
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        return page.thumbnail(of: size, for: .mediaBox).cgImage
    }

    // MARK: Outline

    /// Top-level outline entries with their page indexes, in page order. When the outline has
    /// a single top-level entry (the book's title), its children are used instead.
    private static func outlineSections(_ document: PDFDocument) -> [(title: String, page: Int)] {
        guard var level = document.outlineRoot else { return [] }
        if level.numberOfChildren == 1, let only = level.child(at: 0), only.numberOfChildren > 1 {
            level = only
        }
        var sections: [(title: String, page: Int)] = []
        for index in 0..<level.numberOfChildren {
            guard let item = level.child(at: index),
                  let page = item.destination?.page,
                  let label = item.label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty else { continue }
            let pageIndex = document.index(for: page)
            guard pageIndex != NSNotFound else { continue }
            sections.append((title: label, page: pageIndex))
        }
        sections.sort { $0.page < $1.page }
        // Two entries on one page: keep the first.
        var seen = Set<Int>()
        sections = sections.filter { seen.insert($0.page).inserted }
        return sections.count >= 2 ? sections : []
    }

    // MARK: Text

    private static func textLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Lines read from the page image, top to bottom.
    private static func recognizedLines(_ page: PDFPage) -> [String] {
        guard let image = pageImage(page, longSide: 2200) else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image)
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        let observations = (request.results ?? []).sorted {
            // Vision's coordinates start at the bottom left.
            abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.008
                ? $0.boundingBox.midY > $1.boundingBox.midY
                : $0.boundingBox.minX < $1.boundingBox.minX
        }
        var lines: [String] = []
        var previous: CGRect?
        for observation in observations {
            guard let text = observation.topCandidates(1).first?.string else { continue }
            // A gap bigger than a line and a half is a paragraph break.
            if let previous, previous.minY - observation.boundingBox.maxY > previous.height * 1.5 {
                lines.append("")
            }
            lines.append(text)
            previous = observation.boundingBox
        }
        return lines
    }

    /// Drops page numbers and running heads: short lines that repeat at the top or bottom of many pages.
    private static func removingRunningHeads(_ pages: [[String]]) -> [[String]] {
        func key(_ line: String) -> String {
            line.lowercased().filter(\.isLetter)
        }
        var counts: [String: Int] = [:]
        for lines in pages {
            let edges = lines.filter { !$0.isEmpty }
            for line in edges.prefix(2) + edges.suffix(2) where line.count < 80 {
                let k = key(line)
                if !k.isEmpty { counts[k, default: 0] += 1 }
            }
        }
        let threshold = max(3, pages.count / 4)
        return pages.map { lines in
            let nonEmpty = lines.indices.filter { !lines[$0].isEmpty }
            let edgeIndexes = Set(nonEmpty.prefix(2) + nonEmpty.suffix(2))
            return lines.enumerated().compactMap { index, line in
                guard edgeIndexes.contains(index) else { return line }
                if isPageNumber(line) { return nil }
                if line.count < 80, (counts[key(line)] ?? 0) >= threshold { return nil }
                return line
            }
        }
    }

    private static func isPageNumber(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "-–—[]()")))
        if !trimmed.isEmpty, trimmed.allSatisfy(\.isNumber) { return true }
        if trimmed.lowercased().hasPrefix("page "), trimmed.dropFirst(5).allSatisfy({ $0.isNumber || $0 == " " || $0.isLetter && "of".contains($0) }) { return true }
        // Roman numerals in front matter.
        let roman = Set("ivxlcdm")
        return !trimmed.isEmpty && trimmed.count <= 6 && trimmed.lowercased().allSatisfy { roman.contains($0) }
    }

    /// Joins printed lines into paragraphs. A paragraph ends at a blank line, or where a line
    /// that ends a sentence is clearly shorter than the lines around it. Words hyphenated
    /// across a line break are rejoined.
    static func rebuildParagraphs(_ lines: [String]) -> [String] {
        let lengths = lines.map(\.count).filter { $0 > 20 }.sorted()
        let typical = lengths.isEmpty ? 60 : lengths[lengths.count * 3 / 4]
        var paragraphs: [String] = []
        var current = ""

        func flush() {
            let text = MarkupText.collapse(current)
            if !text.isEmpty { paragraphs.append(text) }
            current = ""
        }

        for (index, line) in lines.enumerated() {
            if line.isEmpty {
                flush()
                continue
            }
            if current.isEmpty {
                current = line
            } else if current.hasSuffix("-"), let last = current.dropLast().last, last.isLetter,
                      let next = line.first, next.isLowercase {
                current.removeLast()
                current += line
            } else {
                current += " " + line
            }

            let endsSentence = line.last.map { ".!?:;\"'”’)".contains($0) } ?? false
            let isShort = line.count < Int(Double(typical) * 0.72)
            let nextLine = index + 1 < lines.count ? lines[index + 1] : ""
            let nextStartsNew = nextLine.first.map { $0.isUppercase || $0.isNumber || "\"“‘(".contains($0) } ?? true
            if endsSentence && isShort && nextStartsNew {
                flush()
            }
        }
        flush()
        return paragraphs
    }

    private static func usableTitle(_ title: String) -> String? {
        let lowered = title.lowercased()
        // Titles some tools write by default.
        if title.isEmpty || lowered == "untitled" || lowered.hasPrefix("microsoft word") || lowered.hasSuffix(".doc") || lowered.hasSuffix(".docx") || lowered.hasSuffix(".pdf") {
            return nil
        }
        return title
    }
}
