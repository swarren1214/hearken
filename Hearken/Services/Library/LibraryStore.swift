import Foundation
import SwiftData

/// One shelf as the Library draws it.
struct ShelfDisplay: Identifiable {
    let id: String
    let name: String
    let isLocked: Bool
    /// A shelf for books whose shelf is gone (deleted on another device mid-sync); it can't be edited.
    var isVirtual = false
    var items: [ShelfItem]

    var caption: String {
        let count = items.count
        return count == 0 ? "Empty" : "\(count) \(count == 1 ? "book" : "books")"
    }
}

/// A cover on a shelf: one of Hearken's works, or a book the user imported.
enum ShelfItem: Identifiable {
    case work(LibraryWork)
    case book(ImportedBook)

    var id: String {
        switch self {
        case .work(let work): work.id
        case .book(let book): book.workID
        }
    }
}

/// The Library's shelves: seeding, merging copies from other devices, and every change the
/// shelf editor and the covers' menus make.
@MainActor
enum LibraryStore {
    static let standardShelfID = "standard"
    static let orphanShelfID = "library.other"
    private static let lastShelfKey = "library.lastImportShelf"

    /// The shelves every Library starts with.
    private static let seededShelves: [(id: String, name: String, order: Double, locked: Bool)] = [
        (standardShelfID, "Standard Works", 0, true),
        ("helps", "Study Helps", 1, false),
        ("history", "Church History", 2, false),
    ]

    /// The Standard Works never leave their shelf.
    static let standardWorks: [LibraryWork] = LibraryCatalog.shelves.first { $0.id == standardShelfID }?.works ?? []

    /// Hearken's other works and the shelf each starts on.
    private static let defaultPlacements: [(workID: String, shelfID: String, order: Double)] = LibraryCatalog.shelves
        .filter { $0.id != standardShelfID }
        .flatMap { shelf in shelf.works.enumerated().map { (workID: $0.element.id, shelfID: shelf.id, order: Double($0.offset)) } }

    // MARK: Seeding and merging

    /// Adds the starting shelves and placements that don't exist yet, then merges duplicates.
    static func prepare(_ context: ModelContext) {
        let shelves = (try? context.fetch(FetchDescriptor<LibraryShelfRecord>())) ?? []
        let existingShelves = Set(shelves.map(\.id))
        for seed in seededShelves where !existingShelves.contains(seed.id) {
            context.insert(LibraryShelfRecord(id: seed.id, name: seed.name, order: seed.order, isLocked: seed.locked, updatedAt: .distantPast))
        }
        let placements = (try? context.fetch(FetchDescriptor<ShelfPlacement>())) ?? []
        let placed = Set(placements.map(\.workID))
        for seed in defaultPlacements where !placed.contains(seed.workID) {
            context.insert(ShelfPlacement(workID: seed.workID, shelfID: seed.shelfID, order: seed.order, updatedAt: .distantPast))
        }
        tidy(context)
    }

    /// Two devices can each create the same seeded shelf or placement; keep one of each.
    /// A removed shelf stays removed; otherwise the most recently changed copy wins.
    static func tidy(_ context: ModelContext) {
        var changed = false
        let shelves = (try? context.fetch(FetchDescriptor<LibraryShelfRecord>())) ?? []
        for (_, copies) in Dictionary(grouping: shelves, by: \.id) where copies.count > 1 {
            let keep = copies.first(where: \.isRemoved) ?? copies.max { $0.updatedAt < $1.updatedAt }
            for copy in copies where copy !== keep {
                context.delete(copy)
                changed = true
            }
        }
        let placements = (try? context.fetch(FetchDescriptor<ShelfPlacement>())) ?? []
        for (_, copies) in Dictionary(grouping: placements, by: \.workID) where copies.count > 1 {
            let keep = copies.max { $0.updatedAt < $1.updatedAt }
            for copy in copies where copy !== keep {
                context.delete(copy)
                changed = true
            }
        }
        if changed || context.hasChanges { try? context.save() }
    }

