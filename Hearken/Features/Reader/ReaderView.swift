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
    @AppStorage(SettingsKey.scriptureTextSize) private var textSize: Double = 20
    @AppStorage(SettingsKey.pencilHighlighting) private var pencilHighlighting = false

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
                        Section("Text Size · \(Int(textSize)) pt") {
                            // Menus can't hold sliders, so this is the system's in-menu stepper:
                            // two buttons side by side that leave the menu open between taps.
                            ControlGroup {
                                Button("Smaller", systemImage: "textformat.size.smaller") {
                                    textSize = max(15, textSize - 1)
                                }
                                .disabled(textSize <= 15)
                                Button("Larger", systemImage: "textformat.size.larger") {
                                    textSize = min(28, textSize + 1)
                                }
                                .disabled(textSize >= 28)
                            }
                            .menuActionDismissBehavior(.disabled)
                        }
                        Picker("Layout", systemImage: layout.symbol, selection: $layout) {
                            ForEach(ReaderLayout.allCases) { option in
                                Label(option.title, systemImage: option.symbol).tag(option)
                            }
                        }
                        if UIDevice.isPad {
                            Section {
                                // Menus show toggles as a checkmark item.
                                Toggle(isOn: $pencilHighlighting) {
                                    Text("Pencil Highlighting")
                                    Text("Draw over text to highlight")
                                }
                            }
                        }
                    } label: {
                        Label("Reader Options", systemImage: "ellipsis")
                    }
                    .tint(Color.primary)
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

