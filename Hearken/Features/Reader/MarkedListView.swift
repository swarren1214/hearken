import SwiftData
import SwiftUI

/// All notes and highlights, filterable by highlight color.
struct MarkedListView: View {
    @Environment(ContentService.self) private var content
    @Environment(HighlightLegend.self) private var legend
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @Query(sort: \Highlight.updatedAt, order: .reverse) private var highlights: [Highlight]
    @State private var filter: HighlightHue?

    var body: some View {
        let filtered = highlights.filter { filter == nil || $0.hue == filter }

        List {
            if filter == nil && !notes.isEmpty {
                Section("Notes") {
                    ForEach(notes) { note in
                        NavigationLink {
                            ReaderView(chapterID: note.chapterID)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(content.reference(chapterID: note.chapterID, verse: note.verse))
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tint)
                                Text(note.body).lineLimit(3)
                                if !note.tags.isEmpty {
                                    Text(note.tags.map { "#\($0)" }.joined(separator: " "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            Section("Highlights") {
                if filtered.isEmpty {
                    Text("Tap a verse in the reader to highlight it.")
                        .foregroundStyle(.secondary)
                }
                ForEach(filtered) { highlight in
                    NavigationLink {
                        ReaderView(chapterID: highlight.chapterID)
                    } label: {
                        HStack(spacing: 12) {
                            Circle().fill(highlight.hue.color).frame(width: 14, height: 14)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(content.reference(chapterID: highlight.chapterID, verse: highlight.startVerse))
                                Text(legend.name(for: highlight.hue))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Notes and Highlights")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                CheckMenu([
                    CheckMenuItem.choice("All Colors", isSelected: filter == nil) { filter = nil },
                ] + legend.entries.map { entry in
                    CheckMenuItem.choice(legend.name(for: entry.hue), systemImage: "circle.fill", iconColor: entry.hue.color, isSelected: filter == entry.hue) {
                        filter = entry.hue
                    }
                }) {
                    Label("Filter", systemImage: filter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                .tint(Color.primary)
            }
        }
    }
}
