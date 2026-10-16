import SwiftData
import SwiftUI

/// An imported book opened from the shelf: its cover and details, Start (or Continue)
/// Reading, and the contents. Chapters open in the Hearken reader.
struct ImportedBookView: View {
    let bookID: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var matches: [ImportedBook]
    @Query private var progressRecords: [ReadingProgress]
    @Query private var shelfRecords: [LibraryShelfRecord]
    @State private var library = ImportedLibrary.shared
    @State private var editingDetails = false
    @State private var confirmingRemove = false
    @State private var originalPages: OriginalPages?

    init(bookID: String) {
        self.bookID = bookID
        _matches = Query(filter: #Predicate<ImportedBook> { $0.id == bookID })
        let prefix = ImportedLibrary.workID(forBook: bookID) + "."
        _progressRecords = Query(filter: #Predicate<ReadingProgress> { $0.chapterID.starts(with: prefix) })
    }

    var body: some View {
        Group {
            if let book = matches.first {
                if book.status == .ready, let content = library.content(bookID) {
                    contents(book, content)
                } else if book.status == .preparing {
                    preparing(book)
                } else {
                    ContentUnavailableView {
                        Label("Couldn't Read This Book", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text("Hearken couldn't find readable text in this file.")
                    } actions: {
                        Button("Try Again") { BookImporter.shared.retry(book) }
                    }
                }
            } else {
                ContentUnavailableView("Book Removed", systemImage: "books.vertical")
            }
        }
        .background(Color(.systemGroupedBackground))
        .refreshable { await CloudRefresh.refresh() }
        .navigationTitle(matches.first?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let book = matches.first {
                ToolbarItem(placement: .topBarTrailing) {
                    CheckMenu(menuItems(book)) {
                        Label("Book Options", systemImage: "ellipsis")
                    }
                    .tint(Color.primary)
                }
            }
        }
        .sheet(isPresented: $editingDetails) {
            if let book = matches.first { BookDetailsSheet(book: book) }
        }
        .fullScreenCover(item: $originalPages) { pages in
            PDFPagesView(url: pages.url, title: pages.title, startPage: pages.startPage)
        }
        .alert("Remove “\(matches.first?.title ?? "")”?", isPresented: $confirmingRemove) {
            Button("Remove", role: .destructive) {
                if let book = matches.first {
                    dismiss()
                    LibraryStore.remove(.book(book), in: modelContext)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(LibraryStore.studySummary(forBooks: [bookID], in: modelContext).map { "This also deletes your \($0) in it, on all your devices." }
                 ?? "It's removed from the Library on all your devices.")
        }
    }

    // MARK: Preparing

    /// The stage and how far along, while the chapters are prepared.
    private func preparing(_ book: ImportedBook) -> some View {
        let progress = library.progress[book.id]
        let stage = library.stage[book.id] ?? .reading
        return VStack(spacing: 18) {
            ImportedBookCover(book: book, size: CGSize(width: 150, height: 225))
            VStack(spacing: 6) {
                Text(progress == nil ? "Waiting for iCloud" : stage.title(for: book.format))
                    .font(.headline)
                Text(progress == nil
                     ? "This book is being prepared on the device it was added on."
                     : "\(book.title) will be ready in a moment.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let progress {
                ProgressView(value: progress)
                    .frame(maxWidth: 240)
                    .accessibilityValue("\(Int(progress * 100)) percent")
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.snappy, value: stage)
    }

    // MARK: Contents

    private func contents(_ book: ImportedBook, _ content: ImportedContent) -> some View {
        let read = Set(progressRecords.filter { $0.completedAt != nil }.map(\.chapterID))
        let resume = resumeChapter(content)

        return List {
            Section {
                VStack(spacing: 14) {
                    ImportedBookCover(book: book, size: CGSize(width: 150, height: 225), showsStatus: false)
                        .padding(.top, 8)
                    VStack(spacing: 4) {
                        Text(book.title)
                            .font(.scripture(size: 24, weight: .bold))
                            .multilineTextAlignment(.center)
                        if !book.author.isEmpty {
                            Text(book.author)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Text(details(book))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    NavigationLink {
                        ReaderView(chapterID: resume.id)
                    } label: {
                        Text(resume.started ? "Continue Reading" : "Start Reading")
                            .font(.headline)
                            .frame(maxWidth: 280)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)

                    if let pages = originalPages(book, startPage: 1) {
                        Button("Original Pages", systemImage: "doc.richtext") { originalPages = pages }
                            .buttonStyle(.glass)
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section("Contents") {
                ForEach(Array(content.chapters.enumerated()), id: \.offset) { index, chapter in
                    let id = ImportedLibrary.chapterID(book: bookID, number: index + 1)
                    NavigationLink {
                        ReaderView(chapterID: id)
                    } label: {
                        HStack(spacing: 12) {
                            Text("\(chapter.number ?? index + 1)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .frame(minWidth: 26, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(chapter.title)
                                    .fontWeight(id == resume.id && resume.started ? .semibold : .regular)
                                    .lineLimit(2)
                                if let page = chapter.startPage, book.format == .pdf {
                                    Text("Page \(page)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 8)
                            if read.contains(id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                                    .accessibilityLabel("Read")
                            } else if id == resume.id && resume.started {
                                Circle().fill(.tint).frame(width: 8, height: 8)
                                    .accessibilityLabel("Reading now")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func details(_ book: ImportedBook) -> String {
        var parts = [book.formatSummary]
        if let shelf = shelfRecords.first(where: { $0.id == book.shelfID && !$0.isRemoved }) {
            parts.append(shelf.name)
        }
        return parts.joined(separator: " · ")
    }

    /// The chapter last read and not finished; else the first unread; else the first.
    private func resumeChapter(_ content: ImportedContent) -> (id: String, started: Bool) {
        if let current = progressRecords.filter({ $0.completedAt == nil }).max(by: { $0.updatedAt < $1.updatedAt }) {
            return (current.chapterID, true)
        }
        let read = Set(progressRecords.filter { $0.completedAt != nil }.map(\.chapterID))
        for number in 1...max(content.chapters.count, 1) {
            let id = ImportedLibrary.chapterID(book: bookID, number: number)
            if !read.contains(id) { return (id, !read.isEmpty) }
        }
        return (ImportedLibrary.chapterID(book: bookID, number: 1), false)
    }

    private func originalPages(_ book: ImportedBook, startPage: Int) -> OriginalPages? {
        guard book.format == .pdf, let url = library.originalFile(forBook: book.id) else { return nil }
        return OriginalPages(url: url, title: book.title, startPage: startPage)
    }

    // MARK: Menu

    private func menuItems(_ book: ImportedBook) -> [CheckMenuItem] {
        var items: [CheckMenuItem] = [
            CheckMenuItem.button("Edit Details", systemImage: "pencil") { editingDetails = true },
        ]
        if let pages = originalPages(book, startPage: 1) {
            items.append(CheckMenuItem.button("Original Pages", systemImage: "doc.richtext") { originalPages = pages })
        }
        let shelves = shelfRecords.filter { !$0.isRemoved && !$0.isLocked }.sorted { $0.order < $1.order }
        if shelves.count > 1 {
            items.append(CheckMenuItem.divider)
            items.append(CheckMenuItem.header("Shelf"))
            for shelf in shelves {
                items.append(CheckMenuItem.choice(shelf.name, systemImage: "books.vertical", isSelected: shelf.id == book.shelfID) {
                    LibraryStore.move(.book(book), to: shelf.id, in: modelContext)
                })
            }
        }
        items.append(CheckMenuItem.divider)
        items.append(CheckMenuItem.button("Remove from Library", systemImage: "trash", role: .destructive) { confirmingRemove = true })
        return items
    }
}
