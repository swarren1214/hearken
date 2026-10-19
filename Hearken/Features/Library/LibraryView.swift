import SwiftData
import SwiftUI

/// The Library tab: shelves of front covers. The Standard Works come first; the rest of the
/// shelves are the user's to name, order and fill, with Hearken's other works and books they
/// import (EPUB and PDF). Tapping a cover lifts it and zooms it open into the book.
struct LibraryView: View {
    @Namespace private var covers
    @Environment(\.modelContext) private var modelContext
    @Query private var progressRecords: [ReadingProgress]
    @Query private var highlights: [Highlight]
    @Query private var shelfRecords: [LibraryShelfRecord]
    @Query private var placements: [ShelfPlacement]
    @Query private var books: [ImportedBook]

    @State private var importer = BookImporter.shared
    @State private var pickingFiles = false
    @State private var importShelfID: String?
    @State private var editingShelves = false
    @State private var namingShelf = false
    @State private var newShelfName = ""
    @State private var editingBook: ImportedBook?
    @State private var removal: Removal?
    @State private var dropTargeted = false

    /// A cover waiting on "Remove from Library" to be confirmed.
    private struct Removal: Identifiable {
        let item: ShelfItem
        let title: String
        let message: String
        var id: String { item.id }
    }

    var body: some View {
        // Split into parts so the compiler can type-check each one quickly.
        syncing(dialogs(importing(destinations(
            shelvesList
                .refreshable { await CloudRefresh.refresh() }
                .colorHeader("Library")
                .toolbar { libraryToolbar }
        ))))
    }