    // MARK: Layout

    /// The shelves in order, each with its covers.
    static func layout(shelves: [LibraryShelfRecord], placements: [ShelfPlacement], books: [ImportedBook]) -> [ShelfDisplay] {
        var seen = Set<String>()
        let visible = shelves
            .filter { !$0.isRemoved }
            .sorted { $0.order == $1.order ? $0.createdAt < $1.createdAt : $0.order < $1.order }
            .filter { seen.insert($0.id).inserted }
        let ids = Set(visible.map(\.id))

        // Each work's latest placement.
        var placementByWork: [String: ShelfPlacement] = [:]
        for placement in placements {
            if let existing = placementByWork[placement.workID], existing.updatedAt >= placement.updatedAt { continue }
            placementByWork[placement.workID] = placement
        }

        func sortKey(_ item: ShelfItem) -> (Double, Date) {
            switch item {
            case .work(let work): (placementByWork[work.id]?.order ?? 0, .distantPast)
            case .book(let book): (book.order, book.addedAt)
            }
        }

        func items(on shelfID: String) -> [ShelfItem] {
            var items: [ShelfItem] = []
            for work in LibraryCatalog.shelves.flatMap(\.works) where placementByWork[work.id]?.shelfID == shelfID {
                items.append(.work(work))
            }
            for book in books where book.shelfID == shelfID {
                items.append(.book(book))
            }
            return items.sorted { sortKey($0) < sortKey($1) }
        }

        var result: [ShelfDisplay] = visible.map { shelf in
            var shelfItems = items(on: shelf.id)
            if shelf.id == standardShelfID {
                shelfItems = standardWorks.map(ShelfItem.work) + shelfItems
            }
            return ShelfDisplay(id: shelf.id, name: shelf.name, isLocked: shelf.isLocked, items: shelfItems)
        }

        // Books whose shelf is gone.
        let orphanBooks = books.filter { !ids.contains($0.shelfID) }.map(ShelfItem.book)
        let orphanWorks = LibraryCatalog.shelves.flatMap(\.works).filter { work in
            guard let shelfID = placementByWork[work.id]?.shelfID else { return false }
            return !shelfID.isEmpty && !ids.contains(shelfID)
        }.map(ShelfItem.work)
        if !orphanBooks.isEmpty || !orphanWorks.isEmpty {
            result.append(ShelfDisplay(id: orphanShelfID, name: "Other Books", isLocked: true, isVirtual: true, items: orphanWorks + orphanBooks))
        }
        // Before the first sync or seed, never show an empty Library.
        if result.isEmpty {
            result = [ShelfDisplay(id: standardShelfID, name: "Standard Works", isLocked: true, items: standardWorks.map(ShelfItem.work))]
        }
        return result
    }

    // MARK: Shelves

    @discardableResult
    static func addShelf(named name: String, in context: ModelContext) -> LibraryShelfRecord {
        let shelves = (try? context.fetch(FetchDescriptor<LibraryShelfRecord>())) ?? []
        let order = (shelves.filter { !$0.isRemoved }.map(\.order).max() ?? -1) + 1
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let shelf = LibraryShelfRecord(name: trimmed.isEmpty ? "New Shelf" : trimmed, order: order)
        context.insert(shelf)
        try? context.save()
        return shelf
    }

