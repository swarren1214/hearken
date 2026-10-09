import SwiftData
import SwiftUI

/// The Scriptures tab: shelves of front covers. Tapping a cover lifts it and zooms it
/// open into the book (see LibraryBookView).
struct LibraryView: View {
    @Namespace private var covers
    @Query private var progressRecords: [ReadingProgress]
    @Query private var highlights: [Highlight]

    var body: some View {
        let progress = LibraryProgress(progress: progressRecords, highlights: highlights)

        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                ForEach(LibraryCatalog.shelves) { shelf in
                    shelfRow(shelf, progress: progress)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Library")
        .navigationDestination(for: LibraryRoute.self) { route in
            if let work = LibraryCatalog.work(route.workID) {
                LibraryBookView(work: work)
                    .navigationTransition(.zoom(sourceID: work.id, in: covers))
            }
        }
    }

    private func shelfRow(_ shelf: LibraryShelf, progress: LibraryProgress) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(shelf.title)
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(shelf.caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 14) {
                    ForEach(shelf.works) { work in
                        cover(work, progress: progress)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 22) // headroom for the lift
            }
            .scrollClipDisabled()

            ShelfBoard()
                .padding(.horizontal, 14)
        }
    }

    @ViewBuilder
    private func cover(_ work: LibraryWork, progress: LibraryProgress) -> some View {
        if work.isAvailable {
            NavigationLink(value: LibraryRoute(workID: work.id)) {
                BookCover(work: work, showsRibbon: progress.isReading(work))
            }
            .buttonStyle(CoverLiftStyle())
            .matchedTransitionSource(id: work.id, in: covers)
            .accessibilityLabel(work.title)
            .accessibilityHint(progress.isReading(work) ? "Reading now. Opens the book." : "Opens the book.")
        } else {
            BookCover(work: work)
                .opacity(0.55)
                .overlay(alignment: .topTrailing) {
                    Text("Soon")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.45), in: .rect(cornerRadius: 6))
                        .padding(8)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(work.title), coming soon")
        }
    }
}

#Preview {
    NavigationStack { LibraryView() }
        .previewEnvironment(signedIn: true)
}
