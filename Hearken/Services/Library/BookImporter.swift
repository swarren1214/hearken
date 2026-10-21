import CryptoKit
import Foundation
import Observation
import OSLog
import SwiftData
import UIKit
import UniformTypeIdentifiers
import UserNotifications

/// One file on its way into the Library, shown on the Add to Library sheet. It appears as
/// soon as the file is picked and fills in once the file has been read.
nonisolated struct ImportDraft: Identifiable {
    enum State: Equatable {
        case reading
        case ready
        case failed(String)
    }

    /// The new book's ID (its file is copied to the book's folder).
    let id: String
    var fileName: String
    var format: ImportedBook.Format
    var state: State = .reading
    var fileSize = 0
    var fileHash = ""
    var title = ""
    var author = ""
    var coverData: Data?
    var chapterCount = 0
    var pageCount = 0
    /// The title of a book already in the Library with the same file.
    var duplicateOf: String?

    init(id: String, fileName: String, format: ImportedBook.Format) {
        self.id = id
        self.fileName = fileName
        self.format = format
    }

    @MainActor var summary: String {
        var parts = [format.title]
        if format == .pdf, pageCount > 0 {
            parts.append("\(pageCount.formatted()) \(pageCount == 1 ? "page" : "pages")")
        } else if chapterCount > 0 {
            parts.append(LibraryBook.Unit.chapter.count(chapterCount))
        }
        if fileSize > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }
}

/// A set of files picked together; one Add to Library sheet.
struct ImportBatch: Identifiable {
    let id = UUID()
    var drafts: [ImportDraft]
    /// A shelf to put the books on, when the import started from an empty shelf.
    var preferredShelfID: String?

    var readingCount: Int { drafts.filter { $0.state == .reading }.count }
    var ready: [ImportDraft] { drafts.filter { $0.state == .ready } }
}

/// Brings EPUB and PDF files into the Library: from the Files picker, the Share sheet
/// ("Open in Hearken"), and drag and drop. Each file is copied in and read for its details
/// on the Add to Library sheet, then prepared in the background into chapters of verses
/// (BookStructurer), with its progress on its cover, a system progress indicator when the
/// app is closed, and a notification when it's ready.
@MainActor
@Observable
final class BookImporter {
    static let shared = BookImporter()

    nonisolated static let contentTypes: [UTType] = [.epub, .pdf]

    /// The open Add to Library sheet.
    var batch: ImportBatch?
    /// Dropped files are being copied in, before the sheet opens.
    var isReading = false
    /// A whole import failed (nothing could be read).
    var failureMessage: String?
    /// Set when books are added, so the app can show the Library.
    var addedToken = 0
    /// Someone tried to import without Hearken Plus or Hearth+ (Files, the Share sheet or a drop);
    /// RootTabView shows the paywall. Books already imported always stay readable.
    var paywallRequested = false

    /// Importing your own books and PDFs is part of Hearken Plus and Hearth+.
    var canImport: Bool { HearthPurchases.shared.isUnlocked }

    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var preparing: [String: Task<Void, Never>] = [:]
    private let log = Logger(subsystem: "com.stephenwarren.hearken", category: "import")

    func attach(container: ModelContainer) {
        self.container = container
    }

    // MARK: Reading files

    /// Opens the Add to Library sheet at once with a row per file, then copies each file in
    /// and reads its details, filling in its row. Files picked while the sheet is open join it.
    func inspect(_ urls: [URL], shelfID: String? = nil) {
        guard !urls.isEmpty else { return }
        guard canImport else {
            paywallRequested = true
            return
        }
        let known = knownHashes()
        let drafts = urls.map { url in
            ImportDraft(id: UUID().uuidString, fileName: url.lastPathComponent, format: Self.guessFormat(url) ?? .epub)
        }
        if batch != nil {
            batch?.drafts += drafts
        } else {
            batch = ImportBatch(drafts: drafts, preferredShelfID: shelfID)
        }
        for (url, draft) in zip(urls, drafts) {
            Task {
                let result: ImportDraft
                do {
                    result = try await Self.read(url, bookID: draft.id, known: known)
                } catch {
                    var failed = draft
                    failed.state = .failed((error as? ReadError)?.errorDescription ?? FriendlyError.importReason(error))
                    result = failed
                }
                finishReading(result)
            }
        }
    }

    /// A file's details are in: fill in its row, or tidy up if the sheet was closed meanwhile.
    private func finishReading(_ draft: ImportDraft) {
        guard let index = batch?.drafts.firstIndex(where: { $0.id == draft.id }) else {
            try? FileManager.default.removeItem(at: ImportedLibrary.folder(forBook: draft.id))
            return
        }
        batch?.drafts[index] = draft
        // Nothing could be read at all: say why instead of showing an empty sheet.
        if let batch, batch.readingCount == 0, batch.ready.isEmpty {
            let failure = batch.drafts.first
            if case .failed(let reason) = failure?.state {
                failureMessage = "“\(failure?.fileName ?? "The file")” couldn't be imported. \(reason)"
            } else {
                failureMessage = "The file couldn't be imported."
            }
            cancel(batch)
        }
    }

