import SwiftData
import SwiftUI
import UIKit

private struct NoteTarget: Identifiable {
    let verse: Verse
    var id: String { verse.id }
}

/// Reads one chapter. Tap a verse (or an existing highlight) to open the highlight toolbar.
///
/// v1 highlights whole verses. Character-range highlights need a TextKit 2 text view,
/// which is the next step for the reader (see the build plan).
struct ReaderView: View {
    let chapterID: String

    @Environment(ContentService.self) private var content
    @Environment(HighlightLegend.self) private var legend
    @Environment(AccountService.self) private var account
    @Environment(\.modelContext) private var modelContext

    @Query private var highlights: [Highlight]
    @Query private var notes: [Note]
    @Query private var progressRecords: [ReadingProgress]

    @AppStorage(SettingsKey.scriptureTextSize) private var textSize: Double = 20
    @AppStorage(SettingsKey.showVerseNumbers) private var showVerseNumbers = true
    @AppStorage(SettingsKey.onboardingDone) private var onboardingDone = false
    @ScaledMetric(relativeTo: .body) private var bodyMetric: CGFloat = 17

    @State private var selectedVerse: Int?
    @State private var pendingStyle: HighlightStyle?
    @State private var noteTarget: NoteTarget?
    @State private var showSignInPrompt = false

    private let mastery = MasteryService()

