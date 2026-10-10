import UIKit

/// Lets the reader ask which verse is at the top of the screen (for bookmarks), and scroll
/// to a verse (when opening one). The chapter text view and the reader page keep it current.
@MainActor
final class ReaderProbe {
    /// Scroll layout: the chapter's text view.
    weak var textView: UITextView?
    var layout: ChapterTextLayout?
    /// Page Turn: where each page's text starts, and the page on screen.
    var isPaged = false
    var pageRanges: [NSRange] = []
    var currentPage = 0
    /// The first verse of the current selection, if any (Listen starts there).
    var selectedVerse: Int?

    /// The verse at the top of the page: the first line on screen in Scroll, the first line
    /// of the current page in Page Turn.
    func topVerse() -> Int? {
        guard let layout else { return nil }
        let first = layout.spans.first?.verse
        if isPaged {
            guard !pageRanges.isEmpty else { return first }
            if currentPage >= pageRanges.count { return layout.spans.last?.verse }
            return layout.position(at: pageRanges[max(currentPage, 0)].location, preferEnd: false)?.verse ?? first
        }
        guard let textView, let scrollView = Self.enclosingScrollView(of: textView) else { return first }
        let visibleTop = scrollView.contentOffset.y + scrollView.adjustedContentInset.top + 8
        let y = scrollView.convert(CGPoint(x: 0, y: visibleTop), to: textView).y
        guard y > 0, let position = textView.closestPosition(to: CGPoint(x: 4, y: y)) else { return first }
        let index = textView.offset(from: textView.beginningOfDocument, to: position)
        return layout.position(at: index, preferEnd: false)?.verse ?? first
    }

    /// Scrolls so `verse` sits just below the top bar. Scroll layout only; Page Turn opens
    /// on the verse's page instead.
    func reveal(verse: Int, animated: Bool = false) {
        guard !isPaged, let layout, let textView, let scrollView = Self.enclosingScrollView(of: textView),
              let range = layout.verseText(verse) else { return }
        scrollView.layoutIfNeeded()
        guard let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
              let end = textView.position(from: start, offset: min(1, range.length)),
              let textRange = textView.textRange(from: start, to: end) else { return }
        let rect = textView.convert(textView.firstRect(for: textRange), to: scrollView)
        guard !rect.isNull, !rect.isInfinite else { return }
        let inset = scrollView.adjustedContentInset
        let lowest = max(-inset.top, scrollView.contentSize.height + inset.bottom - scrollView.bounds.height)
        let y = min(max(rect.minY - inset.top - 12, -inset.top), lowest)
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: y), animated: animated)
    }

    /// The reader's scroll view (the text view is itself a scroll view, so start above it).
    private static func enclosingScrollView(of view: UIView) -> UIScrollView? {
        var current = view.superview
        while let candidate = current {
            if let scrollView = candidate as? UIScrollView, scrollView.isScrollEnabled { return scrollView }
            current = candidate.superview
        }
        return nil
    }
}
