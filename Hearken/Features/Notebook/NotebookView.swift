import SwiftData
import SwiftUI
import UIKit

extension SettingsKey {
    static let notebookGrouping = "notebook.grouping"
}

/// How the Notebook groups its cards. Remembered between visits.
enum NotebookGrouping: String, CaseIterable, Identifiable {
    case book, color, recent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .book: "By Book"
        case .color: "By Color"
        case .recent: "Recent"
        }
    }

    var symbol: String {
        switch self {
        case .book: "books.vertical"
        case .color: "paintpalette"
        case .recent: "clock"
        }
    }
}

/// All, Highlights or Notes. A card with both shows under every tab.
enum NotebookFilter: String, CaseIterable, Identifiable {
    case all, highlights, notes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .highlights: "Highlights"
        case .notes: "Notes"
        }
    }
}

struct NotebookSection: Identifiable {
    let id: String
    let title: String
    let entries: [NotebookEntry]
}

/// My Notebook: every highlight and note in one list, with filters, grouping and search.
///
/// Search lives in the bottom toolbar (iOS 26), between Group and Share.
struct NotebookView: View {
    /// Shown in a sheet (from Search), so it needs a Close button.
    let showsClose: Bool

    @Environment(ContentService.self) private var content
    @Environment(HighlightLegend.self) private var legend
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.notebookGrouping) private var grouping: NotebookGrouping = .book
    @Query(sort: \Highlight.updatedAt, order: .reverse) private var highlights: [Highlight]
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]

    @State private var builder = NotebookBuilder()
    @State private var filter: NotebookFilter = .all
    @State private var hue: HighlightHue?
    /// Only this book's entries (from a chapter's menu in the Library).
    @State private var bookID: String?
    @State private var query = ""
    @State private var selected: NotebookEntry?
    @State private var openTarget: BookmarkTarget?

    init(bookID: String? = nil, showsClose: Bool = false) {
        self.showsClose = showsClose
        _bookID = State(initialValue: bookID)
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        let all = builder.entries(highlights: highlights, notes: notes, content: content)
        let inBook = bookID.map { id in all.filter { $0.bookID == id } } ?? all
        let shown = filtered(inBook)
        let sections = makeSections(shown)

        List {
            if !all.isEmpty {
                Section {
                    controls(inBook, shownCount: shown.count)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }

            if all.isEmpty {
                emptyState
            } else if shown.isEmpty {
                noMatches
            } else {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.entries) { row($0) }
                    } header: {
                        HStack {
                            Text(section.title)
                            Spacer()
                            Text(section.entries.count == 1 ? "1 entry" : "\(section.entries.count) entries")
                                .textCase(nil)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .refreshable { await CloudRefresh.refresh() }
        .navigationTitle("Notebook")
        .navigationSubtitle(summary(all))
        .toolbar {
            if showsClose {
                ToolbarItem(placement: .cancellationAction) {
                    SheetCancelButton("Close") { dismiss() }
                }
            }

            ToolbarItem(placement: .bottomBar) {
                CheckMenu(NotebookGrouping.allCases.map { option in
                    CheckMenuItem.choice(option.title, systemImage: option.symbol, isSelected: option == grouping) {
                        withAnimation(.snappy) { grouping = option }
                    }
                }) {
                    Label("Group", systemImage: "rectangle.3.group")
                }
                .tint(Color.primary)
                .accessibilityValue(grouping.title)
            }

            ToolbarSpacer(.flexible, placement: .bottomBar)
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
            ToolbarSpacer(.fixed, placement: .bottomBar)

            ToolbarItem(placement: .bottomBar) {
                Menu {
                    ShareLink(item: NotebookExport.text(sections, legend: legend, format: .plain)) {
                        Label { Text("Share as Text") } icon: { Image.menuIcon("doc.plaintext") }
                    }
                    ShareLink(item: NotebookExport.text(sections, legend: legend, format: .markdown)) {
                        Label { Text("Share as Markdown") } icon: { Image.menuIcon("number") }
                    }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .tint(Color.primary)
                .disabled(shown.isEmpty)
            }
        }
        .searchable(text: $query, prompt: "Highlights and notes")
        .searchToolbarBehavior(.minimize)
        // A bottom toolbar takes the tab bar's place here, like Mail and Notes.
        .toolbarVisibility(.hidden, for: .tabBar)
        .sheet(item: $selected) { entry in
            NotebookEntrySheet(entry: entry) { target in
                selected = nil
                openTarget = target
            }
        }
        .navigationDestination(item: $openTarget) { target in
            ReaderView(chapterID: target.chapterID, verse: target.verse)
        }
        .sensoryFeedback(.selection, trigger: hue)
        .sensoryFeedback(.selection, trigger: filter)
    }

    // MARK: Filtering and grouping

    private func filtered(_ entries: [NotebookEntry]) -> [NotebookEntry] {
        let query = trimmedQuery
        return entries.filter { entry in
            switch filter {
            case .all: break
            case .highlights: if !entry.hasHighlight { return false }
            case .notes: if !entry.hasNote { return false }
            }
            // Colors belong to highlights, so the chips don't apply on the Notes tab.
            if let hue, filter != .notes, entry.hue != hue { return false }
            if !query.isEmpty, !entry.matches(query) { return false }
            return true
        }
    }

    private func makeSections(_ entries: [NotebookEntry]) -> [NotebookSection] {
        switch grouping {
        case .book:
            var byBook: [String: [NotebookEntry]] = [:]
            for entry in entries { byBook[entry.bookID, default: []].append(entry) }
            return byBook.values
                .map { $0.sorted { $0.canonKey < $1.canonKey } }
                .sorted { ($0.first?.canonKey ?? 0) < ($1.first?.canonKey ?? 0) }
                .compactMap { list in
                    list.first.map { NotebookSection(id: $0.bookID, title: $0.bookTitle, entries: list) }
                }

        case .color:
            var byHue: [HighlightHue: [NotebookEntry]] = [:]
            var notesOnly: [NotebookEntry] = []
            for entry in entries {
                if let hue = entry.hue { byHue[hue, default: []].append(entry) } else { notesOnly.append(entry) }
            }
            let order = legend.entries.map(\.hue) + HighlightHue.allCases.filter { hue in !legend.entries.contains { $0.hue == hue } }
            var result = order.compactMap { hue in
                byHue[hue].map { NotebookSection(id: hue.rawValue, title: legend.name(for: hue), entries: $0.sorted { $0.canonKey < $1.canonKey }) }
            }
            if !notesOnly.isEmpty {
                result.append(NotebookSection(id: "notes", title: "Notes", entries: notesOnly.sorted { $0.canonKey < $1.canonKey }))
            }
            return result

        case .recent:
            let calendar = Calendar.current
            let now = Date.now
            let buckets: [(String, (Date) -> Bool)] = [
                ("Today", { calendar.isDateInToday($0) }),
                ("This Week", { now.timeIntervalSince($0) < 7 * 86_400 }),
                ("This Month", { now.timeIntervalSince($0) < 30 * 86_400 }),
                ("Earlier", { _ in true }),
            ]
            var grouped: [[NotebookEntry]] = Array(repeating: [], count: buckets.count)
            for entry in entries.sorted(by: { $0.date > $1.date }) {
                let index = buckets.firstIndex { $0.1(entry.date) } ?? buckets.count - 1
                grouped[index].append(entry)
            }
            return buckets.indices.compactMap { index in
                grouped[index].isEmpty ? nil : NotebookSection(id: buckets[index].0, title: buckets[index].0, entries: grouped[index])
            }
        }
    }

    private func summary(_ entries: [NotebookEntry]) -> String {
        let highlightCount = entries.filter(\.hasHighlight).count
        let noteCount = entries.filter(\.hasNote).count
        let bookCount = Set(entries.map(\.bookID)).count
        guard !entries.isEmpty else { return "Highlights and notes from the reader" }
        func count(_ n: Int, _ word: String) -> String { "\(n.formatted()) \(word)\(n == 1 ? "" : "s")" }
        return [count(highlightCount, "highlight"), count(noteCount, "note"), count(bookCount, "book")].joined(separator: " · ")
    }

    // MARK: Controls

    @ViewBuilder
    private func controls(_ entries: [NotebookEntry], shownCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let bookID {
                Button {
                    withAnimation(.snappy) { self.bookID = nil }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "books.vertical.fill")
                        Text(entries.first?.bookTitle ?? LibraryCatalog.location(ofChapter: bookID + ".1")?.book.title ?? "This Book")
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.glass)
                .tint(Color.primary)
                .accessibilityLabel("Showing one book")
                .accessibilityHint("Shows every book.")
            }

            Picker("Show", selection: $filter.animation(.snappy)) {
                ForEach(NotebookFilter.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            if filter != .notes {
                colorChips(entries)
            }

            if !trimmedQuery.isEmpty {
                Text(shownCount == 1 ? "1 result" : "\(shownCount) results")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// One chip per color in use, named with the person's own meanings, with counts.
    private func colorChips(_ entries: [NotebookEntry]) -> some View {
        var counts: [HighlightHue: Int] = [:]
        for entry in entries { if let hue = entry.hue { counts[hue, default: 0] += 1 } }
        let order = legend.entries.map(\.hue) + HighlightHue.allCases.filter { hue in !legend.entries.contains { $0.hue == hue } }
        let hues = order.filter { counts[$0, default: 0] > 0 }

        return ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(hues) { chipHue in
                    let on = hue == chipHue
                    Button {
                        withAnimation(.snappy) { hue = on ? nil : chipHue }
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(chipHue.color).frame(width: 12, height: 12)
                            Text(legend.name(for: chipHue))
                            Text("\(counts[chipHue, default: 0])")
                                .foregroundStyle(.secondary)
                                .fontWeight(.medium)
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 34)
                        .background(on ? chipHue.color.opacity(0.28) : Color(.secondarySystemGroupedBackground), in: .capsule)
                        .overlay(Capsule().strokeBorder(on ? chipHue.color : .clear, lineWidth: 1.5))
                        .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(legend.name(for: chipHue)), \(counts[chipHue, default: 0]) highlights")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -16)
    }

    // MARK: Rows

    private func row(_ entry: NotebookEntry) -> some View {
        Button { selected = entry } label: {
            NotebookCard(entry: entry, meaning: entry.hue.map { legend.name(for: $0) }, accent: Accent.color)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
        .swipeActions(edge: .trailing, allowsFullSwipe: entry.kind != .both) {
            // Highlights and notes are removed separately; removing one leaves the other.
            if let note = entry.note {
                Button(role: .destructive) { delete(note) } label: {
                    Label(entry.kind == .both ? "Delete Note" : "Delete", systemImage: entry.kind == .both ? "note.text" : "trash")
                }
                .tint(entry.kind == .both ? .orange : .red)
            }
            if let highlight = entry.highlight {
                Button(role: .destructive) { delete(highlight) } label: {
                    Label(entry.kind == .both ? "Remove Highlight" : "Delete", systemImage: entry.kind == .both ? "highlighter" : "trash")
                }
                .tint(.red)
            }
        }
        .contextMenu {
            Button("Open in Reader", menuIcon: "book") { openTarget = entry.target }
            Button("Copy", menuIcon: "doc.on.doc") {
                UIPasteboard.general.string = NotebookExport.text(for: entry, legend: legend, format: .plain)
            }
            ShareLink(item: NotebookExport.text(for: entry, legend: legend, format: .plain)) {
                Label { Text("Share") } icon: { Image.menuIcon("square.and.arrow.up") }
            }
            Divider()
            if let highlight = entry.highlight {
                Button(role: .destructive) { delete(highlight) } label: {
                    Label { Text("Remove Highlight") } icon: { Image.redTrash }
                }
            }
            if let note = entry.note {
                Button(role: .destructive) { delete(note) } label: {
                    Label { Text("Delete Note") } icon: { Image.redTrash }
                }
            }
        }
        .tint(Color.primary)
    }

    private func delete(_ highlight: Highlight) {
        withAnimation(.snappy) { modelContext.delete(highlight) }
    }

    private func delete(_ note: Note) {
        withAnimation(.snappy) { modelContext.delete(note) }
    }

    // MARK: Empty states

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nothing Here Yet", systemImage: "books.vertical")
        } description: {
            Text("Highlights and notes you make in the reader appear here.")
        } actions: {
            Button("Open the Reader") {
                openTarget = BookmarkTarget(chapterID: content.defaultChapterID, verse: 1)
            }
            .buttonStyle(.glassProminent)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var noMatches: some View {
        Group {
            if trimmedQuery.isEmpty {
                ContentUnavailableView {
                    Label("No Matches", systemImage: "line.3.horizontal.decrease")
                } description: {
                    Text("Nothing here matches these filters.")
                } actions: {
                    Button("Clear Filters") {
                        withAnimation(.snappy) {
                            filter = .all
                            hue = nil
                            bookID = nil
                        }
                    }
                }
            } else {
                ContentUnavailableView.search(text: trimmedQuery)
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

/// A Notebook card. Its shape says what it is:
/// - a highlight: the marked words washed in their color, with a little context;
/// - a note: the note leads, with the verse it's on underneath in grey;
/// - both: the highlight, then the note under a thin rule.
struct NotebookCard: View {
    let entry: NotebookEntry
    let meaning: String?
    /// Explicit, because the row's tint is set to primary for its menu icons.
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            switch entry.kind {
            case .highlight:
                quote
            case .both:
                quote
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "note.text")
                            .font(.footnote)
                            .foregroundStyle(accent)
                        Text(entry.note?.body ?? "")
                            .font(.subheadline)
                            .lineLimit(4)
                    }
                }
            case .note:
                Text(entry.note?.body ?? "")
                    .font(.body)
                    .lineLimit(6)
                verseUnderNote
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        .contentShape(.rect(cornerRadius: 20))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens the entry. Swipe or touch and hold for more.")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(entry.reference)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(accent)
                .lineLimit(1)
            if let hue = entry.hue {
                tag {
                    Circle().fill(hue.color).frame(width: 9, height: 9)
                    Text(meaning ?? hue.colorName)
                }
            }
            if entry.hasNote {
                tag {
                    Image(systemName: "note.text")
                    Text("Note")
                }
            }
            Spacer(minLength: 4)
            Text(DateLabel.short(entry.date))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func tag<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 4) { content() }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    @ViewBuilder
    private var quote: some View {
        if entry.quote.isAvailable {
            Text(quoteText)
                .font(.scripture(size: 17))
                .lineSpacing(3)
                .lineLimit(6)
        } else {
            unavailable
        }
    }

    private var quoteText: AttributedString {
        var before = AttributedString(entry.quote.before)
        var marked = AttributedString(entry.quote.marked)
        var after = AttributedString(entry.quote.after)
        before.swiftUI.foregroundColor = Color.secondary
        after.swiftUI.foregroundColor = Color.secondary
        if let highlight = entry.highlight { marked.applyHighlight(highlight.hue, style: highlight.style) }
        return before + marked + after
    }

    @ViewBuilder
    private var verseUnderNote: some View {
        if entry.quote.isAvailable {
            HStack(alignment: .top, spacing: 10) {
                Capsule()
                    .fill(.quaternary)
                    .frame(width: 3)
                Text(entry.quote.fullText)
                    .font(.scripture(size: 15))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            unavailable
        }
    }

    private var unavailable: some View {
        Text("Text not available yet")
            .font(.footnote)
            .italic()
            .foregroundStyle(.secondary)
    }

    private var accessibilityText: String {
        var parts = [entry.reference]
        if let hue = entry.hue {
            parts.append("\(meaning ?? hue.colorName), highlighted: \(entry.quote.marked)")
        }
        if let note = entry.note, !note.body.isEmpty {
            parts.append("Note: \(note.body)")
        }
        parts.append(DateLabel.short(entry.date))
        return parts.joined(separator: ". ")
    }
}

#Preview {
    NavigationStack { NotebookView() }
        .previewEnvironment(signedIn: true)
}
