import SwiftData
import SwiftUI

/// One Notebook entry, opened from its card: the full passage, the highlight and the note.
///
/// The highlight and the note are handled separately. Either can be added, changed or removed
/// here without touching the other; removing the last of the two closes the sheet.
struct NotebookEntrySheet: View {
    let chapterID: String
    let onOpen: (BookmarkTarget) -> Void

    @Environment(ContentService.self) private var content
    @Environment(HighlightLegend.self) private var legend
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.accent) private var accent: AccentOption = .blue
    @Query private var chapterNotes: [Note]

    @State private var highlight: Highlight?
    @State private var note: Note?
    /// Where a new note or highlight goes: the note's verse, or the highlight's first verse.
    @State private var anchorVerse: Int
    @State private var editingNote = false

    init(entry: NotebookEntry, onOpen: @escaping (BookmarkTarget) -> Void) {
        chapterID = entry.chapterID
        self.onOpen = onOpen
        _highlight = State(initialValue: entry.highlight)
        _note = State(initialValue: entry.note)
        _anchorVerse = State(initialValue: entry.note?.verse ?? entry.startVerse)
        let id = entry.chapterID
        _chapterNotes = Query(filter: #Predicate<Note> { $0.chapterID == id })
    }

    private var verses: [Verse] {
        let range = highlight.map { min($0.startVerse, $0.endVerse)...max($0.startVerse, $0.endVerse) } ?? anchorVerse...anchorVerse
        return content.chapter(chapterID)?.verses.filter { range.contains($0.number) } ?? []
    }

    private var reference: String {
        NotebookBuilder.reference(
            chapterID: chapterID,
            start: highlight?.startVerse ?? anchorVerse,
            end: highlight?.endVerse ?? anchorVerse,
            content: content
        )
    }

    /// The verse a note is (or would be) on.
    private var noteVerse: Verse? {
        let number = note?.verse ?? anchorVerse
        return content.chapter(chapterID)?.verses.first { $0.number == number }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { passage }

                highlightSection

                noteSection

                if let dates = datesLine {
                    Section {
                        EmptyView()
                    } footer: {
                        Text(dates)
                    }
                }
            }
            .contentMargins(.bottom, 80, for: .scrollContent)
            .navigationTitle(reference)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", role: .close) { dismiss() }
                        .tint(Color.primary)
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: shareText) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .tint(Color.primary)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    onOpen(BookmarkTarget(chapterID: chapterID, verse: note?.verse ?? highlight?.startVerse ?? anchorVerse))
                } label: {
                    Label("Open in Reader", systemImage: "book.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .buttonBorderShape(.capsule)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .sheet(isPresented: $editingNote, onDismiss: refreshNote) {
                if let verse = noteVerse {
                    NoteEditorView(
                        chapterID: chapterID,
                        verse: verse,
                        reference: content.reference(chapterID: chapterID, verse: verse.number),
                        existing: note
                    )
                }
            }
        }
        .tint(accent.color)
        .presentationDetents([.medium, .large])
        .sensoryFeedback(.selection, trigger: highlight?.hueRaw)
    }

    // MARK: Passage

    @ViewBuilder
    private var passage: some View {
        if verses.isEmpty {
            Text("This chapter's text arrives with the full scripture import.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            Text(passageText)
                .font(.scripture(size: 19))
                .lineSpacing(4)
                .padding(.vertical, 4)
                .textSelection(.enabled)
        }
    }

    private var passageText: AttributedString {
        var result = AttributedString()
        for (index, verse) in verses.enumerated() {
            var number = AttributedString("\(verse.number) ")
            number.swiftUI.font = .system(size: 12, weight: .bold)
            number.swiftUI.foregroundColor = accent.color
            number.swiftUI.baselineOffset = 5
            if index > 0 { result += AttributedString(" ") }
            result += number

            guard let highlight else {
                result += AttributedString(verse.text)
                continue
            }
            let length = verse.text.utf16.count
            let lower = verse.number == highlight.startVerse ? min(max(highlight.startOffset, 0), length) : 0
            let upper = verse.number == highlight.endVerse && highlight.endOffset >= 0 ? min(highlight.endOffset, length) : length
            var marked = AttributedString(verse.text.utf16Slice(lower, upper))
            marked.applyHighlight(highlight.hue, style: highlight.style)
            result += AttributedString(verse.text.utf16Slice(0, lower)) + marked + AttributedString(verse.text.utf16Slice(upper, length))
        }
        return result
    }

    // MARK: Highlight

    @ViewBuilder
    private var highlightSection: some View {
        Section {
            swatches
            if let highlight {
                Picker("Style", selection: Binding(get: { highlight.style }, set: { highlight.style = $0 })) {
                    ForEach(HighlightStyle.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)

                Button(role: .destructive) {
                    modelContext.delete(highlight)
                    self.highlight = nil
                    closeIfEmpty()
                } label: {
                    Label("Remove Highlight", systemImage: "highlighter")
                }
                .tint(.red)
            }
        } header: {
            Text("Highlight")
        } footer: {
            if let highlight {
                Text(legend.name(for: highlight.hue))
            } else {
                Text("Not highlighted. Tap a color to highlight verse \(anchorVerse).")
            }
        }
    }

    private var swatches: some View {
        let hues = legend.entries.map(\.hue) + (highlight.map { current in legend.entries.contains { $0.hue == current.hue } ? [] : [current.hue] } ?? [])
        return HStack(spacing: 0) {
            ForEach(hues) { hue in
                let on = highlight?.hue == hue
                Button {
                    pick(hue)
                } label: {
                    Circle()
                        .fill(hue.color)
                        .frame(width: 34, height: 34)
                        .padding(3)
                        .overlay(Circle().strokeBorder(on ? Color.primary : .clear, lineWidth: 2.5))
                        .overlay {
                            if on {
                                Image(systemName: "checkmark")
                                    .font(.footnote.weight(.bold))
                                    .foregroundStyle(.black.opacity(0.7))
                            }
                        }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(legend.name(for: hue))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private func pick(_ hue: HighlightHue) {
        withAnimation(.snappy) {
            if let highlight {
                highlight.hue = hue
            } else {
                let new = Highlight(chapterID: chapterID, verse: anchorVerse, hue: hue, style: legend.defaultStyle)
                modelContext.insert(new)
                highlight = new
            }
        }
    }

    // MARK: Note

    @ViewBuilder
    private var noteSection: some View {
        Section {
            if let note, !note.body.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(note.body)
                        .textSelection(.enabled)
                    if !note.tags.isEmpty {
                        Text(note.tags.map { "#\($0)" }.joined(separator: " "))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)

                Button("Edit Note", systemImage: "pencil") { editingNote = true }
                    .disabled(noteVerse == nil)

                Button(role: .destructive) {
                    modelContext.delete(note)
                    self.note = nil
                    closeIfEmpty()
                } label: {
                    Label("Delete Note", systemImage: "trash")
                }
                .tint(.red)
            } else {
                Button("Add Note", systemImage: "square.and.pencil") { editingNote = true }
                    .disabled(noteVerse == nil)
            }
        } header: {
            Text("Note")
        } footer: {
            if note == nil {
                Text("No note on verse \(anchorVerse) yet.")
            }
        }
    }

    /// After the note editor closes: pick up a new note, or let go of a deleted one.
    private func refreshNote() {
        let verse = note?.verse ?? anchorVerse
        note = chapterNotes.first { $0.verse == verse && !$0.isDeleted }
        closeIfEmpty()
    }

    private func closeIfEmpty() {
        if highlight == nil && note == nil { dismiss() }
    }

    // MARK: Text

    private var datesLine: String? {
        var parts: [String] = []
        if let highlight { parts.append("Highlighted \(DateLabel.short(highlight.createdAt))") }
        if let note {
            let edited = note.updatedAt.timeIntervalSince(note.createdAt) > 60
            parts.append("Note \(edited ? "edited" : "added") \(DateLabel.short(note.updatedAt))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var shareText: String {
        let quote: String
        if let highlight {
            quote = NotebookBuilder.cutQuote(for: highlight, verses: verses).marked
        } else {
            quote = verses.map(\.text).joined(separator: " ")
        }
        return NotebookExport.block(
            reference: reference,
            meaning: highlight.map { legend.name(for: $0.hue) },
            quote: quote,
            note: note?.body,
            format: .plain
        )
    }
}