    private var shelvesList: some View {
        let progress = LibraryProgress(progress: progressRecords, highlights: highlights)
        let shelves = LibraryStore.layout(shelves: shelfRecords, placements: placements, books: books)

        return ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                HeaderTitle("Library")
                    .padding(.horizontal, 16)
                ForEach(shelves) { shelf in
                    shelfRow(shelf, progress: progress)
                        .tourTarget(.library, isEnabled: shelf.id == shelves.first?.id)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        // The color header and gray background come from `body`.
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(.tint, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
    }

    @ToolbarContentBuilder
    private var libraryToolbar: some ToolbarContent {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Import a Book…", menuIcon: "square.and.arrow.down") { importBook(toShelf: nil) }
                    Button("New Shelf…", menuIcon: "plus.rectangle.on.rectangle") {
                        newShelfName = ""
                        namingShelf = true
                    }
                    Button("Edit Shelves", menuIcon: "pencil") { editingShelves = true }
                } label: {
                    Label("Add to Library", systemImage: "plus")
                }
                .tint(.white)
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    NotebookView()
                } label: {
                    Label("Notebook", systemImage: "note.text")
                }
                .tint(.white)
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    ReadingPlansView()
                } label: {
                    Label("Reading Plans", systemImage: "calendar")
                }
                .tint(.white)
            }
    }

    private func destinations(_ content: some View) -> some View {
        content
            .navigationDestination(for: LibraryRoute.self) { route in
                if let work = LibraryCatalog.work(route.workID) {
                    LibraryBookView(work: work)
                        .navigationTransition(.zoom(sourceID: work.id, in: covers))
                }
            }
            .navigationDestination(for: ImportedBookRoute.self) { route in
                ImportedBookView(bookID: route.bookID)
                    .navigationTransition(.zoom(sourceID: ImportedLibrary.workID(forBook: route.bookID), in: covers))
            }
    }

    private func importing(_ content: some View) -> some View {
        content
            .fileImporter(isPresented: $pickingFiles, allowedContentTypes: BookImporter.contentTypes, allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    importer.inspect(urls, shelfID: importShelfID)
                }
            }
            // iPad: drop EPUB and PDF files anywhere on the Library.
            .onDrop(of: BookImporter.contentTypes, isTargeted: $dropTargeted) { providers in
                importer.inspect(providers: providers)
            }
    }

    private func dialogs(_ content: some View) -> some View {
        content
            .sheet(isPresented: $editingShelves) {
                ShelfEditorView()
            }
            .sheet(item: $editingBook) { book in
                BookDetailsSheet(book: book)
            }
            .alert("New Shelf", isPresented: $namingShelf) {
                TextField("Name", text: $newShelfName)
                Button("Cancel", role: .cancel) {}
                Button("Add") {
                    withAnimation(.snappy) { _ = LibraryStore.addShelf(named: newShelfName, in: modelContext) }
                }
            } message: {
                Text("Name the shelf, like “Apocryphal Texts”.")
            }
            // A standard alert to confirm removing a book.
            .alert(
                removal?.title ?? "",
                isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }),
                presenting: removal
            ) { removal in
                Button("Remove", role: .destructive) {
                    withAnimation(.snappy) { LibraryStore.remove(removal.item, in: modelContext) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { removal in
                Text(removal.message)
            }
    }

    /// How many imported books are ready, for the haptic when one finishes.
    private var readyCount: Int {
        books.filter { $0.status == .ready }.count
    }

    private func syncing(_ content: some View) -> some View {
        content
            // A book finishing while you watch.
            .sensoryFeedback(trigger: readyCount) { (old: Int, new: Int) -> SensoryFeedback? in
                new > old ? .success : nil
            }
            .task {
                LibraryStore.prepare(modelContext)
                ImportedLibrary.shared.refresh()
            }
            // Shelves and books arriving from another device.
            .onChange(of: shelfRecords.count) { LibraryStore.tidy(modelContext) }
            .onChange(of: placements.count) { LibraryStore.tidy(modelContext) }
            .onChange(of: books.map(\.updatedAt)) { ImportedLibrary.shared.refresh() }
    }

    // MARK: Shelves

    private func shelfRow(_ shelf: ShelfDisplay, progress: LibraryProgress) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(shelf.name)
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(shelf.caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                // Top-aligned: a preparing book's stage line hangs below its cover.
                HStack(alignment: .top, spacing: 14) {
                    ForEach(shelf.items) { item in
                        switch item {
                        case .work(let work):
                            workCover(work, on: shelf, progress: progress)
                        case .book(let book):
                            VStack(alignment: .leading, spacing: 8) {
                                bookCover(book, on: shelf, progress: progress)
                                BookStatusCaption(book: book)
                            }
                        }
                    }
                    if shelf.items.isEmpty && !shelf.isLocked {
                        importSlot(shelf)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 22) // headroom for the lift
                .padding(.bottom, 6) // a little air between the covers and the shelf
            }
            .scrollClipDisabled()

            ShelfBoard()
                .padding(.horizontal, 14)
        }
    }

    /// An empty shelf's invitation to fill it.
    private func importSlot(_ shelf: ShelfDisplay) -> some View {
        Button {
            importBook(toShelf: shelf.id)
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                Text("Import a book")
                    .font(.footnote.weight(.medium))
            }
            .foregroundStyle(.secondary)
            .frame(width: 120, height: 180)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Choose EPUB or PDF files for \(shelf.name).")
    }

    private func importBook(toShelf shelfID: String?) {
        // Importing needs Hearken Plus or Hearth+: the paywall, not the Files picker.
        guard importer.canImport else {
            importer.paywallRequested = true
            return
        }
        importShelfID = shelfID
        pickingFiles = true
    }

    // MARK: Covers

    @ViewBuilder
    private func workCover(_ work: LibraryWork, on shelf: ShelfDisplay, progress: LibraryProgress) -> some View {
        let movable = !LibraryStore.standardWorks.contains { $0.id == work.id }
        Group {
            if work.isAvailable {
                NavigationLink(value: LibraryRoute(workID: work.id)) {
                    BookCover(work: work, showsRibbon: progress.isReading(work))
                }
                .buttonStyle(CoverLiftStyle())
                .matchedTransitionSource(id: work.id, in: covers)
                .accessibilityLabel(work.title)
                .accessibilityHint(progress.isReading(work) ? "Reading now. Opens the book." : "Opens the book.")
            } else {
                BookCover(work: work)
                    .opacity(0.55)
                    .overlay(alignment: .topTrailing) {
                        Text("Soon")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.45), in: .rect(cornerRadius: 6))
                            .padding(8)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(work.title), coming soon")
            }
        }
        .contextMenu {
            if movable {
                moveMenu(.work(work), currentShelf: shelf.id)
                Button("Remove from Library", menuIcon: "minus.circle", role: .destructive) {
                    removal = Removal(
                        item: .work(work),
                        title: "Remove “\(work.title)”?",
                        message: "You can put it back from Edit Shelves."
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func bookCover(_ book: ImportedBook, on shelf: ShelfDisplay, progress: LibraryProgress) -> some View {
        let reading = progress.current.map { $0.hasPrefix(book.workID + ".") } ?? false
        let label = book.author.isEmpty ? book.title : "\(book.title), \(book.author)"
        Group {
            if book.status == .ready {
                NavigationLink(value: ImportedBookRoute(bookID: book.id)) {
                    ImportedBookCover(book: book, showsRibbon: reading)
                }
                .buttonStyle(CoverLiftStyle())
                .matchedTransitionSource(id: book.workID, in: covers)
                .accessibilityLabel(label)
                .accessibilityHint(reading ? "Reading now. Opens the book." : "Opens the book.")
            } else {
                ImportedBookCover(book: book)
                    .onTapGesture {
                        if book.status == .failed { BookImporter.shared.retry(book) }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(label)
                    .accessibilityValue(book.accessibilityStatus)
            }
        }
        .contextMenu {
            if book.status == .failed {
                Button("Try Again", menuIcon: "arrow.clockwise") { BookImporter.shared.retry(book) }
            }
            Button("Edit Details", menuIcon: "pencil") { editingBook = book }
            moveMenu(.book(book), currentShelf: shelf.id)
            Button("Remove from Library", menuIcon: "trash", role: .destructive) {
                let summary = LibraryStore.studySummary(forBooks: [book.id], in: modelContext)
                removal = Removal(
                    item: .book(book),
                    title: "Remove “\(book.title)”?",
                    message: summary.map { "This also deletes your \($0) in it, on all your devices." }
                        ?? "It's removed from the Library on all your devices."
                )
            }
        } preview: {
            ImportedBookCover(book: book, size: CGSize(width: 200, height: 300), showsStatus: false)
                .padding(20)
        }
    }

    /// Every shelf but this one and the Standard Works.
    @ViewBuilder
    private func moveMenu(_ item: ShelfItem, currentShelf: String) -> some View {
        let targets = shelfRecords
            .filter { !$0.isRemoved && !$0.isLocked && $0.id != currentShelf }
            .sorted { $0.order < $1.order }
        if !targets.isEmpty {
            Menu("Move to Shelf", menuIcon: "books.vertical") {
                ForEach(targets) { shelf in
                    Button(shelf.name) {
                        withAnimation(.snappy) { LibraryStore.move(item, to: shelf.id, in: modelContext) }
                    }
                }
            }
        }
    }
}

/// Navigation value for opening an imported book from the shelf.
struct ImportedBookRoute: Hashable {
    let bookID: String
}

#Preview {
    NavigationStack { LibraryView() }
        .previewEnvironment(signedIn: true)
}
