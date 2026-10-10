import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

// The reader's text engine. A chapter (or a page's worth of verses) is one UITextView, so
// people can select any run of text with the system's own selection handles. Highlights are
// stored as verse + offset positions and drawn as attributes on that text.

/// A point in a chapter: a verse and a UTF-16 offset into that verse's text.
struct VersePosition: Hashable, Comparable {
    var verse: Int
    /// UTF-16 offset into the verse text; -1 means the end of the verse.
    var offset: Int

    private var sortOffset: Int { offset < 0 ? Int.max : offset }

    static func < (lhs: VersePosition, rhs: VersePosition) -> Bool {
        (lhs.verse, lhs.sortOffset) < (rhs.verse, rhs.sortOffset)
    }
}

/// What the reader has selected, in verse terms, plus where to float the toolbar.
struct VerseSelection: Equatable {
    var start: VersePosition
    var end: VersePosition
    var text: String
    /// Selection bounds in the owning text view's coordinates.
    var rect: CGRect
    /// True when there's room for the toolbar below the selection on screen.
    var placeBelow: Bool
    /// Which text view owns the selection: 0 in Scroll, the page index in Page Turn.
    var owner: Int
}

/// Builds the attributed text for a run of verses and maps between characters and verses.
struct ChapterTextLayout {
    struct Span {
        let verse: Int
        /// The verse's own text (excluding its number and note button).
        let text: NSRange
        /// The whole paragraph, including the number and trailing newline.
        let paragraph: NSRange
    }

    let attributed: NSAttributedString
    let spans: [Span]
    /// Each highlight's full extent, start to end (including verse numbers between), so a tap
    /// anywhere on it can select the whole thing. Later highlights come last.
    let highlightRuns: [NSRange]
    let firstVerse: Int
    /// Changes whenever anything drawn changes; used to skip redundant updates.
    let signature: Int

