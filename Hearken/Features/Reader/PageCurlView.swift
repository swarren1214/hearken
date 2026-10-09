import SwiftUI
import UIKit

/// UIPageViewController with the native page-curl transition, hosting SwiftUI pages.
///
/// Turning past the first or last page reveals the neighboring chapter's page, then
/// calls `onLeaveChapter` so the reader can switch chapters. With Reduce Motion on, pages
/// slide instead of curling.
struct PageCurlView: UIViewControllerRepresentable {
    let pageCount: Int
    let startPage: Int
    let curl: Bool
    /// Hosted pages don't inherit SwiftUI's environment, so it's passed through.
    let environment: EnvironmentValues
    let page: (Int) -> AnyView
    let previousChapterPage: AnyView?
    let nextChapterPage: AnyView?
    let onLeaveChapter: (_ forward: Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(
            transitionStyle: curl ? .pageCurl : .scroll,
            navigationOrientation: .horizontal,
            options: curl
                ? [.spineLocation: NSNumber(value: UIPageViewController.SpineLocation.min.rawValue)]
                : [.interPageSpacing: NSNumber(value: 16)]
        )
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        controller.isDoubleSided = false
        controller.view.backgroundColor = .systemBackground
        // Taps belong to verses (highlighting); turn pages by swiping.
        for recognizer in controller.gestureRecognizers where recognizer is UITapGestureRecognizer {
            recognizer.isEnabled = false
        }

        let start = min(max(startPage, 0), max(pageCount - 1, 0))
        controller.setViewControllers([context.coordinator.host(for: .page(start))], direction: .forward, animated: false)
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.refresh(controller)
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        enum Slot: Hashable {
            case page(Int)
            case previousChapter
            case nextChapter
        }

        var parent: PageCurlView
        private var slots: [ObjectIdentifier: Slot] = [:]

        init(parent: PageCurlView) {
            self.parent = parent
        }

        func host(for slot: Slot) -> UIViewController {
            let host = UIHostingController(rootView: rootView(for: slot))
            host.safeAreaRegions = []
            host.view.backgroundColor = .systemBackground
            slots[ObjectIdentifier(host)] = slot
            return host
        }

        private func rootView(for slot: Slot) -> AnyView {
            let content: AnyView = switch slot {
            case .page(let index): parent.page(index)
            case .previousChapter: parent.previousChapterPage ?? AnyView(Color.clear)
            case .nextChapter: parent.nextChapterPage ?? AnyView(Color.clear)
            }
            return AnyView(content.environment(\.self, parent.environment))
        }

        private func slot(of controller: UIViewController?) -> Slot? {
            controller.flatMap { slots[ObjectIdentifier($0)] }
        }

        /// Re-renders visible pages after the chapter, highlights or layout change.
        func refresh(_ controller: UIPageViewController) {
            guard let visible = controller.viewControllers?.first as? UIHostingController<AnyView>,
                  let slot = slot(of: visible) else { return }
            if case .page(let index) = slot, index >= parent.pageCount {
                // Pages re-flowed (e.g. a larger text size) and this one no longer exists.
                controller.setViewControllers([host(for: .page(max(parent.pageCount - 1, 0)))], direction: .reverse, animated: false)
                return
            }
            visible.rootView = rootView(for: slot)
        }

        func pageViewController(_ controller: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard case .page(let index) = slot(of: viewController) else { return nil }
            if index > 0 { return host(for: .page(index - 1)) }
            return parent.previousChapterPage == nil ? nil : host(for: .previousChapter)
        }

        func pageViewController(_ controller: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard case .page(let index) = slot(of: viewController) else { return nil }
            if index < parent.pageCount - 1 { return host(for: .page(index + 1)) }
            return parent.nextChapterPage == nil ? nil : host(for: .nextChapter)
        }

        func pageViewController(
            _ controller: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            for previous in previousViewControllers where previous !== controller.viewControllers?.first {
                slots[ObjectIdentifier(previous)] = nil
            }
            guard completed else { return }
            switch slot(of: controller.viewControllers?.first) {
            case .previousChapter: parent.onLeaveChapter(false)
            case .nextChapter: parent.onLeaveChapter(true)
            default: break
            }
        }
    }
}
