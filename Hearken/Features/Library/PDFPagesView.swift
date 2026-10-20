import PDFKit
import SwiftUI

/// An imported PDF's printed pages, for figures, facsimiles and tables the reflowed text
/// can't show. Swipe between pages; pinch to zoom.
struct PDFPagesView: View {
    let url: URL
    let title: String
    let startPage: Int

    @Environment(\.dismiss) private var dismiss
    @State private var page = 1
    @State private var pageCount = 0

    var body: some View {
        NavigationStack {
            PDFPageReader(url: url, startPage: startPage, page: $page, pageCount: $pageCount)
                .ignoresSafeArea(edges: .bottom)
                .background(Color(.secondarySystemBackground))
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        SheetDoneButton { dismiss() }
                    }
                }
                .overlay(alignment: .bottom) {
                    if pageCount > 0 {
                        Text("Page \(page) of \(pageCount)")
                            .font(.footnote.weight(.medium))
                            .monospacedDigit()
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .glassEffect(.regular, in: .capsule)
                            .padding(.bottom, 12)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                }
        }
    }
}

/// PDFKit's view, one page at a time, swiping sideways.
private struct PDFPageReader: UIViewRepresentable {
    let url: URL
    let startPage: Int
    @Binding var page: Int
    @Binding var pageCount: Int

    func makeCoordinator() -> Coordinator { Coordinator(page: $page) }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePage
        view.displayDirection = .horizontal
        view.autoScales = true
        view.usePageViewController(true)
        view.backgroundColor = .secondarySystemBackground
        if let document = PDFDocument(url: url) {
            view.document = document
            if let start = document.page(at: max(0, min(startPage - 1, document.pageCount - 1))) {
                view.go(to: start)
            }
            Task { @MainActor in
                pageCount = document.pageCount
                page = max(1, min(startPage, document.pageCount))
            }
        }
        context.coordinator.observe(view)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {}

    final class Coordinator: NSObject {
        let page: Binding<Int>
        nonisolated(unsafe) private var observer: (any NSObjectProtocol)?

        init(page: Binding<Int>) {
            self.page = page
        }

        func observe(_ view: PDFView) {
            observer = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak view, page] _ in
                MainActor.assumeIsolated {
                    guard let view, let current = view.currentPage, let document = view.document else { return }
                    page.wrappedValue = document.index(for: current) + 1
                }
            }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}