    init(
        verses: [Verse],
        fontSize: CGFloat,
        showNumbers: Bool,
        tint: UIColor,
        highlights: [Highlight],
        noteVerses: Set<Int>,
        bookmarkVerses: Set<Int> = [],
        groupVerses: Set<Int> = [],
        speakingVerse: Int? = nil
    ) {
        let bodyFont = Self.serifFont(size: fontSize)
        let numberFont = UIFont.systemFont(ofSize: fontSize * 0.6, weight: .semibold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = fontSize * 0.35
        paragraph.paragraphSpacing = fontSize * 0.6

        let text = NSMutableAttributedString()
        var spans: [Span] = []
        for (index, verse) in verses.enumerated() {
            let paragraphStart = text.length
            if bookmarkVerses.contains(verse.number) {
                // A tappable bookmark ribbon before the verse; tap it to edit the bookmark.
                let symbol = UIImage(
                    systemName: "bookmark.fill",
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: fontSize * 0.62, weight: .semibold)
                )?.withTintColor(tint, renderingMode: .alwaysOriginal)
                if let symbol {
                    let attachment = NSTextAttachment(image: symbol)
                    attachment.bounds = CGRect(x: 0, y: fontSize * 0.02, width: symbol.size.width, height: symbol.size.height)
                    let ribbon = NSMutableAttributedString(attachment: attachment)
                    ribbon.append(NSAttributedString(string: "\u{2009}", attributes: [.font: numberFont]))
                    ribbon.addAttribute(.link, value: URL(string: "hearken-bookmark://\(verse.number)")!, range: NSRange(location: 0, length: ribbon.length))
                    text.append(ribbon)
                }
            }
            if showNumbers {
                text.append(NSAttributedString(string: "\(verse.number)\u{2009}", attributes: [
                    .font: numberFont,
                    .foregroundColor: tint,
                    .baselineOffset: fontSize * 0.3,
                ]))
            }
            let textStart = text.length
            text.append(NSAttributedString(string: verse.text, attributes: [
                .font: bodyFont,
                .foregroundColor: UIColor.label,
            ]))
            let textRange = NSRange(location: textStart, length: text.length - textStart)

            if noteVerses.contains(verse.number) {
                // A tappable note button at the end of the verse.
                let symbol = UIImage(
                    systemName: "note.text",
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: fontSize * 0.8, weight: .medium)
                )?.withTintColor(tint, renderingMode: .alwaysOriginal)
                if let symbol {
                    let attachment = NSTextAttachment(image: symbol)
                    attachment.bounds = CGRect(x: 0, y: -fontSize * 0.12, width: symbol.size.width, height: symbol.size.height)
                    let button = NSMutableAttributedString(string: "\u{2009}")
                    button.append(NSAttributedString(attachment: attachment))
                    button.addAttribute(.link, value: URL(string: "hearken-note://\(verse.number)")!, range: NSRange(location: 0, length: button.length))
                    text.append(button)
                }
            }
            if groupVerses.contains(verse.number) {
                // Someone in a study group shared this verse; tap to see what they shared.
                let symbol = UIImage(
                    systemName: "person.2.fill",
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: fontSize * 0.7, weight: .medium)
                )?.withTintColor(tint, renderingMode: .alwaysOriginal)
                if let symbol {
                    let attachment = NSTextAttachment(image: symbol)
                    attachment.bounds = CGRect(x: 0, y: -fontSize * 0.08, width: symbol.size.width, height: symbol.size.height)
                    let button = NSMutableAttributedString(string: "\u{2009}")
                    button.append(NSAttributedString(attachment: attachment))
                    button.addAttribute(.link, value: URL(string: "hearken-group://\(verse.number)")!, range: NSRange(location: 0, length: button.length))
                    text.append(button)
                }
            }
            if index < verses.count - 1 {
                text.append(NSAttributedString(string: "\n", attributes: [.font: bodyFont]))
            }
            spans.append(Span(verse: verse.number, text: textRange, paragraph: NSRange(location: paragraphStart, length: text.length - paragraphStart)))
        }
        text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))

        self.spans = spans
        self.firstVerse = verses.first?.number ?? 0

        // Highlights, applied to verse text only (never to verse numbers).
        var runs: [NSRange] = []
        var signature = Hasher()
        signature.combine(verses.map(\.id))
        signature.combine(fontSize)
        signature.combine(showNumbers)
        signature.combine(tint.hashValue)
        signature.combine(noteVerses.sorted())
        signature.combine(bookmarkVerses.sorted())
        signature.combine(groupVerses.sorted())
        signature.combine(speakingVerse)
        // Listen mode: a soft wash of the accent behind the verse being read aloud.
        if let speakingVerse, let span = spans.first(where: { $0.verse == speakingVerse }) {
            text.addAttribute(.backgroundColor, value: tint.withAlphaComponent(0.16), range: span.text)
        }
        for highlight in highlights.sorted(by: { $0.createdAt < $1.createdAt }) {
            signature.combine(highlight.startVerse); signature.combine(highlight.startOffset)
            signature.combine(highlight.endVerse); signature.combine(highlight.endOffset)
            signature.combine(highlight.hueRaw); signature.combine(highlight.styleRaw)
            let color = UIColor(highlight.hue.color)
            if let first = spans.first(where: { $0.verse == highlight.startVerse }),
               let last = spans.first(where: { $0.verse == highlight.endVerse }) {
                let lower = first.text.location + min(max(highlight.startOffset, 0), first.text.length)
                let upper = last.text.location + (highlight.endOffset < 0 ? last.text.length : min(highlight.endOffset, last.text.length))
                if upper > lower { runs.append(NSRange(location: lower, length: upper - lower)) }
            }
            for span in spans where span.verse >= highlight.startVerse && span.verse <= highlight.endVerse {
                let lower = span.verse == highlight.startVerse ? min(max(highlight.startOffset, 0), span.text.length) : 0
                let upper = span.verse == highlight.endVerse && highlight.endOffset >= 0
                    ? min(highlight.endOffset, span.text.length) : span.text.length
                guard upper > lower else { continue }
                let range = NSRange(location: span.text.location + lower, length: upper - lower)
                switch highlight.style {
                case .fill:
                    text.addAttribute(.backgroundColor, value: color.withAlphaComponent(0.32), range: range)
                case .underline:
                    text.addAttributes([.underlineStyle: NSUnderlineStyle.thick.rawValue, .underlineColor: color], range: range)
                }
            }
        }
        self.highlightRuns = runs
        self.signature = signature.finalize()
        self.attributed = text
    }

    static func serifFont(size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    // MARK: Mapping

    func characterIndex(of position: VersePosition) -> Int? {
        guard let span = spans.first(where: { $0.verse == position.verse }) else { return nil }
        let offset = position.offset < 0 ? span.text.length : min(position.offset, span.text.length)
        return span.text.location + offset
    }

    /// The verse position for a character index. Indexes in a verse number or note button snap
    /// to the start or end of that verse's text.
    func position(at index: Int, preferEnd: Bool) -> VersePosition? {
        // At the seam between two verses, a start belongs to the next verse and an end to the previous one.
        let match = preferEnd
            ? spans.first { index > $0.paragraph.location && index <= NSMaxRange($0.paragraph) }
            : spans.first { index >= $0.paragraph.location && index < NSMaxRange($0.paragraph) }
        guard let span = match ?? (index <= 0 ? spans.first : spans.last) else { return nil }
        let offset = min(max(index - span.text.location, 0), span.text.length)
        if preferEnd && offset == span.text.length { return VersePosition(verse: span.verse, offset: -1) }
        return VersePosition(verse: span.verse, offset: offset)
    }

    func verseText(_ verse: Int) -> NSRange? {
        spans.first { $0.verse == verse }?.text
    }

    /// Height of the text at `width`, for paginating before any view exists.
    func height(forWidth width: CGFloat) -> CGFloat {
        let bounds = attributed.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return ceil(bounds.height)
    }
}

