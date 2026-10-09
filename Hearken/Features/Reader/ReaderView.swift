import SwiftData
import SwiftUI
import UIKit

private struct NoteTarget: Identifiable {
    let verse: Verse
    var id: String { verse.id }
}

/// The reader. Shows one chapter at a time and carries the location control at the top,
/// which expands into breadcrumbs for jumping to any chapter.
struct ReaderView: View {
    @Environment(ContentService.self) private var content
    @State private var chapterID: String
    @State private var showsLocation = false
    @State private var startsAtEnd = false
    @AppStorage(SettingsKey.readerLayout) private var layout: ReaderLayout = .scroll

    init(chapterID: String) {
        _chapterID = State(initialValue: chapterID)
    }

    var body: some View {
        ReaderPage(chapterID: chapterID, layout: layout, startsAtEnd: startsAtEnd) { id, atEnd in
            startsAtEnd = atEnd
            chapterID = id
        }
            .id(chapterID)
            .navigationTitle(content.title(forChapter: chapterID))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    ReaderLocationPill(title: content.title(forChapter: chapterID), expanded: showsLocation) {
                        withAnimation(.snappy) { showsLocation.toggle() }
                    }
                }
                .sharedBackgroundVisibility(.hidden)

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Layout", selection: $layout) {
                            ForEach(ReaderLayout.allCases) { option in
                                Label(option.title, systemImage: option.symbol).tag(option)
                            }
                        }
                    } label: {
                        Label("Reading Layout", systemImage: layout.symbol)
                    }
                }
            }
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    if showsLocation {
                        Rectangle()
                            .fill(Color.black.opacity(0.18))
                            .ignoresSafeArea()
                            .onTapGesture { withAnimation(.snappy) { showsLocation = false } }
                            .accessibilityHidden(true)
                            .transition(.opacity)
                        ReaderLocationPanel(chapterID: chapterID) { id in
                            withAnimation(.snappy) {
                                startsAtEnd = false
                                chapterID = id
                                showsLocation = false
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                        .transition(.scale(scale: 0.92, anchor: .top).combined(with: .opacity))
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: chapterID)
    }
}

/// Reads one chapter. Tap a verse (or an existing highlight) to open the highlight toolbar.
///
/// v1 highlights whole verses. Character-range highlights need a TextKit 2 text view,
/// which is the next step for the reader (see the build plan).
struct ReaderPage: View {
    let chapterID: String
    let layout: ReaderLayout
    /// Page Turn only: open on the last page (after turning back from the next chapter).
    let startsAtEnd: Bool
    /// Page Turn only: called after a page turn crosses into the previous or next chapter.
    let onTurnChapter: (_ chapterID: String, _ atEnd: Bool) -> Void