    static func rename(_ shelf: LibraryShelfRecord, to name: String, in context: ModelContext) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !shelf.isLocked, !trimmed.isEmpty, trimmed != shelf.name else { return }
        shelf.name = trimmed
        shelf.updatedAt = .now
        try? context.save()
    }

    /// Saves the shelves' order as given.
    static func reorder(_ shelves: [LibraryShelfRecord], in context: ModelContext) {
        for (index, shelf) in shelves.enumerated() where shelf.order != Double(index) {
            shelf.order = Double(index)
            shelf.updatedAt = .now
        }
        try? context.save()
    }

    enum BooksChoice: Hashable {
        case move(to: String)
        case remove
    }

    /// Deletes a shelf, first moving its covers to another shelf or removing them.
    static func delete(_ shelf: LibraryShelfRecord, books choice: BooksChoice, in context: ModelContext) {
        guard !shelf.isLocked else { return }
        let shelfID = shelf.id
        let books = (try? context.fetch(FetchDescriptor<ImportedBook>(predicate: #Predicate { $0.shelfID == shelfID }))) ?? []
        let placements = (try? context.fetch(FetchDescriptor<ShelfPlacement>(predicate: #Predicate { $0.shelfID == shelfID }))) ?? []

        switch choice {
        case .move(let target):
            var order = nextOrder(on: target, in: context)
            for book in books.sorted(by: { $0.order < $1.order }) {
                book.shelfID = target
                book.order = order
                book.updatedAt = .now
                order += 1
            }
            for placement in placements {
                placement.shelfID = target
                placement.order = order
                placement.updatedAt = .now
                order += 1
            }
        case .remove:
            for book in books { removeBook(book, in: context, save: false) }
            for placement in placements {
                placement.shelfID = ""
                placement.updatedAt = .now
            }
        }

        if seededShelves.contains(where: { $0.id == shelfID }) {
            // Kept, so a new device seeding the defaults doesn't bring it back.
            shelf.isRemoved = true
            shelf.updatedAt = .now
        } else {
            context.delete(shelf)
        }
        try? context.save()
        ImportedLibrary.shared.refresh()
    }

    /// The order value that puts a cover at the end of a shelf.
    static func nextOrder(on shelfID: String, in context: ModelContext) -> Double {
        let books = (try? context.fetch(FetchDescriptor<ImportedBook>(predicate: #Predicate { $0.shelfID == shelfID }))) ?? []
        let placements = (try? context.fetch(FetchDescriptor<ShelfPlacement>(predicate: #Predicate { $0.shelfID == shelfID }))) ?? []
        let highest = (books.map(\.order) + placements.map(\.order)).max() ?? -1
        return highest + 1
    }

    // MARK: Covers

    static func move(_ item: ShelfItem, to shelfID: String, in context: ModelContext) {
        let order = nextOrder(on: shelfID, in: context)
        switch item {
        case .book(let book):
            book.shelfID = shelfID
            book.order = order
            book.updatedAt = .now
        case .work(let work):
            if let placement = placement(for: work.id, in: context) {
                placement.shelfID = shelfID
                placement.order = order
                placement.updatedAt = .now
            }
        }
        try? context.save()
    }

    /// Takes a cover off the Library. An imported book is deleted with everything the user
    /// made in it; one of Hearken's works is only hidden (Edit Shelves can bring it back).
    static func remove(_ item: ShelfItem, in context: ModelContext) {
        switch item {
        case .book(let book):
            removeBook(book, in: context, save: true)
        case .work(let work):
            guard let placement = placement(for: work.id, in: context) else { return }
            placement.shelfID = ""
            placement.updatedAt = .now
            try? context.save()
        }
    }

    static func removeBook(_ book: ImportedBook, in context: ModelContext, save: Bool) {
        let bookID = book.id
        let prefix = ImportedLibrary.workID(forBook: bookID) + "."
        if let items = try? context.fetch(FetchDescriptor<Highlight>(predicate: #Predicate { $0.chapterID.starts(with: prefix) })) {
            for item in items { context.delete(item) }
        }
        if let items = try? context.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.chapterID.starts(with: prefix) })) {
            for item in items { context.delete(item) }
        }
        if let items = try? context.fetch(FetchDescriptor<Bookmark>(predicate: #Predicate { $0.chapterID.starts(with: prefix) })) {
            for item in items { context.delete(item) }
        }
        if let items = try? context.fetch(FetchDescriptor<ReadingProgress>(predicate: #Predicate { $0.chapterID.starts(with: prefix) })) {
            for item in items { context.delete(item) }
        }
        BookImporter.shared.cancelPreparing(bookID)
        context.delete(book)
        ImportedLibrary.shared.forget(bookID)
        if save {
            try? context.save()
            ImportedLibrary.shared.refresh()
        }
    }

    /// "12 highlights and 3 notes", for warning before books are removed.
    static func studySummary(forBooks bookIDs: [String], in context: ModelContext) -> String? {
        var highlights = 0
        var notes = 0
        var bookmarks = 0
        for bookID in bookIDs {
            let prefix = ImportedLibrary.workID(forBook: bookID) + "."
            highlights += (try? context.fetchCount(FetchDescriptor<Highlight>(predicate: #Predicate { $0.chapterID.starts(with: prefix) }))) ?? 0
            notes += (try? context.fetchCount(FetchDescriptor<Note>(predicate: #Predicate { $0.chapterID.starts(with: prefix) }))) ?? 0
            bookmarks += (try? context.fetchCount(FetchDescriptor<Bookmark>(predicate: #Predicate { $0.chapterID.starts(with: prefix) }))) ?? 0
        }
        let parts = [
            highlights > 0 ? "\(highlights) \(highlights == 1 ? "highlight" : "highlights")" : nil,
            notes > 0 ? "\(notes) \(notes == 1 ? "note" : "notes")" : nil,
            bookmarks > 0 ? "\(bookmarks) \(bookmarks == 1 ? "bookmark" : "bookmarks")" : nil,
        ].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return ListFormatter.localizedString(byJoining: parts)
    }

    /// Hearken's works the user removed from the Library.
    static func hiddenWorks(_ placements: [ShelfPlacement]) -> [LibraryWork] {
        let hidden = Set(placements.filter { $0.shelfID.isEmpty }.map(\.workID))
        return LibraryCatalog.shelves.flatMap(\.works).filter { hidden.contains($0.id) }
    }

    /// Puts removed works back on their starting shelf, or the first shelf that can hold them.
    static func restoreHiddenWorks(in context: ModelContext) {
        let shelves = ((try? context.fetch(FetchDescriptor<LibraryShelfRecord>())) ?? []).filter { !$0.isRemoved }
        let ids = Set(shelves.map(\.id))
        var fallback = shelves.filter { !$0.isLocked }.min { $0.order < $1.order }?.id
        let placements = (try? context.fetch(FetchDescriptor<ShelfPlacement>())) ?? []
        for placement in placements where placement.shelfID.isEmpty {
            let home = defaultPlacements.first { $0.workID == placement.workID }?.shelfID
            if let home, ids.contains(home) {
                placement.shelfID = home
            } else {
                if fallback == nil { fallback = addShelf(named: "Study Helps", in: context).id }
                placement.shelfID = fallback ?? ""
            }
            placement.order = nextOrder(on: placement.shelfID, in: context)
            placement.updatedAt = .now
        }
        try? context.save()
    }

    private static func placement(for workID: String, in context: ModelContext) -> ShelfPlacement? {
        let all = (try? context.fetch(FetchDescriptor<ShelfPlacement>(predicate: #Predicate { $0.workID == workID }))) ?? []
        if let latest = all.max(by: { $0.updatedAt < $1.updatedAt }) { return latest }
        let placement = ShelfPlacement(workID: workID, shelfID: "", order: 0)
        context.insert(placement)
        return placement
    }

    // MARK: Import shelf

    /// Where the Add to Library sheet puts books unless told otherwise: the last shelf used,
    /// or the first shelf that can hold them.
    static func defaultImportShelf(_ shelves: [LibraryShelfRecord]) -> String? {
        let usable = shelves.filter { !$0.isRemoved && !$0.isLocked }.sorted { $0.order < $1.order }
        if let last = UserDefaults.standard.string(forKey: lastShelfKey), usable.contains(where: { $0.id == last }) {
            return last
        }
        return usable.first?.id
    }

    static func rememberImportShelf(_ id: String) {
        UserDefaults.standard.set(id, forKey: lastShelfKey)
    }
}