/// Apple Pencil highlighting settings for a chapter text view (iPad).
struct PencilConfig: Equatable {
    var enabled = false
    var color: UIColor = .systemYellow
    var style: HighlightStyle = .fill
    /// The eraser: strokes remove highlights instead of adding them.
    var erasing = false
}

/// A non-editable, selectable text view sized to its content (scrolling belongs to the reader).
/// Long-pressing selects the whole verse; the selection handles then trim it to any text.
/// A single tap only clears the selection.
struct ChapterTextView: UIViewRepresentable {
    let layout: ChapterTextLayout
    var interactive = true
    /// Identifies this view's selections (see VerseSelection.owner).
    var owner = 0
    /// Page Turn: the slice of the chapter's text on this page (see PagedChapterText).
    /// Nil shows all of `layout`. Selections are always reported in whole-chapter terms.
    var pageRange: NSRange? = nil
    @Binding var selection: VerseSelection?
    /// True while a finger is dragging the selection (handles or long press), so the toolbar can hide.
    @Binding var isAdjusting: Bool
    /// Bump to clear the current selection (for example when the toolbar closes).
    var clearToken: Int = 0
    var onOpenNote: (Int) -> Void = { _ in }
    /// The bookmark ribbon before a verse was tapped.
    var onOpenBookmark: (Int) -> Void = { _ in }
    /// The study-group marker after a verse was tapped.
    var onOpenGroupItems: (Int) -> Void = { _ in }
    /// Scroll layout: lets the reader find the verse at the top of the screen and scroll to one.
    var probe: ReaderProbe? = nil
    /// Pencil mode: the Pencil highlights, fingers scroll and select as usual.
    var pencil = PencilConfig()
    /// A finished Pencil stroke, in whole-chapter terms.
    var onPencilStroke: (_ start: VersePosition, _ end: VersePosition) -> Void = { _, _ in }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UITextView {
        // Pages use TextKit 1, the same engine that measured where the pages break,
        // so each page's lines match exactly.
        let textView = UITextView(usingTextLayoutManager: pageRange == nil)
        textView.isEditable = false
        textView.isSelectable = interactive
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = false
        textView.dataDetectorTypes = []
        textView.textDragInteraction?.isEnabled = false
        textView.delegate = context.coordinator
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.attributedText = displayedText
        context.coordinator.signature = layout.signature
        context.coordinator.pageRange = pageRange
        if let probe {
            probe.textView = textView
            probe.layout = layout
        }

        if interactive {
            let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPress(_:)))
            press.minimumPressDuration = 0.4
            press.delegate = context.coordinator
            textView.addGestureRecognizer(press)
            context.coordinator.press = press