    @Environment(ContentService.self) private var content
    @Environment(HighlightLegend.self) private var legend
    @Environment(AccountService.self) private var account
    @Environment(\.modelContext) private var modelContext
    @Environment(\.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
    @State private var pageCache = PageCache()

    private let mastery = MasteryService()

    init(
        chapterID: String,
        layout: ReaderLayout = .scroll,
        startsAtEnd: Bool = false,
        onTurnChapter: @escaping (_ chapterID: String, _ atEnd: Bool) -> Void = { _, _ in }
    ) {
        self.chapterID = chapterID
        self.layout = layout
        self.startsAtEnd = startsAtEnd
        self.onTurnChapter = onTurnChapter
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
            if let chapter, layout == .pages {
                pagedBody(chapter)
            } else if let chapter {
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
                ContentUnavailableView(
                    "Not Imported Yet",
                    systemImage: "book.closed",
                    description: Text("This chapter's text arrives with the full scripture import.")
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            // Scroll: the toolbar takes space. Page Turn: it floats, so pages don't re-flow.
            if layout == .scroll { selectionToolbar }
        }
        .overlay(alignment: .bottom) {
            if layout == .pages { selectionToolbar }
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
            Text(content.bookTitle(forChapter: chapter.id).uppercased())
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
        footerView(isRead: progress?.completedAt != nil, markRead: markRead)
    }

    private func footerView(isRead: Bool, markRead: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if isRead {
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

    @ViewBuilder
    private var selectionToolbar: some View {
        if let selectedVerse, let verse = chapter?.verses.first(where: { $0.number == selectedVerse }) {
            toolbar(for: verse)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
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

// MARK: - Page Turn

/// One measurable block of a chapter. Pages are filled with whole units.
enum ReaderUnit: Hashable {
    case header
    case verse(Int) // index into chapter.verses
    case footer
}

/// Remembers the last pagination per chapter so pages aren't re-measured on every render.
final class PageCache {
    private var entries: [AnyHashable: [[ReaderUnit]]] = [:]
    private lazy var sizer = UIHostingController(rootView: AnyView(EmptyView()))

    func pages(for key: AnyHashable, compute: (UIHostingController<AnyView>) -> [[ReaderUnit]]) -> [[ReaderUnit]] {
        if let pages = entries[key] { return pages }
        let pages = compute(sizer)
        if entries.count > 12 { entries.removeAll() }
        entries[key] = pages
        return pages
    }
}

extension ReaderPage {
    private static let pageTopPadding: CGFloat = 12
    private static let pageFooterHeight: CGFloat = 40
    private static let unitSpacing: CGFloat = 4

    func pagedBody(_ chapter: Chapter) -> some View {
        GeometryReader { geo in
            let pages = pagination(for: chapter, size: geo.size, interactive: true)
            let previousID = LibraryCatalog.adjacentChapter(to: chapterID, offset: -1)
            let nextID = LibraryCatalog.adjacentChapter(to: chapterID, offset: 1)

            PageCurlView(
                pageCount: pages.count,
                startPage: startsAtEnd ? pages.count - 1 : 0,
                curl: !reduceMotion,
                environment: environment,
                page: { index in
                    AnyView(pageView(pages[index], chapter: chapter, index: index, count: pages.count, interactive: true))
                },
                previousChapterPage: previousID.flatMap { neighborPage($0, last: true, size: geo.size) },
                nextChapterPage: nextID.flatMap { neighborPage($0, last: false, size: geo.size) },
                onLeaveChapter: { forward in
                    selectedVerse = nil
                    if let id = forward ? nextID : previousID {
                        onTurnChapter(id, !forward)
                    }
                }
            )
        }
    }

    /// A neighboring chapter's first or last page, drawn without highlights or notes.
    /// It's what the curl reveals; the reader then switches to that chapter for real.
    private func neighborPage(_ id: String, last: Bool, size: CGSize) -> AnyView? {
        guard let neighbor = content.chapter(id) else { return nil }
        let pages = pagination(for: neighbor, size: size, interactive: false)
        guard let page = last ? pages.last : pages.first else { return nil }
        let index = last ? pages.count - 1 : 0
        return AnyView(pageView(page, chapter: neighbor, index: index, count: pages.count, interactive: false))
    }

    private func pageView(_ units: [ReaderUnit], chapter: Chapter, index: Int, count: Int, interactive: Bool) -> some View {
        VStack(alignment: .leading, spacing: Self.unitSpacing) {
            ForEach(units, id: \.self) { unit in
                unitView(unit, chapter: chapter, interactive: interactive)
            }
            Spacer(minLength: 0)
            Text("\(index + 1) of \(count)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: Self.pageFooterHeight - 8)
                .accessibilityLabel("Page \(index + 1) of \(count)")
        }
        .padding(.horizontal, 24)
        .padding(.top, Self.pageTopPadding)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private func unitView(_ unit: ReaderUnit, chapter: Chapter, interactive: Bool) -> some View {
        switch unit {
        case .header:
            header(chapter)
        case .verse(let index):
            if interactive {
                verseBlock(chapter.verses[index])
            } else {
                VerseRow(verse: chapter.verses[index], highlight: nil, showNumber: showVerseNumbers, fontSize: fontSize, isSelected: false)
            }
        case .footer:
            if interactive {
                footer
            } else {
                footerView(isRead: false, markRead: {})
            }
        }
    }

    /// Splits a chapter into pages of whole verses that fit `size`.
    /// A verse taller than a page gets a page to itself.
    private func pagination(for chapter: Chapter, size: CGSize, interactive: Bool) -> [[ReaderUnit]] {
        let noteVerses = interactive ? notes.map(\.verse).sorted() : []
        let key = PaginationKey(
            chapterID: chapter.id, width: size.width, height: size.height, textSize: textSize,
            showNumbers: showVerseNumbers, dynamicType: environment.dynamicTypeSize, noteVerses: noteVerses,
            isRead: interactive && progress?.completedAt != nil
        )
        return pageCache.pages(for: key) { sizer in
            let width = size.width - 48
            let available = size.height - Self.pageTopPadding - Self.pageFooterHeight
            let units: [ReaderUnit] = [.header] + chapter.verses.indices.map { .verse($0) } + [.footer]

            var pages: [[ReaderUnit]] = []
            var current: [ReaderUnit] = []
            var used: CGFloat = 0
            for unit in units {
                sizer.rootView = AnyView(unitView(unit, chapter: chapter, interactive: interactive).environment(\.self, environment))
                let height = sizer.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
                let needed = current.isEmpty ? height : used + Self.unitSpacing + height
                if needed > available && !current.isEmpty {
                    pages.append(current)
                    current = [unit]
                    used = height
                } else {
                    current.append(unit)
                    used = needed
                }
            }
            if !current.isEmpty { pages.append(current) }
            return pages.isEmpty ? [[.header]] : pages
        }
    }
}

private struct PaginationKey: Hashable {
    let chapterID: String
    let width: CGFloat
    let height: CGFloat
    let textSize: Double
    let showNumbers: Bool
    let dynamicType: DynamicTypeSize
    let noteVerses: [Int]
    let isRead: Bool
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
