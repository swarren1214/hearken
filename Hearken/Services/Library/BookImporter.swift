import CryptoKit
import Foundation
import Observation
import OSLog
import SwiftData
import UniformTypeIdentifiers

/// One file on its way into the Library, shown on the Add to Library sheet.
nonisolated struct ImportDraft: Identifiable {
    /// The new book's ID (its file is already copied to the book's folder).
    let id: String
    let format: ImportedBook.Format
    let fileName: String
    let fileSize: Int
    let fileHash: String
    var title: String
    var author: String
    let coverData: Data?
    let chapterCount: Int
    let pageCount: Int
    /// The title of a book already in the Library with the same file.
    let duplicateOf: String?

    @MainActor var summary: String {
        var parts = [format.title]
        if format == .pdf, pageCount > 0 {
            parts.append("\(pageCount.formatted()) \(pageCount == 1 ? "page" : "pages")")
        } else if chapterCount > 0 {
            parts.append(LibraryBook.Unit.chapter.count(chapterCount))
        }
        parts.append(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))
        return parts.joined(separator: " · ")
    }
}

/// A set of files picked together; one Add to Library sheet.
struct ImportBatch: Identifiable {
    let id = UUID()
    var drafts: [ImportDraft]
    /// Files that couldn't be read, with why.
    var failures: [(name: String, reason: String)]
    /// A shelf to put the books on, when the import started from an empty shelf.
    var preferredShelfID: String?
}

/// Brings EPUB and PDF files into the Library: from the Files picker, the Share sheet
/// ("Open in Hearken"), and drag and drop. Each file is copied in, read for its details
/// (Add to Library sheet), then prepared in the background into chapters of paragraphs.
@MainActor
@Observable
final class BookImporter {
    static let shared = BookImporter()

    static let contentTypes: [UTType] = [.epub, .pdf]

    /// The open Add to Library sheet.
    var batch: ImportBatch?
    /// Files are being copied and read.
    var isReading = false
    /// A whole import failed (nothing could be read).
    var failureMessage: String?
    /// Set when books are added, so the app can show the Library.
    var addedToken = 0

    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var preparing: [String: Task<Void, Never>] = [:]
    private let log = Logger(subsystem: "com.stephenwarren.hearken", category: "import")

    func attach(container: ModelContainer) {
        self.container = container
    }

    // MARK: Reading files

    /// Copies the files in and reads their details, then opens the Add to Library sheet.
    func inspect(_ urls: [URL], shelfID: String? = nil) {
        guard !urls.isEmpty else { return }
        isReading = true
        let known = knownHashes()
        Task {
            var drafts: [ImportDraft] = []
            var failures: [(name: String, reason: String)] = []
            for url in urls {
                let name = url.lastPathComponent
                do {
                    let draft = try await Self.read(url, known: known)
                    drafts.append(draft)
                } catch {
                    failures.append((name, error.localizedDescription))
                }
            }
            isReading = false
            if drafts.isEmpty {
                failureMessage = failures.first.map { "“\($0.name)” couldn't be imported. \($0.reason)" }
                    ?? "The file couldn't be imported."
            } else {
                batch = ImportBatch(drafts: drafts, failures: failures, preferredShelfID: shelfID)
            }
        }
    }

    /// Files dropped on the Library (iPad).
    func inspect(providers: [NSItemProvider], shelfID: String? = nil) -> Bool {
        let accepted = providers.filter { provider in Self.contentTypes.contains { provider.hasItemConformingToTypeIdentifier($0.identifier) } }
        guard !accepted.isEmpty else { return false }
        isReading = true
        Task {
            var urls: [URL] = []
            for provider in accepted {
                if let url = await Self.copyDropped(provider) { urls.append(url) }
            }
            if urls.isEmpty {
                isReading = false
                failureMessage = "The dropped file couldn't be read."
            } else {
                inspect(urls, shelfID: shelfID)
            }
        }
        return true
    }