            // A tap (finger or Pencil) on a highlight selects all of it, for editing or removing.
            let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tappedHighlight(_:)))
            tap.delegate = context.coordinator
            textView.addGestureRecognizer(tap)
            context.coordinator.highlightTap = tap

            context.coordinator.adoptLongPress(in: textView)
            context.coordinator.textView = textView
            context.coordinator.installPencil(on: textView)
        }
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if let probe {
            probe.textView = textView
            probe.layout = layout
        }
        // Text views add some of their selection gestures once on screen; adopt those too.
        if interactive, let window = textView.window, !coordinator.adoptedOnScreen {
            coordinator.adoptLongPress(in: textView)
            coordinator.installTouchTracker(in: window)
            coordinator.adoptedOnScreen = true
        }
        if coordinator.signature != layout.signature || coordinator.pageRange != pageRange {
            let selected = textView.selectedRange
            textView.attributedText = displayedText
            coordinator.pageRange = pageRange
            if selected.length > 0, NSMaxRange(selected) <= textView.attributedText.length {
                textView.selectedRange = selected
            }
            coordinator.signature = layout.signature
        }
        if interactive {
            let enabled = pencil.enabled
            if textView.window != nil {
                coordinator.applyPencilMode(enabled, in: textView)
            } else {
                // Not on screen yet, so the scroll view above it isn't reachable; try once it is.
                DispatchQueue.main.async { [weak textView] in
                    guard let textView else { return }
                    coordinator.applyPencilMode(enabled, in: textView)
                }
            }
        }
        if coordinator.clearToken != clearToken {
            coordinator.clearToken = clearToken
            if textView.selectedRange.length > 0 {
                textView.selectedRange = NSRange(location: 0, length: 0)
            }
        }
    }

    static func dismantleUIView(_ textView: UITextView, coordinator: Coordinator) {
        coordinator.removeTouchTracker()
        coordinator.applyPencilMode(false, in: textView)
    }

    fileprivate var displayedText: NSAttributedString {
        guard let pageRange, NSMaxRange(pageRange) <= layout.attributed.length else { return layout.attributed }
        return layout.attributed.attributedSubstring(from: pageRange)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(size.height))
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: ChapterTextView
        var signature = 0
        var clearToken = 0
        var pageRange: NSRange?
        /// Offset of this view's text within the whole chapter.
        private var base: Int { parent.pageRange?.location ?? 0 }
        var press: UILongPressGestureRecognizer?
        var highlightTap: UITapGestureRecognizer?
        var adoptedOnScreen = false

        init(parent: ChapterTextView) {
            self.parent = parent
        }

        /// The built-in long press selects a word; ours selects the verse, so theirs waits for ours.
        func adoptLongPress(in textView: UITextView) {
            guard let press else { return }
            for recognizer in textView.gestureRecognizers ?? [] where recognizer !== press && recognizer !== highlightTap {
                if recognizer is UILongPressGestureRecognizer {
                    recognizer.require(toFail: press)
                } else if let tap = recognizer as? UITapGestureRecognizer, tap.numberOfTapsRequired == 1, let highlightTap {
                    // The built-in tap (which clears the selection) waits to see if this was a highlight tap.
                    tap.require(toFail: highlightTap)
                }
            }
        }

        /// The highlight under a point, in whole-chapter character terms (the newest if they overlap).
        private func highlightRun(at point: CGPoint, in textView: UITextView) -> NSRange? {
            guard let position = textView.closestPosition(to: point) else { return nil }
            let index = textView.offset(from: textView.beginningOfDocument, to: position) + base
            return parent.layout.highlightRuns.last { index >= $0.location && index < NSMaxRange($0) }
        }

        @objc func tappedHighlight(_ tap: UITapGestureRecognizer) {
            guard let textView = tap.view as? UITextView,
                  let run = highlightRun(at: tap.location(in: textView), in: textView) else { return }
            // On a page, select the part of the highlight that's on this page.
            let visible = NSRange(location: base, length: textView.attributedText.length)
            let range = NSIntersectionRange(run, visible)
            guard range.length > 0 else { return }
            textView.becomeFirstResponder()
            textView.selectedRange = NSRange(location: range.location - base, length: range.length)
            UISelectionFeedbackGenerator().selectionChanged()
            report(textView)
        }

        // Dragging a selection handle: the handles' drag gesture doesn't tell the delegate anything
        // until it ends, so a passive touch watcher on the window notices a finger landing on a
        // handle and lifting again. The toolbar hides in between.
        weak var textView: UITextView?
        private var tracker: TouchTracker?
        private var draggingHandle = false

        func installTouchTracker(in window: UIWindow) {
            guard tracker == nil else { return }
            let tracker = TouchTracker()
            tracker.onTouch = { [weak self] phase, point in self?.touch(phase, at: point) }
            window.addGestureRecognizer(tracker)
            self.tracker = tracker
        }

        func removeTouchTracker() {
            if let tracker { tracker.view?.removeGestureRecognizer(tracker) }
            tracker = nil
        }

        private func touch(_ phase: TouchTracker.Phase, at windowPoint: CGPoint) {
            switch phase {
            case .began:
                guard let textView, textView.window != nil, textView.selectedRange.length > 0,
                      let range = textView.selectedTextRange else { return }
                let point = textView.convert(windowPoint, from: nil)
                let handles = [textView.caretRect(for: range.start), textView.caretRect(for: range.end)]
                    .map { $0.insetBy(dx: -28, dy: -28) }
                guard handles.contains(where: { $0.contains(point) }) else { return }
                draggingHandle = true
                setAdjusting(true)
            case .ended:
                guard draggingHandle else { return }
                draggingHandle = false
                setAdjusting(false)
            }
        }

        private func setAdjusting(_ value: Bool) {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.parent.isAdjusting != value else { return }
                self.parent.isAdjusting = value
            }
        }

        /// Holding a selection handle (to drag it) shouldn't reselect the whole verse.
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            if recognizer === highlightTap {
                guard let textView = recognizer.view as? UITextView else { return false }
                let point = recognizer.location(in: textView)
                // Leave taps on a note button to the button.
                if let position = textView.closestPosition(to: point) {
                    let local = textView.offset(from: textView.beginningOfDocument, to: position)
                    for index in [local - 1, local] where index >= 0 && index < textView.attributedText.length {
                        if textView.attributedText.attribute(.link, at: index, effectiveRange: nil) != nil { return false }
                    }
                }
                return highlightRun(at: point, in: textView) != nil
            }
            guard let textView = recognizer.view as? UITextView,
                  textView.selectedRange.length > 0,
                  let range = textView.selectedTextRange else { return true }
            let point = recognizer.location(in: textView)
            let handles = [textView.caretRect(for: range.start), textView.caretRect(for: range.end)]
                .map { $0.insetBy(dx: -32, dy: -32) }
            return !handles.contains { $0.contains(point) }
        }

        @objc func longPress(_ press: UILongPressGestureRecognizer) {
            guard press.state == .began, let textView = press.view as? UITextView else { return }
            let point = press.location(in: textView)
            guard let position = textView.closestPosition(to: point) else { return }
            let index = textView.offset(from: textView.beginningOfDocument, to: position) + base
            guard let verse = parent.layout.position(at: index, preferEnd: false)?.verse,
                  let verseRange = parent.layout.verseText(verse) else { return }
            // On a page, select only the part of the verse that's on this page.
            let visible = NSRange(location: base, length: textView.attributedText.length)
            let range = NSIntersectionRange(verseRange, visible)
            guard range.length > 0 else { return }
            textView.becomeFirstResponder()
            textView.selectedRange = NSRange(location: range.location - base, length: range.length)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            report(textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            report(textView)
        }

        private func report(_ textView: UITextView) {
            let range = textView.selectedRange
            let layout = parent.layout
            let next: VerseSelection?
            if range.length == 0 {
                next = nil
            } else if let start = layout.position(at: range.location + base, preferEnd: false),
                      let end = layout.position(at: NSMaxRange(range) + base, preferEnd: true),
                      let textRange = textView.selectedTextRange {
                let rects = textView.selectionRects(for: textRange).map(\.rect).filter { !$0.isEmpty }
                let bounds = rects.dropFirst().reduce(rects.first ?? textView.firstRect(for: textRange)) { $0.union($1) }
                let inWindow = textView.convert(bounds, to: nil)
                let screenHeight = textView.window?.bounds.height ?? UIScreen.main.bounds.height
                let text = (textView.attributedText.string as NSString).substring(with: range)
                next = VerseSelection(
                    start: start,
                    end: end,
                    text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                    rect: bounds,
                    placeBelow: screenHeight - inWindow.maxY > 300,
                    owner: parent.owner
                )
            } else {
                next = nil
            }
            // Publish after the current update pass so SwiftUI isn't modified mid-render.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.parent.selection != next else { return }
                if next == nil, self.parent.selection?.owner != self.parent.owner { return }
                self.parent.selection = next
            }
        }

        // MARK: Apple Pencil

        private var pencilPan: UIPanGestureRecognizer?
        private var pencilHover: UIHoverGestureRecognizer?
        private var pencilOn = false
        private var claimed: [UIGestureRecognizer] = []
        private var anchor: Int?
        private var preview: NSRange?
        private var caret: UIView?
        private var halo: UIView?

        func installPencil(on textView: UITextView) {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(pencilDrag(_:)))
            pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
            pan.maximumNumberOfTouches = 1
            pan.isEnabled = false
            textView.addGestureRecognizer(pan)
            pencilPan = pan

            let hover = UIHoverGestureRecognizer(target: self, action: #selector(pencilHovered(_:)))
            hover.isEnabled = false
            textView.addGestureRecognizer(hover)
            pencilHover = hover
        }

        /// Turns Pencil mode on or off. While on, every other gesture on the way up to the window
        /// (scrolling, page turns, text selection, long press) accepts fingers only, so the Pencil
        /// draws highlights instead of scrolling or selecting.
        func applyPencilMode(_ on: Bool, in textView: UITextView) {
            pencilPan?.isEnabled = on
            pencilHover?.isEnabled = on
            guard on != pencilOn else { return }
            pencilOn = on
            if on {
                var views: [UIView] = [textView]
                var next = textView.superview
                while let view = next { views.append(view); next = view.superview }
                for view in views {
                    for recognizer in view.gestureRecognizers ?? []
                    where recognizer !== pencilPan && recognizer !== pencilHover && recognizer !== highlightTap
                        && !(recognizer is TouchTracker) {
                        PencilTouchRouting.claim(recognizer)
                        claimed.append(recognizer)
                    }
                }
            } else {
                claimed.forEach(PencilTouchRouting.release)
                claimed.removeAll()
                hideCaret()
                clearPreview(in: textView)
            }
        }

        @objc func pencilDrag(_ pan: UIPanGestureRecognizer) {
            guard let textView = pan.view as? UITextView,
                  let position = textView.closestPosition(to: pan.location(in: textView)) else { return }
            let index = textView.offset(from: textView.beginningOfDocument, to: position)
            switch pan.state {
            case .began:
                anchor = index
                hideCaret()
                updatePreview(in: textView, to: index)
            case .changed:
                updatePreview(in: textView, to: index)
            case .ended:
                commitStroke(in: textView)
            default:
                clearPreview(in: textView)
                anchor = nil
            }
        }

        /// The words from where the stroke started to where the tip is now, whole words only.
        private func strokeRange(to index: Int, in text: NSString) -> NSRange? {
            guard let anchor else { return nil }
            var lower = max(0, min(anchor, index))
            var upper = min(text.length, max(anchor, index))
            while lower > 0, Self.isWordCharacter(text.character(at: lower - 1)) { lower -= 1 }
            while upper < text.length, Self.isWordCharacter(text.character(at: upper)) { upper += 1 }
            // Don't start or end on spaces or line breaks.
            while lower < upper, Self.isSpace(text.character(at: lower)) { lower += 1 }
            while upper > lower, Self.isSpace(text.character(at: upper - 1)) { upper -= 1 }
            return upper > lower ? NSRange(location: lower, length: upper - lower) : nil
        }

        private static func isWordCharacter(_ character: unichar) -> Bool {
            guard let scalar = Unicode.Scalar(character) else { return false }
            return CharacterSet.alphanumerics.contains(scalar) || character == 0x27 || character == 0x2019
        }

        private static func isSpace(_ character: unichar) -> Bool {
            guard let scalar = Unicode.Scalar(character) else { return false }
            return CharacterSet.whitespacesAndNewlines.contains(scalar)
        }

        private func updatePreview(in textView: UITextView, to index: Int) {
            let storage = textView.textStorage
            let range = strokeRange(to: index, in: storage.string as NSString)
            guard range != preview else { return }
            storage.beginEditing()
            if let old = preview { restore(old, in: storage) }
            if let range {
                let pencil = parent.pencil
                if pencil.erasing {
                    storage.addAttribute(.backgroundColor, value: UIColor.systemGray.withAlphaComponent(0.25), range: range)
                } else if pencil.style == .underline {
                    storage.addAttributes([.underlineStyle: NSUnderlineStyle.thick.rawValue, .underlineColor: pencil.color], range: range)
                } else {
                    storage.addAttribute(.backgroundColor, value: pencil.color.withAlphaComponent(0.32), range: range)
                }
            }
            storage.endEditing()
            preview = range
        }

        /// Puts the original attributes back over a previewed range.
        private func restore(_ range: NSRange, in storage: NSTextStorage) {
            let original = parent.displayedText
            guard NSMaxRange(range) <= original.length, NSMaxRange(range) <= storage.length else { return }
            original.enumerateAttributes(in: range) { attributes, subrange, _ in
                storage.setAttributes(attributes, range: subrange)
            }
        }

        private func clearPreview(in textView: UITextView) {
            guard let range = preview else { return }
            textView.textStorage.beginEditing()
            restore(range, in: textView.textStorage)
            textView.textStorage.endEditing()
            preview = nil
        }

        private func commitStroke(in textView: UITextView) {
            defer { anchor = nil }
            guard let range = preview,
                  let start = parent.layout.position(at: range.location + base, preferEnd: false),
                  let end = parent.layout.position(at: NSMaxRange(range) + base, preferEnd: true) else {
                clearPreview(in: textView)
                return
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            let before = signature
            parent.onPencilStroke(start, end)
            // The saved highlight redraws the text. If nothing was saved (for example, not signed in),
            // take the preview back off.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self, weak textView] in
                guard let self, let textView else { return }
                if self.signature == before {
                    self.clearPreview(in: textView)
                } else {
                    self.preview = nil
                }
            }
        }

        // Hover: a caret in the current color where the highlight would start.

        @objc func pencilHovered(_ hover: UIHoverGestureRecognizer) {
            guard let textView = hover.view as? UITextView else { return }
            switch hover.state {
            case .began, .changed:
                // Only the Pencil reports a height above the screen; a trackpad pointer is at zero.
                guard hover.zOffset > 0,
                      let position = textView.closestPosition(to: hover.location(in: textView)) else {
                    hideCaret()
                    return
                }
                let text = textView.textStorage.string as NSString
                var index = textView.offset(from: textView.beginningOfDocument, to: position)
                while index > 0, index <= text.length, Self.isWordCharacter(text.character(at: index - 1)) { index -= 1 }
                guard let snapped = textView.position(from: textView.beginningOfDocument, offset: index) else { return }
                showCaret(at: textView.caretRect(for: snapped), in: textView)
            default:
                hideCaret()
            }
        }

        private func showCaret(at rect: CGRect, in textView: UITextView) {
            let pencil = parent.pencil
            let color = pencil.erasing ? UIColor.systemGray : pencil.color
            let caret = self.caret ?? {
                let view = UIView()
                view.isUserInteractionEnabled = false
                view.layer.cornerRadius = 2
                view.layer.borderColor = UIColor.systemBackground.cgColor
                view.layer.borderWidth = 1
                return view
            }()
            let halo = self.halo ?? {
                let view = UIView()
                view.isUserInteractionEnabled = false
                view.frame.size = CGSize(width: 30, height: 30)
                view.layer.cornerRadius = 15
                return view
            }()
            if caret.superview !== textView {
                textView.addSubview(halo)
                textView.addSubview(caret)
            }
            self.caret = caret
            self.halo = halo
            caret.backgroundColor = color
            halo.backgroundColor = color.withAlphaComponent(0.22)
            if pencil.style == .underline && !pencil.erasing {
                caret.frame = CGRect(x: rect.minX, y: rect.maxY + 1, width: 22, height: 4)
            } else {
                caret.frame = CGRect(x: rect.minX - 3, y: rect.minY - 1, width: 4, height: rect.height + 2)
            }
            halo.center = CGPoint(x: rect.minX, y: rect.midY)
            caret.alpha = 1
            halo.alpha = 1
        }

        private func hideCaret() {
            caret?.alpha = 0
            halo?.alpha = 0
        }

        // No system edit menu: the Hearken toolbar replaces it.
        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            UIMenu(children: [])
        }

        // Note buttons at the end of verses, and bookmark ribbons before them.
        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
            guard case .link(let url) = textItem.content, let verse = Int(url.host() ?? "") else { return defaultAction }
            switch url.scheme {
            case "hearken-note": return UIAction { [weak self] _ in self?.parent.onOpenNote(verse) }
            case "hearken-bookmark": return UIAction { [weak self] _ in self?.parent.onOpenBookmark(verse) }
            case "hearken-group": return UIAction { [weak self] _ in self?.parent.onOpenGroupItems(verse) }
            default: return defaultAction
            }
        }

        func textView(_ textView: UITextView, menuConfigurationFor textItem: UITextItem, defaultMenu: UIMenu) -> UITextItem.MenuConfiguration? {
            nil
        }
    }
}

