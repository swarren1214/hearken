import SwiftData
import SwiftUI

/// An opened book: expandable volumes → expandable books → a grid of chapters.
///
/// It arrives through a zoom transition from its shelf cover, then the cover swings
/// open on its spine to reveal the contents.
struct LibraryBookView: View {
    let work: LibraryWork

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var progressRecords: [ReadingProgress]
    @Query private var highlights: [Highlight]

    @State private var expandedVolume: String? = nil
    @State private var expandedBook: String? = nil
    @State private var didRestorePosition = false
    @State private var coverSwung = false
    @State private var coverGone = false

    init(work: LibraryWork) {
        self.work = work
        _expandedVolume = State(initialValue: work.hasVolumeLevel ? nil : work.volumes.first?.id)
    }

    private var progress: LibraryProgress {
        LibraryProgress(progress: progressRecords, highlights: highlights)
    }

    var body: some View {
        let progress = self.progress

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    BreadcrumbBar(crumbs: crumbs)
                    ForEach(work.volumes) { volume in
                        volumeCard(volume, progress: progress, proxy: proxy)
                    }
                    legend
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .onAppear { restorePosition(progress: progress, proxy: proxy) }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(work.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Collapse All", systemImage: "rectangle.compress.vertical") { collapseAll() }
                } label: {
                    Label("Book Options", systemImage: "ellipsis")
                }
                .tint(Color.primary)
            }
        }
        .overlay { openingCover }
        .task { await openCover() }
    }

    // MARK: Opening

    @ViewBuilder
    private var openingCover: some View {
        if !coverGone {
            GeometryReader { geo in
                BookCover(work: work, size: geo.size)
                    .rotation3DEffect(
                        .degrees(coverSwung ? -100 : 0),
                        axis: (x: 0, y: 1, z: 0),
                        anchor: .leading,
                        perspective: 0.6
                    )
                    .opacity(coverSwung ? 0 : 1)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func openCover() async {
        guard !coverGone else { return }
        if reduceMotion {
            coverGone = true
            return
        }
        // Let the zoom finish growing the cover to full screen, then swing it open.
        try? await Task.sleep(for: .milliseconds(380))
        withAnimation(.timingCurve(0.5, 0, 0.3, 1, duration: 0.7)) { coverSwung = true }
        try? await Task.sleep(for: .milliseconds(720))
        coverGone = true
    }

    // MARK: Header and breadcrumbs

    private var header: some View {
        HStack(spacing: 16) {
            BookCover(work: work, size: CGSize(width: 54, height: 81))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(work.title)
                    .font(.system(.largeTitle, design: .serif, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Text(work.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }

    private var crumbs: [BreadcrumbBar.Crumb] {
        var list: [BreadcrumbBar.Crumb] = [
            .init(id: "library", title: "Library") { dismiss() },
            .init(id: work.id, title: work.title) { collapseAll() },
        ]
        if work.hasVolumeLevel, let volume = work.volumes.first(where: { $0.id == expandedVolume }) {
            list.append(.init(id: volume.id, title: volume.title) {
                withAnimation(.snappy) { expandedBook = nil }
            })
        }
        if let book = work.books.first(where: { $0.id == expandedBook }) {
            list.append(.init(id: book.id, title: book.title, action: nil))
        }
        return list
    }

    // MARK: Volumes and books

    @ViewBuilder
    private func volumeCard(_ volume: LibraryVolume, progress: LibraryProgress, proxy: ScrollViewProxy) -> some View {
        let expanded = expandedVolume == volume.id

        VStack(spacing: 0) {
            if work.hasVolumeLevel {
                Button {
                    withAnimation(.snappy) {
                        expandedVolume = expanded ? nil : volume.id
                        expandedBook = nil
                    }
                } label: {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(volume.title)
                                .font(.system(.title3, design: .serif, weight: .semibold))
                            Text(volume.summary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        DisclosureChevron(expanded: expanded)
                    }
                    .padding(16)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityValue(expanded ? "Expanded" : "Collapsed")
                .accessibilityHint(expanded ? "Hides its books." : "Shows its books.")

                if expanded { Divider() }
            }

            if expanded {
                ForEach(Array(volume.books.enumerated()), id: \.element.id) { index, book in
                    bookRow(book, isFirst: index == 0, progress: progress, proxy: proxy)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 22))
    }

    @ViewBuilder
    private func bookRow(_ book: LibraryBook, isFirst: Bool, progress: LibraryProgress, proxy: ScrollViewProxy) -> some View {
        let expanded = expandedBook == book.id
        let reading = progress.isReading(book)

        VStack(spacing: 0) {
            if !isFirst { Divider().padding(.leading, 16) }

            Button {
                withAnimation(.snappy) { expandedBook = expanded ? nil : book.id }
                if !expanded {
                    withAnimation(.snappy.delay(0.05)) { proxy.scrollTo(book.id, anchor: .top) }
                }
            } label: {
                HStack(spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(book.title)
                        Text(book.unit.count(book.chapterCount))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Spacer(minLength: 8)
                    if reading {
                        Circle().fill(.tint).frame(width: 8, height: 8)
                    }
                    DisclosureChevron(expanded: expanded)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 50)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityValue([reading ? "Reading now" : nil, expanded ? "Expanded" : "Collapsed"].compactMap { $0 }.joined(separator: ", "))

            if expanded {
                ChapterGrid(book: book, progress: progress)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
            }
        }
        .id(book.id)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem("Read") { RoundedRectangle(cornerRadius: 4).fill(.tint.opacity(0.18)).frame(width: 12, height: 12) }
            legendItem("Reading now") { RoundedRectangle(cornerRadius: 4).fill(.tint).frame(width: 12, height: 12) }
            legendItem("Highlights") { Circle().fill(.yellow).frame(width: 7, height: 7).padding(.horizontal, 2) }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }

    private func legendItem(_ title: String, @ViewBuilder swatch: () -> some View) -> some View {
        HStack(spacing: 6) {
            swatch()
            Text(title)
        }
    }

    // MARK: State

    private func collapseAll() {
        withAnimation(.snappy) {
            expandedVolume = work.hasVolumeLevel ? nil : work.volumes.first?.id
            expandedBook = nil
        }
    }

    /// Opens straight to wherever the user is reading in this work.
    private func restorePosition(progress: LibraryProgress, proxy: ScrollViewProxy) {
        guard !didRestorePosition else { return }
        didRestorePosition = true
        guard let current = progress.current,
              let book = work.books.first(where: { $0.contains(chapterID: current) }) else { return }
        expandedVolume = work.volumes.first { $0.books.contains(book) }?.id
        expandedBook = book.id
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            proxy.scrollTo(book.id, anchor: .top)
        }
    }
}

// MARK: - Pieces

/// A right chevron that turns down when its section is open.
private struct DisclosureChevron: View {
    let expanded: Bool

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
            .rotationEffect(.degrees(expanded ? 90 : 0))
            .accessibilityHidden(true)
    }
}

/// One row of plain-text locations with chevrons between them. Scrolls sideways
/// instead of wrapping, and keeps the deepest level in view.
struct BreadcrumbBar: View {
    struct Crumb: Identifiable {
        let id: String
        let title: String
        let action: (() -> Void)?
    }

    let crumbs: [Crumb]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(crumbs.enumerated()), id: \.element.id) { index, crumb in
                        HStack(spacing: 6) {
                            if index > 0 {
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                            let isLast = index == crumbs.count - 1
                            if let action = crumb.action, !isLast {
                                Button(crumb.title, action: action)
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.tint)
                                    .padding(.vertical, 6)
                            } else {
                                Text(crumb.title)
                                    .fontWeight(.semibold)
                                    .padding(.vertical, 6)
                                    .accessibilityAddTraits(.isSelected)
                            }
                        }
                        .id(crumb.id)
                    }
                }
                .font(.subheadline)
                .padding(.horizontal, 20)
            }
            .padding(.horizontal, -16)
            .onChange(of: crumbs.last?.id) { _, id in
                guard let id else { return }
                withAnimation(.snappy) { proxy.scrollTo(id, anchor: .trailing) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Location")
    }
}

/// Six chapters per row; each opens the reader.
private struct ChapterGrid: View {
    let book: LibraryBook
    let progress: LibraryProgress

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(1...book.chapterCount, id: \.self) { number in
                let id = book.chapterID(number)
                NavigationLink {
                    ReaderView(chapterID: id)
                } label: {
                    ChapterTile(
                        number: number,
                        unit: book.unit,
                        isRead: progress.read.contains(id),
                        isCurrent: progress.current == id,
                        isMarked: progress.marked.contains(id)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct ChapterTile: View {
    let number: Int
    let unit: LibraryBook.Unit
    let isRead: Bool
    let isCurrent: Bool
    let isMarked: Bool

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 44

    var body: some View {
        Text(number, format: .number)
            .font(.body.weight(isCurrent ? .bold : .medium))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(isCurrent ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
            .frame(maxWidth: .infinity, minHeight: height)
            .background(fill, in: .rect(cornerRadius: 12))
            .overlay(alignment: .bottom) {
                if isMarked {
                    Circle().fill(.yellow).frame(width: 5, height: 5).padding(.bottom, 5)
                }
            }
            .contentShape(.rect(cornerRadius: 12))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(unit.singular) \(number)")
            .accessibilityValue([
                isRead ? "Read" : nil,
                isCurrent ? "Reading now" : nil,
                isMarked ? "Has highlights" : nil,
            ].compactMap { $0 }.joined(separator: ", "))
    }

    private var fill: AnyShapeStyle {
        if isCurrent { return AnyShapeStyle(.tint) }
        if isRead { return AnyShapeStyle(.tint.opacity(0.18)) }
        return AnyShapeStyle(Color(.tertiarySystemGroupedBackground))
    }
}

#Preview {
    NavigationStack { LibraryBookView(work: LibraryCatalog.bible) }
        .previewEnvironment(signedIn: true)
}
