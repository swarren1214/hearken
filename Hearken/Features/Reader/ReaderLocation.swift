import SwiftData
import SwiftUI

/// The reader's title: a Liquid Glass capsule showing the book and chapter.
/// Tapping it opens ReaderLocationPanel.
struct ReaderLocationPill: View {
    let title: String
    let expanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityLabel(title)
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
        .accessibilityHint("Shows where you are and lets you jump to another chapter.")
    }
}

/// Breadcrumbs for the current chapter, plus whatever level is selected:
/// the library's books, a volume's books, or a book's chapters. Picking a chapter jumps there.
struct ReaderLocationPanel: View {
    let chapterID: String
    let onSelect: (String) -> Void

    private enum Level: Hashable {
        case library
        case work(String)
        case volume(String)
        case book(String)
    }

    @Query private var progressRecords: [ReadingProgress]
    @Query private var highlights: [Highlight]
    @State private var level: Level
    @State private var contentHeight: CGFloat = 0

    private let location: LibraryLocation?

    init(chapterID: String, onSelect: @escaping (String) -> Void) {
        self.chapterID = chapterID
        self.onSelect = onSelect
        let location = LibraryCatalog.location(ofChapter: chapterID)
        self.location = location
        _level = State(initialValue: location.map { .book($0.book.id) } ?? .library)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BreadcrumbBar(crumbs: crumbs)
            Divider()
            ScrollView {
                levelContent
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .frame(height: min(max(contentHeight, 44), 360))
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .animation(.snappy, value: level)
    }

    // MARK: Breadcrumbs

    private var crumbs: [BreadcrumbBar.Crumb] {
        var list: [BreadcrumbBar.Crumb] = [.init(id: "library", title: "Library") { level = .library }]
        switch level {
        case .library:
            break
        case .work(let id):
            if let work = LibraryCatalog.work(id) { list.append(.init(id: work.id, title: work.title, action: nil)) }
        case .volume(let id):
            if case let (work, volume)? = findVolume(id) {
                list.append(.init(id: work.id, title: work.title) { level = .work(work.id) })
                list.append(.init(id: volume.id, title: volume.title, action: nil))
            }
        case .book(let id):
            if case let (work, volume, book)? = findBook(id) {
                list.append(.init(id: work.id, title: work.title) { level = .work(work.id) })
                if work.hasVolumeLevel {
                    list.append(.init(id: volume.id, title: volume.title) { level = .volume(volume.id) })
                }
                list.append(.init(id: book.id, title: book.title, action: nil))
            }
        }
        return list
    }

    // MARK: Levels

    @ViewBuilder
    private var levelContent: some View {
        switch level {
        case .library:
            rows(LibraryCatalog.shelves.flatMap(\.works).filter(\.isAvailable)) { work in
                row(title: work.title, detail: work.summary, isCurrent: work.id == location?.work.id) {
                    level = .work(work.id)
                }
            }
        case .work(let id):
            if let work = LibraryCatalog.work(id) {
                if work.hasVolumeLevel {
                    rows(work.volumes) { volume in
                        row(title: volume.title, detail: volume.summary, isCurrent: volume.id == location?.volume.id) {
                            level = .volume(volume.id)
                        }
                    }
                } else {
                    bookRows(work.books)
                }
            }
        case .volume(let id):
            if case let (_, volume)? = findVolume(id) {
                bookRows(volume.books)
            }
        case .book(let id):
            if case let (_, _, book)? = findBook(id) {
                chapterGrid(book)
            }
        }
    }

    private func bookRows(_ books: [LibraryBook]) -> some View {
        rows(books) { book in
            row(title: book.title, detail: book.unit.count(book.chapterCount), isCurrent: book.id == location?.book.id) {
                level = .book(book.id)
            }
        }
    }

    private func rows<Item: Identifiable, Row: View>(_ items: [Item], @ViewBuilder row: @escaping (Item) -> Row) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider() }
                row(item)
            }
        }
    }

    private func row(title: String, detail: String, isCurrent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .fontWeight(isCurrent ? .semibold : .regular)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 8)
                if isCurrent {
                    Circle().fill(.tint).frame(width: 8, height: 8)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(minHeight: 50)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isCurrent ? "You're reading here" : "")
    }

    private func chapterGrid(_ book: LibraryBook) -> some View {
        let progress = LibraryProgress(progress: progressRecords, highlights: highlights)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
            ForEach(1...book.chapterCount, id: \.self) { number in
                let id = book.chapterID(number)
                Button {
                    onSelect(id)
                } label: {
                    ChapterTile(
                        number: number,
                        unit: book.unit,
                        isRead: progress.read.contains(id),
                        isCurrent: id == chapterID,
                        isMarked: progress.marked.contains(id)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Lookups

    private func findVolume(_ id: String) -> (LibraryWork, LibraryVolume)? {
        for work in LibraryCatalog.shelves.flatMap(\.works) {
            if let volume = work.volumes.first(where: { $0.id == id }) { return (work, volume) }
        }
        return nil
    }

    private func findBook(_ id: String) -> (LibraryWork, LibraryVolume, LibraryBook)? {
        for work in LibraryCatalog.shelves.flatMap(\.works) {
            for volume in work.volumes {
                if let book = volume.books.first(where: { $0.id == id }) { return (work, volume, book) }
            }
        }
        return nil
    }
}