/// Reads one chapter as selectable text. Long-press a verse to select it, then drag the
/// handles to any run of words; the highlight toolbar floats beside the selection.
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
    @AppStorage(SettingsKey.accent) private var accent: AccentOption = .blue
    @AppStorage(SettingsKey.pencilHighlighting) private var pencilHighlighting = false
    @AppStorage(SettingsKey.pencilHue) private var pencilHue: HighlightHue = .yellow
    @AppStorage(SettingsKey.pencilStyle) private var pencilStyle: HighlightStyle = .fill
    @ScaledMetric(relativeTo: .body) private var bodyMetric: CGFloat = 17

    @State private var selection: VerseSelection?
    @State private var clearToken = 0
    @State private var isAdjustingSelection = false
    @State private var pencilErasing = false
    @State private var recentStroke: RecentStroke?
    @State private var pendingStyle: HighlightStyle?
    @State private var noteTarget: NoteTarget?
    @State private var showSignInPrompt = false
    @State private var pageCache = PageCache()
    /// Where each text view sits on screen (keyed by its first verse), and the bottom of the
    /// reader's visible area. Used to float the toolbar above a selection near the bottom.
    @State private var textFrames: [Int: CGRect] = [:]
    @State private var visibleBottom: CGFloat = .infinity

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
                    VStack(alignment: .leading, spacing: 4) {
                        header(chapter)
                        chapterText(textLayout(chapter.verses, interactive: true))
                        footer
                    }
                    .padding(.horizontal, 24)
                    // Room to scroll the last lines above the Pencil palette.
                    .padding(.bottom, pencilOn ? 160 : 40)
                }
                // Scrolling away from a selection dismisses it, like Books.
                .onScrollPhaseChange { _, phase in
                    if phase == .interacting, selection != nil { closeSelection() }
                }
            } else {
                ContentUnavailableView(
                    "Not Imported Yet",
                    systemImage: "book.closed",
                    description: Text("This chapter's text arrives with the full scripture import.")
                )
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { visibleBottom = $0 }
        .animation(.snappy(duration: 0.25), value: selection)
        .animation(.easeOut(duration: 0.15), value: isAdjustingSelection)
        .overlay(alignment: .bottom) { pencilOverlay }
        .animation(.snappy, value: pencilOn)
        .animation(.snappy, value: UIDevice.isPad ? selection?.start : nil)
        .animation(.snappy, value: recentStroke?.id)
        .task(id: recentStroke?.id) {
            // The after-stroke pill steps aside on its own.
            guard recentStroke != nil else { return }
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { recentStroke = nil }
        }
        .sensoryFeedback(.selection, trigger: selection?.start)
        .onChange(of: selection?.start) { _, start in
            guard let start, let progress else { return }
            progress.lastVerse = start.verse
            progress.updatedAt = .now
        }
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

    // MARK: Text

    fileprivate func textLayout(_ verses: [Verse], interactive: Bool) -> ChapterTextLayout {
        ChapterTextLayout(
            verses: verses,
            fontSize: fontSize,
            showNumbers: showVerseNumbers,
            tint: UIColor(accent.color),
            highlights: interactive ? highlights : [],
            noteVerses: interactive ? Set(notes.map(\.verse)) : []
        )
    }

    /// Verses as one selectable text view, with the toolbar floating beside any selection in it.
    /// In Page Turn, `pageRange` is this page's slice of the chapter's flowing text.
    fileprivate func chapterText(
        _ built: ChapterTextLayout,
        interactive: Bool = true,
        owner: Int = 0,
        pageRange: NSRange? = nil
    ) -> some View {
        ChapterTextView(
            layout: built,
            interactive: interactive,
            owner: owner,
            pageRange: pageRange,
            selection: $selection,
            isAdjusting: $isAdjustingSelection,
            clearToken: clearToken,
            onOpenNote: openExistingNote,
            pencil: interactive ? pencilConfig : PencilConfig(),
            onPencilStroke: pencilStroke
        )
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            if interactive { textFrames[owner] = frame }
        }
        .overlay(alignment: .topLeading) {
            // Hidden while a handle is being dragged, so the text stays visible; back on release.
            // iPhone: the toolbar floats by the selection. iPad uses the bar at the bottom instead.
            if !UIDevice.isPad, interactive, !isAdjustingSelection, let selection, selection.owner == owner {
                floatingToolbar(for: selection)
            }
        }
        .accessibilityHint(interactive ? "Touch and hold a verse to select it for highlighting." : "")
    }

    /// About how tall the toolbar is, plus a margin, for deciding which side of the selection it fits.
    private static let toolbarClearance: CGFloat = 230
    /// Gap between the selection and the toolbar, enough to keep the selection handles' grab
    /// knobs (which sit just past the first and last lines) uncovered and easy to drag.
    private static let handleClearance: CGFloat = 24

    /// Below the selection when there's room before the bottom of the reader (above the tab bar),
    /// otherwise above it.
    private func placesToolbarBelow(_ selection: VerseSelection) -> Bool {
        guard let frame = textFrames[selection.owner] else { return selection.placeBelow }
        return frame.minY + selection.rect.maxY + Self.toolbarClearance <= visibleBottom
    }

    /// The highlight toolbar, just below the selection, or just above it near the bottom of the screen.
    @ViewBuilder
    private func floatingToolbar(for selection: VerseSelection) -> some View {
        let below = placesToolbarBelow(selection)
        toolbar(for: selection)
            .padding(.horizontal, -20)
            .alignmentGuide(VerticalAlignment.top) { dimensions in
                below ? dimensions[.top] : dimensions[.bottom]
            }
            .offset(y: below ? selection.rect.maxY + Self.handleClearance : selection.rect.minY - Self.handleClearance)
            .transition(.scale(scale: 0.94, anchor: below ? .top : .bottom).combined(with: .opacity))
            .zIndex(1)
    }

    // MARK: Apple Pencil (iPad)

    private struct RecentStroke: Identifiable {
        let id = UUID()
        let highlight: Highlight
    }

    private var pencilOn: Bool { UIDevice.isPad && pencilHighlighting }

    private var pencilConfig: PencilConfig {
        PencilConfig(enabled: pencilOn, color: UIColor(pencilHue.color), style: pencilStyle, erasing: pencilErasing)
    }

    @ViewBuilder
    private var pencilOverlay: some View {
        if UIDevice.isPad, let selection, !isAdjustingSelection {
            iPadSelectionBar(for: selection)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if pencilOn {
            VStack(spacing: 12) {
                if let stroke = recentStroke {
                    PencilStrokePill(
                        hue: stroke.highlight.hue,
                        name: legend.name(for: stroke.highlight.hue),
                        reference: reference(from: stroke.highlight.start, to: stroke.highlight.end),
                        onNote: {
                            recentStroke = nil
                            openNote(verse: stroke.highlight.startVerse)
                        },
                        onRemove: {
                            // Clears all highlighting under the stroke, including older highlights there.
                            let start = stroke.highlight.start, end = stroke.highlight.end
                            recentStroke = nil
                            carve(from: start, to: end)
                        },
                        onUndo: {
                            modelContext.delete(stroke.highlight)
                            recentStroke = nil
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                PencilPalette(
                    entries: legend.entries,
                    name: legend.name(for:),
                    hue: $pencilHue,
                    style: $pencilStyle,
                    erasing: $pencilErasing,
                    onDone: {
                        pencilHighlighting = false
                        pencilErasing = false
                        recentStroke = nil
                    }
                )
            }
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func iPadSelectionBar(for selection: VerseSelection) -> some View {
        let existing = existingHighlight(for: selection)
        return IPadSelectionBar(
            reference: reference(for: selection),
            entries: legend.entries,
            name: legend.name(for:),
            selectedHue: existing?.hue,
            style: existing?.style ?? pendingStyle ?? legend.defaultStyle,
            onPick: { hue in pick(hue, selection: selection, existing: existing) },
            onStyle: { style in setStyle(style, existing: existing) },
            onNote: { openNote(verse: selection.start.verse) },
            onCopy: { copy(selection) },
            onRemove: {
                removeHighlights(in: selection)
                closeSelection()
            },
            onClose: closeSelection
        )
    }

    private func reference(from start: VersePosition, to end: VersePosition) -> String {
        let base = content.reference(chapterID: chapterID, verse: start.verse)
        return end.verse > start.verse ? "\(base)–\(end.verse)" : base
    }

    /// A finished Pencil stroke: add a highlight in the palette's color and style, or erase.
    private func pencilStroke(start: VersePosition, end: VersePosition) {
        let start = normalized(start), end = normalized(end)
        if pencilErasing {
            // Drop the after-stroke pill first, so it never reads a deleted highlight.
            recentStroke = nil
            carve(from: start, to: end)
            return
        }
        guard requireSignIn() else { return }
        carve(from: start, to: end)
        let highlight = Highlight(chapterID: chapterID, start: start, end: end, hue: pencilHue, style: pencilStyle)
        modelContext.insert(highlight)
        recentStroke = RecentStroke(highlight: highlight)
    }

    // MARK: Pieces

    fileprivate func header(_ chapter: Chapter) -> some View {
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

    fileprivate var footer: some View {
        footerView(isRead: progress?.completedAt != nil, markRead: markRead)
    }

    fileprivate func footerView(isRead: Bool, markRead: @escaping () -> Void) -> some View {
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

    private func reference(for selection: VerseSelection) -> String {
        let base = content.reference(chapterID: chapterID, verse: selection.start.verse)
        return selection.end.verse > selection.start.verse ? "\(base)–\(selection.end.verse)" : base
    }

    /// The highlight the toolbar edits: the one covering exactly the selection (tap a highlight to
    /// select all of it). Any other selection is new text, so a color applied to part of a
    /// highlight becomes its own highlight.
    private func existingHighlight(for selection: VerseSelection) -> Highlight? {
        highlights.first { normalized($0.start) == normalized(selection.start) && normalized($0.end) == normalized(selection.end) }
    }

    private func isWholeVerse(_ selection: VerseSelection) -> Bool {
        selection.start.verse == selection.end.verse && selection.start.offset == 0 && selection.end.offset < 0
    }

    /// Treats "offset at the end of the verse" and -1 as the same position.
    private func normalized(_ position: VersePosition) -> VersePosition {
        guard let verse = chapter?.verses.first(where: { $0.number == position.verse }) else { return position }
        return position.offset >= verse.text.utf16.count ? VersePosition(verse: position.verse, offset: -1) : position
    }

    private func toolbar(for selection: VerseSelection) -> some View {
        let existing = existingHighlight(for: selection)
        return HighlightToolbar(
            reference: reference(for: selection),
            entries: legend.entries,
            name: legend.name(for:),
            showNames: legend.showNames,
            selectedHue: existing?.hue,
            style: existing?.style ?? pendingStyle ?? legend.defaultStyle,
            onPick: { hue in pick(hue, selection: selection, existing: existing) },
            onStyle: { style in setStyle(style, existing: existing) },
            onNote: { openNote(verse: selection.start.verse) },
            onCopy: { copy(selection) },
            onRemove: { removeHighlights(in: selection) },
            onClose: closeSelection
        )
    }

    // MARK: Actions

    private func requireSignIn() -> Bool {
        if account.isSignedIn { return true }
        showSignInPrompt = true
        return false
    }

    private func pick(_ hue: HighlightHue, selection: VerseSelection, existing: Highlight?) {
        guard requireSignIn() else { return }
        if let existing {
            existing.hue = hue
        } else {
            let start = normalized(selection.start), end = normalized(selection.end)
            // Recoloring part of a highlight makes that part its own highlight.
            carve(from: start, to: end)
            modelContext.insert(Highlight(
                chapterID: chapterID,
                start: start,
                end: end,
                hue: hue,
                style: pendingStyle ?? legend.defaultStyle
            ))
        }
    }

    private func setStyle(_ style: HighlightStyle, existing: Highlight?) {
        pendingStyle = style
        existing?.style = style
    }

    /// Removes highlighting from just the selected text; highlight outside it stays.
    private func removeHighlights(in selection: VerseSelection) {
        carve(from: normalized(selection.start), to: normalized(selection.end))
    }

    /// Cuts the range out of every highlight it overlaps. Parts of a highlight before and after
    /// the range are kept as their own highlights, in the same color and style.
    private func carve(from start: VersePosition, to end: VersePosition) {
        for highlight in highlights where highlight.start < end && start < highlight.end {
            if highlight.start < start {
                modelContext.insert(Highlight(chapterID: chapterID, start: highlight.start, end: start, hue: highlight.hue, style: highlight.style))
            }
            if end < highlight.end {
                // A cut ending at the end of a verse resumes at the start of the next one.
                let resume = end.offset < 0 ? VersePosition(verse: end.verse + 1, offset: 0) : end
                if resume < highlight.end {
                    modelContext.insert(Highlight(chapterID: chapterID, start: resume, end: highlight.end, hue: highlight.hue, style: highlight.style))
                }
            }
            if recentStroke?.highlight === highlight { recentStroke = nil }
            modelContext.delete(highlight)
        }
    }

    private func openNote(verse number: Int) {
        guard requireSignIn(), let verse = chapter?.verses.first(where: { $0.number == number }) else { return }
        closeSelection()
        noteTarget = NoteTarget(verse: verse)
    }

    private func openExistingNote(_ number: Int) {
        guard let verse = chapter?.verses.first(where: { $0.number == number }) else { return }
        noteTarget = NoteTarget(verse: verse)
    }

    private func copy(_ selection: VerseSelection) {
        UIPasteboard.general.string = "\u{201C}\(selection.text)\u{201D} (\(reference(for: selection)))"
    }

    private func closeSelection() {
        selection = nil
        clearToken += 1
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

/// A chapter laid out as pages. The text is flowed through page-sized TextKit containers to
/// find where each page breaks (always between lines, never at verse boundaries), then each
/// page shows its slice of the text. The chapter heading takes the top of the first page; the
/// "Mark as Read" footer follows the text, on its own page if the last one is full.
final class PagedChapterText {
    let pageRanges: [NSRange]
    let footerOnOwnPage: Bool

    init(layout: ChapterTextLayout, width: CGFloat, firstPageHeight: CGFloat, pageHeight: CGFloat, footerHeight: CGFloat) {
        let storage = NSTextStorage(attributedString: layout.attributed)
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)

        var ranges: [NSRange] = []
        var lastUsedHeight: CGFloat = 0
        var lastHeight: CGFloat = pageHeight
        repeat {
            let height = ranges.isEmpty ? max(firstPageHeight, 80) : pageHeight
            let container = NSTextContainer(size: CGSize(width: max(width, 50), height: height))
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)
            let glyphs = layoutManager.glyphRange(for: container)
            ranges.append(layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil))
            lastUsedHeight = layoutManager.usedRect(for: container).height
            lastHeight = height
            if glyphs.length == 0 && layoutManager.numberOfGlyphs > 0 && ranges.count > 1 { break }
        } while NSMaxRange(ranges[ranges.count - 1]) < storage.length && ranges.count < 500

        pageRanges = ranges
        footerOnOwnPage = lastUsedHeight + footerHeight + 8 > lastHeight
    }

    var pageCount: Int { pageRanges.count + (footerOnOwnPage ? 1 : 0) }
}

/// Remembers paginations so pages aren't re-laid out on every render.
final class PageCache {
    private var entries: [AnyHashable: PagedChapterText] = [:]
    private lazy var sizer = UIHostingController(rootView: AnyView(EmptyView()))

    func pages(for key: AnyHashable, build: (UIHostingController<AnyView>) -> PagedChapterText) -> PagedChapterText {
        if let pages = entries[key] { return pages }
        let pages = build(sizer)
        if entries.count > 8 { entries.removeAll() }
        entries[key] = pages
        return pages
    }
}

extension ReaderPage {
    private static let pageTopPadding: CGFloat = 12
    private static let pageFooterHeight: CGFloat = 40
    private static let headerSpacing: CGFloat = 4

    func pagedBody(_ chapter: Chapter) -> some View {
        GeometryReader { geo in
            let built = textLayout(chapter.verses, interactive: true)
            let paged = pagination(for: chapter, layout: built, size: geo.size, interactive: true)
            let previousID = LibraryCatalog.adjacentChapter(to: chapterID, offset: -1)
            let nextID = LibraryCatalog.adjacentChapter(to: chapterID, offset: 1)

            PageCurlView(
                pageCount: paged.pageCount,
                startPage: startsAtEnd ? paged.pageCount - 1 : 0,
                curl: !reduceMotion,
                environment: environment,
                page: { index in
                    AnyView(pageView(index, paged: paged, layout: built, chapter: chapter, interactive: true))
                },
                previousChapterPage: previousID.flatMap { neighborPage($0, last: true, size: geo.size) },
                nextChapterPage: nextID.flatMap { neighborPage($0, last: false, size: geo.size) },
                onTurnStart: { if selection != nil { closeSelection() } },
                onLeaveChapter: { forward in
                    selection = nil
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
        let built = textLayout(neighbor.verses, interactive: false)
        let paged = pagination(for: neighbor, layout: built, size: size, interactive: false)
        let index = last ? paged.pageCount - 1 : 0
        return AnyView(pageView(index, paged: paged, layout: built, chapter: neighbor, interactive: false))
    }

    private func pageView(_ index: Int, paged: PagedChapterText, layout built: ChapterTextLayout, chapter: Chapter, interactive: Bool) -> some View {
        let pageRange = index < paged.pageRanges.count ? paged.pageRanges[index] : nil
        let isLastTextPage = index == paged.pageRanges.count - 1
        return VStack(alignment: .leading, spacing: Self.headerSpacing) {
            if index == 0 {
                header(chapter)
            }
            if let pageRange {
                chapterText(built, interactive: interactive, owner: index, pageRange: pageRange)
            }
            if pageRange == nil || (isLastTextPage && !paged.footerOnOwnPage) {
                if interactive { footer } else { footerView(isRead: false, markRead: {}) }
            }
            Spacer(minLength: 0)
            Text("\(index + 1) of \(paged.pageCount)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: Self.pageFooterHeight - 8)
                .accessibilityLabel("Page \(index + 1) of \(paged.pageCount)")
        }
        .padding(.horizontal, 24)
        .padding(.top, Self.pageTopPadding)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemBackground))
    }

    /// Lays the chapter out into page-sized containers.
    private func pagination(for chapter: Chapter, layout built: ChapterTextLayout, size: CGSize, interactive: Bool) -> PagedChapterText {
        let key = PaginationKey(
            chapterID: chapter.id, width: size.width, height: size.height, textSize: textSize,
            showNumbers: showVerseNumbers, dynamicType: environment.dynamicTypeSize,
            noteVerses: interactive ? notes.map(\.verse).sorted() : [],
            isRead: interactive && progress?.completedAt != nil,
            interactive: interactive
        )
        return pageCache.pages(for: key) { sizer in
            let width = size.width - 48
            let pageHeight = size.height - Self.pageTopPadding - Self.pageFooterHeight - 8

            func measure(_ view: some View) -> CGFloat {
                sizer.rootView = AnyView(view.environment(\.self, environment))
                return sizer.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
            }
            let headerHeight = measure(header(chapter)) + Self.headerSpacing
            let footerHeight = interactive ? measure(footer) : measure(footerView(isRead: false, markRead: {}))

            return PagedChapterText(
                layout: built,
                width: width,
                firstPageHeight: pageHeight - headerHeight,
                pageHeight: pageHeight,
                footerHeight: footerHeight
            )
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
    let interactive: Bool
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