    /// A dropped file is only lent for the length of the callback; copy it somewhere it'll stay.
    private static func copyDropped(_ provider: NSItemProvider) async -> URL? {
        guard let type = contentTypes.first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) }) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                let folder = FileManager.default.temporaryDirectory.appending(path: "Dropped-\(UUID().uuidString)", directoryHint: .isDirectory)
                let copy = folder.appending(path: url.lastPathComponent)
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: url, to: copy)
                    continuation.resume(returning: copy)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private enum ReadError: LocalizedError {
        case unsupported

        var errorDescription: String? { "Only EPUB and PDF files can be imported." }
    }

    /// Copies one file into a new book folder and reads its details, off the main thread.
    private static func read(_ url: URL, known: [String: String]) async throws -> ImportDraft {
        let format: ImportedBook.Format
        switch url.pathExtension.lowercased() {
        case "epub": format = .epub
        case "pdf": format = .pdf
        default:
            let type = UTType(filenameExtension: url.pathExtension)
            if type?.conforms(to: .epub) == true {
                format = .epub
            } else if type?.conforms(to: .pdf) == true {
                format = .pdf
            } else {
                throw ReadError.unsupported
            }
        }
        let bookID = UUID().uuidString
        let destination = ImportedLibrary.originalFile(forBook: bookID, format: format)

        return try await Task.detached(priority: .userInitiated) {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            let manager = FileManager.default
            try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            do {
                try manager.copyItem(at: url, to: destination)
            } catch {
                // Some providers only allow reading through a coordinator.
                try? manager.removeItem(at: destination)
                var coordinatorError: NSError?
                var copyError: (any Error)?
                NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinatorError) { readable in
                    do { try manager.copyItem(at: readable, to: destination) } catch { copyError = error }
                }
                if let failure = coordinatorError ?? copyError { throw failure }
            }
            // Files handed over by the Share sheet arrive in Documents/Inbox; ours is copied, so tidy up.
            if url.path(percentEncoded: false).contains("/Documents/Inbox/") || url.path(percentEncoded: false).contains("/tmp/Dropped-") {
                try? manager.removeItem(at: url)
            }

            do {
                let data = try Data(contentsOf: destination, options: .mappedIfSafe)
                let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                let details = format == .epub
                    ? try EPUBParser.details(of: destination)
                    : try PDFTextExtractor.details(of: destination)
                return ImportDraft(
                    id: bookID, format: format, fileName: url.lastPathComponent, fileSize: data.count, fileHash: hash,
                    title: details.title, author: details.author, coverData: details.coverData,
                    chapterCount: details.chapterCount, pageCount: details.pageCount,
                    duplicateOf: known[hash]
                )
            } catch {
                try? manager.removeItem(at: destination.deletingLastPathComponent())
                throw error
            }
        }.value
    }

    /// Hashes of the books already in the Library, with their titles.
    private func knownHashes() -> [String: String] {
        guard let context = container?.mainContext else { return [:] }
        let books = (try? context.fetch(FetchDescriptor<ImportedBook>())) ?? []
        return Dictionary(books.filter { !$0.fileHash.isEmpty }.map { ($0.fileHash, $0.title) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: Adding

    /// Adds the batch's books to a shelf and starts preparing them.
    func add(_ batch: ImportBatch, toShelf shelfID: String, in context: ModelContext) {
        var order = LibraryStore.nextOrder(on: shelfID, in: context)
        for draft in batch.drafts {
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let book = ImportedBook(
                id: draft.id,
                title: title.isEmpty ? (draft.fileName as NSString).deletingPathExtension : title,
                author: draft.author.trimmingCharacters(in: .whitespacesAndNewlines),
                format: draft.format,
                shelfID: shelfID,
                order: order
            )
            book.fileHash = draft.fileHash
            book.fileName = draft.fileName
            book.fileSize = draft.fileSize
            book.chapterCount = draft.chapterCount
            book.pageCount = draft.pageCount
            book.coverData = draft.coverData
            book.coverHex = Self.coverColor(for: book.title)
            context.insert(book)
            order += 1
        }
        try? context.save()
        LibraryStore.rememberImportShelf(shelfID)
        for draft in batch.drafts {
            prepare(draft.id, format: draft.format)
        }
        self.batch = nil
        addedToken += 1
    }

    /// Discards the batch's copied files.
    func cancel(_ batch: ImportBatch) {
        for draft in batch.drafts {
            try? FileManager.default.removeItem(at: ImportedLibrary.folder(forBook: draft.id))
        }
        self.batch = nil
    }

    // MARK: Preparing

    /// Reads the book's chapters in the background and saves them to its record.
    func prepare(_ bookID: String, format: ImportedBook.Format) {
        guard preparing[bookID] == nil else { return }
        let url = ImportedLibrary.originalFile(forBook: bookID, format: format)
        ImportedLibrary.shared.progress[bookID] = 0

        preparing[bookID] = Task {
            let result: Result<Data, any Error> = await Task.detached(priority: .utility) {
                do {
                    let report: @Sendable (Double) -> Void = { value in
                        Task { @MainActor in
                            if ImportedLibrary.shared.progress[bookID] != nil {
                                ImportedLibrary.shared.progress[bookID] = value
                            }
                        }
                    }
                    let content = format == .epub
                        ? try EPUBParser.content(of: url, progress: report)
                        : try PDFTextExtractor.content(of: url, progress: report)
                    return .success(try JSONEncoder().encode(content))
                } catch {
                    return .failure(error)
                }
            }.value

            preparing[bookID] = nil
            ImportedLibrary.shared.progress[bookID] = nil
            guard !Task.isCancelled, let book = ImportedLibrary.shared.model(bookID) else { return }
            switch result {
            case .success(let data):
                book.contentData = data
                if let content = try? JSONDecoder().decode(ImportedContent.self, from: data) {
                    book.chapterCount = content.chapters.count
                }
                book.status = .ready
            case .failure(let error):
                log.error("Couldn't prepare \(bookID, privacy: .public): \(error.localizedDescription, privacy: .public)")
                book.status = .failed
            }
            book.updatedAt = .now
            try? book.modelContext?.save()
            ImportedLibrary.shared.refresh()
        }
    }

    func cancelPreparing(_ bookID: String) {
        preparing[bookID]?.cancel()
        preparing[bookID] = nil
        ImportedLibrary.shared.progress[bookID] = nil
    }

    func isPreparing(_ bookID: String) -> Bool { preparing[bookID] != nil }

    /// At launch: carry on with books that were still being prepared when the app last quit.
    /// (A book imported on another device stays "preparing" here until its text syncs.)
    func resumeUnfinished() {
        guard let context = container?.mainContext else { return }
        let books = (try? context.fetch(FetchDescriptor<ImportedBook>())) ?? []
        for book in books where book.status == .preparing && preparing[book.id] == nil {
            let url = ImportedLibrary.originalFile(forBook: book.id, format: book.format)
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                prepare(book.id, format: book.format)
            }
        }
    }

    /// Tries a book that failed again, when this device has its file.
    func retry(_ book: ImportedBook) {
        let url = ImportedLibrary.originalFile(forBook: book.id, format: book.format)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        book.status = .preparing
        try? book.modelContext?.save()
        prepare(book.id, format: book.format)
    }

    // MARK: Covers

    /// Cloth colors for generated covers, in the library's palette.
    nonisolated static let coverPalette: [Int] = [
        0x5B2E4A, 0x2F5A4C, 0x3B2A22, 0x1F3466, 0x5A3A2A, 0x2E3F5C, 0x4D3B2E, 0x2F4A4A,
        0x3D3557, 0x6B3A2E, 0x334E3A, 0x4A2F3F, 0x284A5E, 0x5C4A26, 0x3F2E52, 0x5E2B2B,
    ]

    /// A color picked from the title, the same on every device.
    nonisolated static func coverColor(for title: String) -> Int {
        let sum = title.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7FFF_FFFF }
        return coverPalette[sum % coverPalette.count]
    }
}
