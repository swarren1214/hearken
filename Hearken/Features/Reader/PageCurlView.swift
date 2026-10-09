import SwiftUI
import UIKit

/// UIPageViewController with the native page-curl transition, hosting SwiftUI pages.
///
/// Turning past the first or last page reveals the neighboring chapter's page, then
/// calls `onLeaveChapter` so the reader can switch chapters. With Reduce Motion on, pages
/// slide instead of curling.
///
/// In a spread (iPad in landscape), two pages sit side by side with the spine in the middle,
/// like an open book, and each turn moves two pages. A chapter with an odd number of pages
/// ends on a blank right-hand page.
struct PageCurlView: UIViewControllerRepresentable {
    let pageCount: Int
    let startPage: Int
    let curl: Bool
    /// Two pages at once, spine in the middle. Only with the curl (sliding pages show one).
    var spread = false
    /// Hosted pages don't inherit SwiftUI's environment, so it's passed through.
    let environment: EnvironmentValues
    let page: (Int) -> AnyView
    /// What the curl reveals before the first page: the previous chapter's last page, or in
    /// a spread its last two (left, then right).
    let previousChapterPages: [AnyView]
    /// What the curl reveals after the last page: the next chapter's first page (or two).
    let nextChapterPages: [AnyView]
    /// A page turn has begun (used to dismiss any text selection).
    var onTurnStart: () -> Void = {}
    /// The page now on screen (the left one in a spread), after opening or a completed turn.
    var onPageChange: (Int) -> Void = { _ in }
    let onLeaveChapter: (_ forward: Bool) -> Void

    var isSpread: Bool { spread && curl }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let spine: UIPageViewController.SpineLocation = isSpread ? .mid : .min
        let controller = UIPageViewController(
            transitionStyle: curl ? .pageCurl : .scroll,
            navigationOrientation: .horizontal,
            options: curl
                ? [.spineLocation: NSNumber(value: spine.rawValue)]
                : [.interPageSpacing: NSNumber(value: 16)]
        )
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        // A spine in the middle shows a page on each side of every leaf.
        controller.isDoubleSided = isSpread
        controller.view.backgroundColor = .systemBackground
        // Taps belong to verses (highlighting); turn pages by swiping.
        for recognizer in controller.gestureRecognizers where recognizer is UITapGestureRecognizer {
            recognizer.isEnabled = false
        }

        let coordinator = context.coordinator
        let start = coordinator.clampedStart(startPage)
        controller.setViewControllers(coordinator.slots(startingAt: start).map(coordinator.host(for:)), direction: .forward, animated: false)
        onPageChange(start)
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.refresh(controller)
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        enum Slot: Hashable {
            case page(Int)
            /// Fills the right-hand side of a spread when a chapter has an odd number of pages.
            case blank
            case previousChapter(Int)
            case nextChapter(Int)
        }

        var parent: PageCurlView
        private var slotsByHost: [ObjectIdentifier: Slot] = [:]

        init(parent: PageCurlView) {
            self.parent = parent
        }

        /// One host per page, reused, so each page's text view (tied to that page's text
        /// container) is created once rather than every time the page comes back into view.
        private var hosts: [Slot: UIHostingController<AnyView>] = [:]

        func host(for slot: Slot) -> UIViewController {
            if let cached = hosts[slot] {
                cached.rootView = rootView(for: slot)
                return cached
            }
            let host = UIHostingController(rootView: rootView(for: slot))
            host.safeAreaRegions = []
            host.view.backgroundColor = .systemBackground
            slotsByHost[ObjectIdentifier(host)] = slot
            hosts[slot] = host
            return host
        }

        private func rootView(for slot: Slot) -> AnyView {
            let content: AnyView = switch slot {
            case .page(let index): parent.page(index)
            case .blank: AnyView(Color(.systemBackground))
            case .previousChapter(let index):
                parent.previousChapterPages.indices.contains(index) ? parent.previousChapterPages[index] : AnyView(Color.clear)
            case .nextChapter(let index):
                parent.nextChapterPages.indices.contains(index) ? parent.nextChapterPages[index] : AnyView(Color.clear)
            }
            return AnyView(content.environment(\.self, parent.environment))
        }

        private func slot(of controller: UIViewController?) -> Slot? {
            controller.flatMap { slotsByHost[ObjectIdentifier($0)] }
        }

        /// Every slot in reading order: the previous chapter's page(s), this chapter's pages
        /// (plus a blank to finish an odd spread), then the next chapter's.
        private var sequence: [Slot] {
            var result: [Slot] = parent.previousChapterPages.indices.map { .previousChapter($0) }
            result += (0..<max(parent.pageCount, 1)).map { .page($0) }
            if parent.isSpread, parent.pageCount % 2 == 1 { result.append(.blank) }
            result += parent.nextChapterPages.indices.map { .nextChapter($0) }
            return result
        }

        /// A valid first page: in range, and the left-hand (even) page in a spread.
        func clampedStart(_ page: Int) -> Int {
            let start = min(max(page, 0), max(parent.pageCount - 1, 0))
            return parent.isSpread ? start - start % 2 : start
        }

        /// The slots shown together, starting at `page`.
        func slots(startingAt page: Int) -> [Slot] {
            guard parent.isSpread else { return [.page(page)] }
            return [.page(page), page + 1 < parent.pageCount ? .page(page + 1) : .blank]
        }

        /// Re-renders visible pages after the chapter, highlights or layout change.
        func refresh(_ controller: UIPageViewController) {
            guard let visible = controller.viewControllers, let first = slot(of: visible.first) else { return }
            if case .page(let index) = first {
                let start = clampedStart(index)
                let expected = slots(startingAt: start)
                if index >= parent.pageCount || visible.compactMap(slot(of:)) != expected {
                    // Pages re-flowed (e.g. a larger text size) and these no longer line up.
                    controller.setViewControllers(expected.map(host(for:)), direction: .reverse, animated: false)
                    parent.onPageChange(start)
                    return
                }
            }
            for host in visible {
                if let host = host as? UIHostingController<AnyView>, let slot = slot(of: host) {
                    host.rootView = rootView(for: slot)
                }
            }
        }

        private func neighbor(of controller: UIViewController, offset: Int) -> UIViewController? {
            guard let current = slot(of: controller) else { return nil }
            let order = sequence
            guard let index = order.firstIndex(of: current), order.indices.contains(index + offset) else { return nil }
            return host(for: order[index + offset])
        }

        func pageViewController(_ controller: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            neighbor(of: viewController, offset: -1)
        }

        func pageViewController(_ controller: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            neighbor(of: viewController, offset: 1)
        }

        func pageViewController(_ controller: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
            parent.onTurnStart()
        }

        func pageViewController(
            _ controller: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            guard completed else { return }
            switch slot(of: controller.viewControllers?.first) {
            case .previousChapter: parent.onLeaveChapter(false)
            case .nextChapter: parent.onLeaveChapter(true)
            case .page(let index): parent.onPageChange(index)
            case .blank, nil: break
            }
        }
    }
}