    /// Files dropped on the Library (iPad).
    func inspect(providers: [NSItemProvider], shelfID: String? = nil) -> Bool {
        let accepted = providers.filter { provider in Self.contentTypes.contains { provider.hasItemConformingToTypeIdentifier($0.identifier) } }
        guard !accepted.isEmpty else { return false }
        guard canImport else {
            paywallRequested = true
            return false
        }
        isReading = true
        Task {
            var urls: [URL] = []
            for provider in accepted {
                if let url = await Self.copyDropped(provider) { urls.append(url) }
            }
            isReading = false
            if urls.isEmpty {
                failureMessage = "The dropped file couldn't be read."
            } else {
                inspect(urls, shelfID: shelfID)
            }
        }
        return true
    }

    /// A dropped file is only lent for the length of the callback; copy it somewhere it'll stay.
    nonisolated private static func copyDropped(_ provider: NSItemProvider) async -> URL? {
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

    nonisolated private static func guessFormat(_ url: URL) -> ImportedBook.Format? {
        switch url.pathExtension.lowercased() {
        case "epub": return .epub
        case "pdf": return .pdf
        default:
            let type = UTType(filenameExtension: url.pathExtension)
            if type?.conforms(to: .epub) == true { return .epub }
            if type?.conforms(to: .pdf) == true { return .pdf }
            return nil
        }
    }

    /// Copies one file into its book folder and reads its details, off the main thread.
    private static func read(_ url: URL, bookID: String, known: [String: String]) async throws -> ImportDraft {
        guard let format = guessFormat(url) else { throw ReadError.unsupported }
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
                var draft = ImportDraft(id: bookID, fileName: url.lastPathComponent, format: format)
                draft.state = .ready
                draft.fileSize = data.count
                draft.fileHash = hash
                draft.title = details.title
                draft.author = details.author
                draft.coverData = details.coverData
                draft.chapterCount = details.chapterCount
                draft.pageCount = details.pageCount
                draft.duplicateOf = known[hash]
                return draft
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
        let drafts = batch.ready
        for draft in drafts {
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
        // Files that couldn't be read leave nothing behind.
        for draft in batch.drafts where draft.state != .ready {
            try? FileManager.default.removeItem(at: ImportedLibrary.folder(forBook: draft.id))
        }

        // Keep going when the app is closed, with the system's progress indicator.
        let title = drafts.count == 1 ? "Preparing \(drafts[0].title)" : "Preparing \(drafts.count) books"
        PreparationTask.shared.begin(bookIDs: drafts.map(\.id), title: title)
        for draft in drafts {
            prepare(draft.id, format: draft.format)
        }
        self.batch = nil
        addedToken += 1
        Task { await Self.askForNotificationsIfNeeded() }
    }

    /// Discards the batch's copied files.
    func cancel(_ batch: ImportBatch) {
        for draft in batch.drafts {
            try? FileManager.default.removeItem(at: ImportedLibrary.folder(forBook: draft.id))
        }
        self.batch = nil
    }

    // MARK: Preparing

    /// Reads the book into chapters of verses in the background and saves them to its record.
    func prepare(_ bookID: String, format: ImportedBook.Format) {
        guard preparing[bookID] == nil else { return }
        let url = ImportedLibrary.originalFile(forBook: bookID, format: format)
        let library = ImportedLibrary.shared
        library.progress[bookID] = 0
        library.stage[bookID] = .reading

        preparing[bookID] = Task {
            let result: Result<Data, any Error> = await Task.detached(priority: .utility) {
                do {
                    // Reading the file is most of the work; chapters and verses are quick.
                    let reading = Self.reporter(bookID, from: 0, to: 0.8) { _ in .reading }
                    let raws = format == .epub
                        ? try EPUBParser.chapters(of: url, progress: reading)
                        : try PDFTextExtractor.chapters(of: url, progress: reading)
                    let structuring = Self.reporter(bookID, from: 0.8, to: 1) { $0 < 0.3 ? .chapters : .verses }
                    let structured = BookStructurer.structure(raws, progress: structuring)
                    guard !structured.content.chapters.isEmpty else { throw EPUBParser.ParseError.noText }
                    return .success(try JSONEncoder().encode(structured.content))
                } catch {
                    return .failure(error)
                }
            }.value

            preparing[bookID] = nil
            library.progress[bookID] = nil
            library.stage[bookID] = nil
            defer { PreparationTask.shared.finished(bookID) }
            guard !Task.isCancelled, let book = library.model(bookID) else { return }
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
            library.refresh()
            var failure: String?
            if case .failure(let error) = result { failure = FriendlyError.importReason(error) }
            notifyIfAway(book, failure: failure)
            if book.status == .ready { BookRefiner.shared.refine(bookID) }
        }
    }

    /// A progress callback for the background work that maps 0...1 into part of the bar and
    /// sets the stage shown under the cover.
    nonisolated private static func reporter(
        _ bookID: String, from start: Double, to end: Double,
        stage: @escaping @Sendable (Double) -> ImportedLibrary.PrepStage
    ) -> @Sendable (Double) -> Void {
        { value in
            let overall = start + (end - start) * min(max(value, 0), 1)
            let current = stage(value)
            Task { @MainActor in
                let library = ImportedLibrary.shared
                guard library.progress[bookID] != nil else { return }
                // Only forward: callbacks can arrive slightly out of order.
                if overall >= library.progress[bookID] ?? 0 {
                    library.progress[bookID] = overall
                    library.stage[bookID] = current
                }
                PreparationTask.shared.update()
            }
        }
    }

    func cancelPreparing(_ bookID: String) {
        preparing[bookID]?.cancel()
        preparing[bookID] = nil
        ImportedLibrary.shared.progress[bookID] = nil
        ImportedLibrary.shared.stage[bookID] = nil
        PreparationTask.shared.finished(bookID)
    }

    func isPreparing(_ bookID: String) -> Bool { preparing[bookID] != nil }

    /// At launch: carry on with books that were still being prepared when the app last quit,
    /// and give books prepared before verses existed their verses.
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
        upgradeOldBooks(books)
    }

    /// Tries a book that failed again, when this device has its file.
    func retry(_ book: ImportedBook) {
        let url = ImportedLibrary.originalFile(forBook: book.id, format: book.format)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        book.status = .preparing
        try? book.modelContext?.save()
        PreparationTask.shared.begin(bookIDs: [book.id], title: "Preparing \(book.title)")
        prepare(book.id, format: book.format)
    }

    // MARK: Upgrading

    /// Books prepared before verses (content version 1) get verses and chapters, with their
    /// highlights, notes, bookmarks and reading positions moved onto the new verses. Only the
    /// device that imported a book (it has the original file) does this, so two devices never
    /// move the same highlights twice; the others receive the upgraded book through iCloud.
    private func upgradeOldBooks(_ books: [ImportedBook]) {
        for book in books where book.status == .ready && preparing[book.id] == nil {
            guard let data = book.contentData,
                  let old = try? JSONDecoder().decode(ImportedContent.self, from: data), !old.hasVerses,
                  FileManager.default.fileExists(atPath: ImportedLibrary.originalFile(forBook: book.id, format: book.format).path(percentEncoded: false))
            else { continue }
            let bookID = book.id
            let library = ImportedLibrary.shared
            library.progress[bookID] = 0
            library.stage[bookID] = .verses
            preparing[bookID] = Task {
                let structured = await Task.detached(priority: .utility) {
                    let raws = old.chapters.map { RawChapter(title: $0.title, titleSource: .file, paragraphs: $0.paragraphs) }
                    return BookStructurer.structure(raws, progress: Self.reporter(bookID, from: 0, to: 1) { _ in .verses })
                }.value
                preparing[bookID] = nil
                library.progress[bookID] = nil
                library.stage[bookID] = nil
                guard let model = library.model(bookID), let context = model.modelContext,
                      let newData = try? JSONEncoder().encode(structured.content) else { return }
                BookMigration.move(bookID: bookID, from: old, to: structured, in: context)
                model.contentData = newData
                model.chapterCount = structured.content.chapters.count
                model.updatedAt = .now
                do {
                    try context.save()
                } catch {
                    log.error("Couldn't save the upgraded \(bookID, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    context.rollback()
                }
                library.refresh()
                BookRefiner.shared.refine(bookID)
            }
        }
    }

    // MARK: Notifications

    /// When a book finishes while Hearken isn't on screen: "The Book of Enoch is ready".
    private func notifyIfAway(_ book: ImportedBook, failure: String?) {
        guard UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        if book.status == .ready {
            content.title = "\(book.title) is ready"
            let shelf = container.flatMap { container in
                let shelfID = book.shelfID
                return try? container.mainContext.fetch(FetchDescriptor<LibraryShelfRecord>(predicate: #Predicate { $0.id == shelfID })).first?.name
            }
            let count = LibraryBook.Unit.chapter.count(book.chapterCount)
            content.body = shelf.map { "\(count) on \($0). Tap to start reading." } ?? "\(count). Tap to start reading."
        } else {
            content.title = "Couldn't read a book"
            content.body = "\(book.fileName.isEmpty ? book.title : book.fileName): \(failure ?? "Hearken couldn't find readable text.")"
        }
        content.sound = .default
        content.userInfo = ["bookID": book.id]
        let request = UNNotificationRequest(identifier: "book.\(book.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// The first time books are added, ask to send "ready" notifications (plan reminders may
    /// already have asked).
    private static func askForNotificationsIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
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
