import SwiftData
import SwiftUI

// The reader on iPhone Duo (see DUO.md and HearthDuo.swift):
// - Open wide (inner landscape): the book's chapters on the leading pane in an even four-column
//   grid, the text on the trailing pane, Highlight and Explain on the rail.
// - Book (partly folded, held): the text alone on the left page, with no bars, and the notebook
//   for this chapter (or Explain) on the right page. Tapping a note or highlight marks its verse.
// Both are drawn by ReaderPage from the pose; everything else in the reader is unchanged.

/// A reader action sent from the toolbar (the Duo's rail) to the page that owns the selection.
struct ReaderCommand: Equatable {
    enum Kind: Equatable { case highlight, explain }
    let kind: Kind
    let id = UUID()
}

/// Open wide: the current book's chapters, four to a row, beside the text. Picking one opens it.
struct ReaderChapterPane: View {
    let chapterID: String
    let onSelect: (String) -> Void

    @Query private var progressRecords: [ReadingProgress]
    @Query private var highlights: [Highlight]

    init(chapterID: String, onSelect: @escaping (String) -> Void) {
        self.chapterID = chapterID
        self.onSelect = onSelect
    }

    var body: some View {
        if let location = LibraryCatalog.location(ofChapter: chapterID), location.book.chapterCount > 0 {
            let book = location.book
            let progress = LibraryProgress(progress: progressRecords, highlights: highlights)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(book.title)
                            .font(.title2.bold())
                            .accessibilityAddTraits(.isHeader)
                        Text(book.unit.count(book.chapterCount))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    // Four columns: an even grid, so nothing straddles a fold.
                    LazyVGrid(columns: HearthEvenColumns.flexible(4, spacing: 8), spacing: 8) {
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
                }
                .padding(16)
            }
            .refreshable { await CloudRefresh.refresh() }
            .background(Color(.systemGroupedBackground))
        } else {
            ContentUnavailableView("No Chapters", systemImage: "books.vertical")
        }
    }
}

/// Book: the right-hand page. The reader's controls at the top (the text page has no bars), then
/// Explain when it's open, or this chapter's notes and highlights. Each entry is tied to its
/// verse: tapping it marks that verse on the left page.
struct ReaderNotebookPane: View {
    let chapterID: String
    /// The reader's controls (Back, location, Listen, Reader Options).
    let header: AnyView
    @Binding var explainRequest: ExplainRequest?
    let onMark: (Int) -> Void
    let onOpenPassage: (BookmarkTarget) -> Void

    @Environment(ContentService.self) private var content
    @Environment(HighlightLegend.self) private var legend
    @Environment(\.modelContext) private var modelContext
    @Query private var notes: [Note]
    @Query private var highlights: [Highlight]
    @State private var editing: NoteEditTarget?

    private struct NoteEditTarget: Identifiable {
        let verse: Verse
        var id: String { verse.id }
    }

    init(
        chapterID: String,
        header: AnyView,
        explainRequest: Binding<ExplainRequest?>,
        onMark: @escaping (Int) -> Void,
        onOpenPassage: @escaping (BookmarkTarget) -> Void
    ) {
        self.chapterID = chapterID
        self.header = header
        _explainRequest = explainRequest
        self.onMark = onMark
        self.onOpenPassage = onOpenPassage
        let id = chapterID
        _notes = Query(filter: #Predicate<Note> { $0.chapterID == id })
        _highlights = Query(filter: #Predicate<Highlight> { $0.chapterID == id })
    }

    private var chapter: Chapter? { content.chapter(chapterID) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let request = explainRequest {
                ExplainSheet(
                    request: request,
                    onOpenPassage: onOpenPassage,
                    onSaveNote: saveExplanation,
                    inline: true,
                    onClose: { explainRequest = nil }
                )
                .id(request.id)
            } else if let chapter {
                notebook(chapter)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGroupedBackground))
        .sheet(item: $editing) { target in
            NoteEditorView(
                chapterID: chapterID,
                verse: target.verse,
                reference: content.reference(chapterID: chapterID, verse: target.verse.number),
                existing: notes.first { $0.verse == target.verse.number }
            )
        }
    }

    /// Save as Note from Explain: added to the note on the first selected verse, as in the sheet.
    private func saveExplanation(_ text: String) -> Bool {
        guard let request = explainRequest else { return false }
        if let note = notes.first(where: { $0.verse == request.startVerse }) {
            note.body = note.body.isEmpty ? text : note.body + "\n\n" + text
            note.updatedAt = .now
        } else {
            modelContext.insert(Note(chapterID: chapterID, verse: request.startVerse, body: text))
        }
        return true
    }

    private func editNote(_ number: Int) {
        guard let verse = chapter?.verses.first(where: { $0.number == number }) else { return }
        editing = NoteEditTarget(verse: verse)
    }

    private var sortedNotes: [Note] { notes.sorted { $0.verse < $1.verse } }
    private var sortedHighlights: [Highlight] {
        highlights.sorted { ($0.startVerse, $0.startOffset) < ($1.startVerse, $1.startOffset) }
    }

    @ViewBuilder
    private func notebook(_ chapter: Chapter) -> some View {
        if notes.isEmpty && highlights.isEmpty {
            ContentUnavailableView(
                "Nothing Marked Yet",
                systemImage: "note.text",
                description: Text("Select text on the left page to highlight it, add a note, or explain it.")
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Notebook")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    if !notes.isEmpty {
                        section("Notes") {
                            ForEach(sortedNotes) { note in noteRow(note, chapter: chapter) }
                        }
                    }
                    if !highlights.isEmpty {
                        section("Highlights") {
                            ForEach(sortedHighlights) { highlight in highlightRow(highlight, chapter: chapter) }
                        }
                    }
                }
                .padding(16)
            }
            .refreshable { await CloudRefresh.refresh() }
        }
    }

    private func section<Rows: View>(_ title: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 8) { rows() }
        }
    }

    private func noteRow(_ note: Note, chapter: Chapter) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                onMark(note.verse)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(content.reference(chapterID: chapter.id, verse: note.verse))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(note.body)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Marks this verse on the left page.")
            Button("Edit Note", systemImage: "pencil") { editNote(note.verse) }
                .labelStyle(.iconOnly)
                .tint(Color.primary)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    private func highlightRow(_ highlight: Highlight, chapter: Chapter) -> some View {
        let text = chapter.verses
            .filter { $0.number >= highlight.startVerse && $0.number <= highlight.endVerse }
            .map(\.text)
            .joined(separator: " ")
        let base = content.reference(chapterID: chapter.id, verse: highlight.startVerse)
        let reference = highlight.endVerse > highlight.startVerse ? "\(base)–\(highlight.endVerse)" : base
        return Button {
            onMark(highlight.startVerse)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(highlight.hue.color)
                    .frame(width: 10, height: 10)
                    .padding(.top, 5)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(reference) · \(legend.name(for: highlight.hue))")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(text)
                        .font(.scripture(size: 16))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Marks this verse on the left page.")
    }
}