/// Watches touches without taking part in them: it never recognizes, never blocks other
/// gestures and can't be blocked by them, so it sees a handle drag from start to finish.
final class TouchTracker: UIGestureRecognizer {
    enum Phase { case began, ended }

    var onTouch: (Phase, CGPoint) -> Void = { _, _ in }

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    convenience init() {
        self.init(target: nil, action: nil)
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first { onTouch(.began, touch.location(in: nil)) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        finish(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        finish(touches)
    }

    private func finish(_ touches: Set<UITouch>) {
        onTouch(.ended, touches.first?.location(in: nil) ?? .zero)
        state = .failed // never recognizes; resets for the next touch
    }
}

/// While Pencil mode is on, the reader's other gestures accept fingers (and trackpads) only.
/// Several text views can claim the same gesture (pages share a page controller), so the
/// original touch types are kept here and restored when the last one lets go.
enum PencilTouchRouting {
    private struct Claim {
        weak var recognizer: UIGestureRecognizer?
        let original: [NSNumber]
        var count: Int
    }

    private static var claims: [ObjectIdentifier: Claim] = [:]
    private static let fingers = [
        NSNumber(value: UITouch.TouchType.direct.rawValue),
        NSNumber(value: UITouch.TouchType.indirectPointer.rawValue),
    ]

    static func claim(_ recognizer: UIGestureRecognizer) {
        let id = ObjectIdentifier(recognizer)
        if var claim = claims[id], claim.recognizer === recognizer {
            claim.count += 1
            claims[id] = claim
        } else {
            claims[id] = Claim(recognizer: recognizer, original: recognizer.allowedTouchTypes, count: 1)
            recognizer.allowedTouchTypes = fingers
        }
    }

    static func release(_ recognizer: UIGestureRecognizer) {
        let id = ObjectIdentifier(recognizer)
        guard var claim = claims[id] else { return }
        claim.count -= 1
        if claim.count <= 0 {
            recognizer.allowedTouchTypes = claim.original
            claims[id] = nil
        } else {
            claims[id] = claim
        }
    }
}
