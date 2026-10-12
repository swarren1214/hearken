import Foundation
import ImageIO
import UniformTypeIdentifiers

/// What the Add to Library sheet shows before a book is added.
nonisolated struct BookDetails: Sendable {
    var title: String
    var author: String
    var coverData: Data?
    /// EPUB: the number of chapters, roughly (spine items). PDF: 0 until prepared.
    var chapterCount: Int
    var pageCount: Int
}

/// Reads EPUB 2 and 3 books: the metadata, the cover, and the text of each chapter in reading
/// order. Chapters follow the table of contents where it splits a file into parts, otherwise
/// each spine document is a chapter.
nonisolated enum EPUBParser {
    enum ParseError: LocalizedError {
        case noPackage
        case noText

        var errorDescription: String? {
            switch self {
            case .noPackage: "The file isn't a valid EPUB."
            case .noText: "Hearken couldn't find any text in this book. It may be protected (DRM), or only images."
            }
        }
    }

    private struct ManifestItem {
        let id: String
        let path: String
        let mediaType: String
        let properties: Set<String>
    }

    private struct Package {
        let archive: ZipArchive
        let opf: MarkupElement
        let manifest: [String: ManifestItem]
        let spine: [ManifestItem]
        let tocItem: ManifestItem?
        let navItem: ManifestItem?
    }

    // MARK: Public

    static func details(of url: URL) throws -> BookDetails {
        let package = try open(url)
        let metadata = package.opf.first("metadata") ?? package.opf
        let title = metadata.first("title")?.text ?? ""
        let authors = metadata.all("creator").map(\.text).filter { !$0.isEmpty }
        let cover = coverItem(in: package).flatMap { try? package.archive.contents(of: $0.path) }
        let readable = package.spine.filter { $0.mediaType.contains("html") && $0.id != package.navItem?.id }
        return BookDetails(
            title: title.isEmpty ? url.deletingPathExtension().lastPathComponent : title,
            author: authors.joined(separator: ", "),
            coverData: cover.flatMap { ImageTools.thumbnail($0, maxPixels: 900) },
            chapterCount: readable.count,
            pageCount: 0
        )
    }

    /// The book's text as chapters of paragraphs, in reading order (BookStructurer adds verses).
    static func chapters(of url: URL, progress: @Sendable (Double) -> Void) throws -> [RawChapter] {
        let package = try open(url)
        let toc = tableOfContents(package)
        var chapters: [RawChapter] = []
        let readable = package.spine.filter { $0.mediaType.contains("html") && $0.id != package.navItem?.id }

        for (index, item) in readable.enumerated() {
            progress(Double(index) / Double(max(readable.count, 1)))
            guard let source = try? package.archive.text(of: item.path) else { continue }

            // The table of contents entries that point into this file, in order.
            let entries = toc.filter { $0.path == item.path }
            let anchors = Set(entries.compactMap(\.fragment))

            var paragraphs: [String]
            var heading: String?
            var markers: [String: Int] = [:]
            if let root = MarkupParser.parse(source) {
                let parsed = MarkupText.paragraphs(in: root, anchors: anchors)
                paragraphs = parsed.paragraphs
                heading = parsed.heading
                markers = parsed.markers
            } else {
                paragraphs = MarkupText.paragraphs(inBrokenMarkup: source)
            }
            guard !paragraphs.isEmpty else { continue }

            let wholeFileTitle = entries.first { $0.fragment == nil }?.title
            let splits = entries
                .compactMap { entry in entry.fragment.flatMap { markers[$0] }.map { (start: $0, title: entry.title) } }
                .sorted { $0.start < $1.start }

            if splits.count >= 2 || (splits.count == 1 && splits[0].start > 0) {
                // One file, several chapters.
                if let firstStart = splits.first?.start, firstStart > 0 {
                    let lead = Array(paragraphs[0..<firstStart])
                    chapters.append(raw(wholeFileTitle, heading, lead))
                }
                for (i, split) in splits.enumerated() {
                    let end = i + 1 < splits.count ? splits[i + 1].start : paragraphs.count
                    guard split.start < end else { continue }
                    chapters.append(RawChapter(title: split.title, titleSource: .file, paragraphs: Array(paragraphs[split.start..<end])))
                }
            } else {
                chapters.append(raw(wholeFileTitle ?? entries.first?.title, heading, paragraphs))
            }
        }
        progress(1)
        let nonEmpty = chapters.filter { !$0.paragraphs.isEmpty }
        guard !nonEmpty.isEmpty else { throw ParseError.noText }
        return nonEmpty
    }

    /// A chapter titled by the table of contents, else by its first heading, else untitled.
    private static func raw(_ tocTitle: String?, _ heading: String?, _ paragraphs: [String]) -> RawChapter {
        if let tocTitle { return RawChapter(title: tocTitle, titleSource: .file, paragraphs: paragraphs) }
        if let heading { return RawChapter(title: heading, titleSource: .heading, paragraphs: paragraphs) }
        return RawChapter(title: nil, titleSource: .generic, paragraphs: paragraphs)
    }

    // MARK: Package

    private static func open(_ url: URL) throws -> Package {
        let archive = try ZipArchive(data: Data(contentsOf: url, options: .mappedIfSafe))

        var opfPath: String?
        if let container = try? archive.contents(of: "META-INF/container.xml"),
           let root = MarkupParser.parse(container) {
            opfPath = root.first("rootfile")?["full-path"]
        }
        if opfPath == nil || !(archive.contains(opfPath!)) {
            opfPath = archive.entries.keys.sorted().first { $0.lowercased().hasSuffix(".opf") }
        }
        guard let opfPath, let opfData = try? archive.contents(of: opfPath), let opf = MarkupParser.parse(opfData) else {
            throw ParseError.noPackage
        }
        let base = directory(of: opfPath)

        var manifest: [String: ManifestItem] = [:]
        for item in (opf.first("manifest") ?? opf).all("item") {
            guard let id = item["id"], let href = item["href"] else { continue }
            manifest[id] = ManifestItem(
                id: id,
                path: resolve(href, from: base),
                mediaType: (item["media-type"] ?? "").lowercased(),
                properties: Set((item["properties"] ?? "").split(separator: " ").map(String.init))
            )
        }

        let spineElement = opf.first("spine")
        let spine = (spineElement?.all("itemref") ?? []).compactMap { $0["idref"].flatMap { manifest[$0] } }
        let tocItem = spineElement?["toc"].flatMap { manifest[$0] }
            ?? manifest.values.first { $0.mediaType == "application/x-dtbncx+xml" }
        let navItem = manifest.values.first { $0.properties.contains("nav") }
        return Package(archive: archive, opf: opf, manifest: manifest, spine: spine, tocItem: tocItem, navItem: navItem)
    }

    private static func coverItem(in package: Package) -> ManifestItem? {
        let images = package.manifest.values.filter { $0.mediaType.hasPrefix("image/") }
        if let item = images.first(where: { $0.properties.contains("cover-image") }) { return item }
        let metadata = package.opf.first("metadata") ?? package.opf
        if let id = metadata.all("meta").first(where: { $0["name"]?.lowercased() == "cover" })?["content"],
           let item = package.manifest[id], item.mediaType.hasPrefix("image/") {
            return item
        }
        return images.first { $0.id.lowercased().contains("cover") || $0.path.lowercased().contains("cover") }
    }

    // MARK: Table of contents

    private struct TOCEntry {
        let path: String
        let fragment: String?
        let title: String
    }

    private static func tableOfContents(_ package: Package) -> [TOCEntry] {
        // EPUB 3: the navigation document's toc list.
        if let nav = package.navItem,
           let data = try? package.archive.contents(of: nav.path),
           let root = MarkupParser.parse(data) {
            let navs = root.all("nav")
            let toc = navs.first { ($0["type"] ?? "").contains("toc") } ?? navs.first
            let links = (toc ?? root).all("a").compactMap { link -> TOCEntry? in
                guard let href = link["href"] else { return nil }
                return entry(href, title: link.text, base: directory(of: nav.path))
            }
            if !links.isEmpty { return links }
        }
        // EPUB 2: the NCX.
        if let ncx = package.tocItem,
           let data = try? package.archive.contents(of: ncx.path),
           let root = MarkupParser.parse(data) {
            return root.all("navpoint").compactMap { point -> TOCEntry? in
                guard let src = point.first("content")?["src"] else { return nil }
                let label = point.first("navlabel")?.text ?? ""
                return entry(src, title: label, base: directory(of: ncx.path))
            }
        }
        return []
    }

    private static func entry(_ href: String, title: String, base: String) -> TOCEntry? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let parts = href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let file = String(parts.first ?? "")
        let fragment = parts.count > 1 && !parts[1].isEmpty ? String(parts[1]) : nil
        return TOCEntry(path: resolve(file, from: base), fragment: fragment, title: title)
    }

    // MARK: Helpers

    private static func directory(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<slash])
    }

    /// `href` relative to `base`, with "." and ".." resolved and percent-encoding removed.
    static func resolve(_ href: String, from base: String) -> String {
        let clean = href.split(separator: "#").first.map(String.init) ?? href
        let decoded = clean.removingPercentEncoding ?? clean
        var parts = decoded.hasPrefix("/") ? [] : base.split(separator: "/").map(String.init)
        for part in decoded.split(separator: "/") {
            switch part {
            case ".": continue
            case "..": _ = parts.popLast()
            default: parts.append(String(part))
            }
        }
        return parts.joined(separator: "/")
    }
}

/// Image helpers that are safe off the main thread.
nonisolated enum ImageTools {
    /// A JPEG no larger than `maxPixels` on its long side.
    static func thumbnail(_ data: Data, maxPixels: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return jpeg(image)
    }

    static func jpeg(_ image: CGImage, quality: Double = 0.82) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