    init(chapterID: String) {
        self.chapterID = chapterID
        let id = chapterID
        _highlights = Query(filter: #Predicate<Highlight> { $0.chapterID == id })
        _notes = Query(filter: #Predicate<Note> { $0.chapterID == id })
        _progressRecords = Query(filter: #Predicate<ReadingProgress> { $0.chapterID == id })
    }

    private var chapter: Chapter? { content.chapter(chapterID) }
    private var fontSize: CGFloat { CGFloat(textSize) * bodyMetric / 17 }
    private var progress: ReadingProgress? { progressRecords.first }

    var body: some View {
        Group {
            if let chapter {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        header(chapter)
                        ForEach(chapter.verses) { verse in
                            verseBlock(verse)
                        }
                        footer
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            } else {
                ContentUnavailableView("Chapter not found", systemImage: "book.closed")
            }
        }
        .navigationTitle(content.title(forChapter: chapterID))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let selectedVerse, let verse = chapter?.verses.first(where: { $0.number == selectedVerse }) {
                toolbar(for: verse)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: selectedVerse)
        .sensoryFeedback(.selection, trigger: selectedVerse)
        .sheet(item: $noteTarget) { target in
            NoteEditorView(
                chapterID: chapterID,
                verse: target.verse,
                reference: content.reference(chapterID: chapterID, verse: target.verse.number),
                existing: notes.first { $0.verse == target.verse.number }
            )
        }
        .alert("Sign in to save highlights and notes", isPresented: $showSignInPrompt) {
            Button("Sign In") { onboardingDone = false }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Your highlights, notes and progress are saved to your own iCloud.")
        }
        .onAppear(perform: touchProgress)
    }

    // MARK: Pieces

    private func header(_ chapter: Chapter) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(content.bookTitle(forChapter: chapterID).uppercased())
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Chapter \(chapter.number)")
                .font(.scripture(size: 34, weight: .bold))
            if let heading = chapter.heading {
                Text(heading)
                    .font(.scripture(size: 16).italic())
                    .foregroundStyle(.secondary)
            }
            if chapter.isExcerpt == true {
                Label("Sample excerpt. The full chapter arrives with the content import.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func verseBlock(_ verse: Verse) -> some View {
        let highlight = highlights.first { $0.covers(verse: verse.number) }
        let note = notes.first { $0.verse == verse.number }

        VerseRow(
            verse: verse,
            highlight: highlight.map { (hue: $0.hue, style: $0.style) },
            showNumber: showVerseNumbers,
            fontSize: fontSize,
            isSelected: selectedVerse == verse.number
        )
        .onTapGesture {
            selectedVerse = selectedVerse == verse.number ? nil : verse.number
            pendingStyle = nil
            if let progress { progress.lastVerse = verse.number; progress.updatedAt = .now }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens highlight options")

        if let note {
            Button {
                noteTarget = NoteTarget(verse: verse)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "square.and.pencil").foregroundStyle(.tint)
                    Text(note.body)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(4)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 10)
            .accessibilityLabel("Note on verse \(verse.number): \(note.body)")
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if progress?.completedAt != nil {
                Label("Chapter read", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button {
                    markRead()
                } label: {
                    Label("Mark Chapter as Read", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
        }
        .padding(.top, 24)
    }

    private func toolbar(for verse: Verse) -> some View {
        let existing = highlights.first { $0.covers(verse: verse.number) }
        return HighlightToolbar(
            reference: content.reference(chapterID: chapterID, verse: verse.number),
            entries: legend.entries,
            name: legend.name(for:),
            showNames: legend.showNames,
            selectedHue: existing?.hue,
            style: existing?.style ?? pendingStyle ?? legend.defaultStyle,
            onPick: { hue in pick(hue, verse: verse, existing: existing) },
            onStyle: { style in setStyle(style, existing: existing) },
            onNote: { openNote(for: verse) },
            onCopy: { copy(verse) },
            onRemove: { if let existing { modelContext.delete(existing) } },
            onClose: { selectedVerse = nil }
        )
    }

    // MARK: Actions

    private func requireSignIn() -> Bool {
        if account.isSignedIn { return true }
        showSignInPrompt = true
        return false
    }

    private func pick(_ hue: HighlightHue, verse: Verse, existing: Highlight?) {
        guard requireSignIn() else { return }
        if let existing {
            existing.hue = hue
        } else {
            modelContext.insert(Highlight(chapterID: chapterID, verse: verse.number, hue: hue, style: pendingStyle ?? legend.defaultStyle))
        }
    }

    private func setStyle(_ style: HighlightStyle, existing: Highlight?) {
        pendingStyle = style
        existing?.style = style
    }

    private func openNote(for verse: Verse) {
        guard requireSignIn() else { return }
        noteTarget = NoteTarget(verse: verse)
    }

    private func copy(_ verse: Verse) {
        UIPasteboard.general.string = "\(verse.text) (\(content.reference(chapterID: chapterID, verse: verse.number)))"
    }

    private func touchProgress() {
        guard account.isSignedIn else { return }
        if let progress {
            progress.updatedAt = .now
        } else {
            modelContext.insert(ReadingProgress(chapterID: chapterID))
        }
    }

    private func markRead() {
        guard requireSignIn() else { return }
        let record = progress ?? {
            let new = ReadingProgress(chapterID: chapterID)
            modelContext.insert(new)
            return new
        }()
        record.completedAt = .now
        record.updatedAt = .now
        mastery.award(MasteryConfig.standard.chapterReadXP, reason: "chapter", in: modelContext)
    }
}

/// One verse, with its highlight drawn inline and the verse number in the tint color.
struct VerseRow: View {
    let verse: Verse
    let highlight: (hue: HighlightHue, style: HighlightStyle)?
    let showNumber: Bool
    let fontSize: CGFloat
    let isSelected: Bool

    var body: some View {
        text
            .font(.scripture(size: fontSize))
            .lineSpacing(fontSize * 0.35)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground))
                }
            }
            .padding(.horizontal, -8)
            .contentShape(.rect)
    }

    private var text: Text {
        var attributed = AttributedString(verse.text)
        if let highlight {
            attributed.applyHighlight(highlight.hue, style: highlight.style)
        }
        let verseText = Text(attributed)
        guard showNumber else { return verseText }
        let number = Text("\(verse.number) ")
            .font(.system(size: fontSize * 0.6, weight: .semibold))
            .foregroundStyle(.tint)
            .baselineOffset(fontSize * 0.3)
        return Text("\(number)\(verseText)")
    }
}

#Preview {
    NavigationStack { ReaderView(chapterID: "bofm.alma.32") }
        .previewEnvironment(signedIn: true)
}
