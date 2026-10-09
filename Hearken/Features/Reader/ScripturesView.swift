import SwiftData
import SwiftUI

/// The Scriptures tab: the standard works, plus everything the user has marked.
struct ScripturesView: View {
    @Environment(ContentService.self) private var content

    var body: some View {
        List {
            Section {
                NavigationLink {
                    MarkedListView()
                } label: {
                    Label("Notes and Highlights", systemImage: "square.and.pencil")
                }
            }

            ForEach(content.volumes) { volume in
                Section(volume.title) {
                    ForEach(volume.books) { book in
                        ForEach(book.chapters) { chapter in
                            NavigationLink {
                                ReaderView(chapterID: chapter.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(book.title) \(chapter.number)")
                                        .font(.scripture(size: 18, weight: .semibold))
                                    if let heading = chapter.heading {
                                        Text(heading)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Section {
                Text("This build includes sample chapters. The full standard works arrive with the content import.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Scriptures")
    }
}

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
                Menu {
                    Picker("Color", selection: $filter) {
                        Text("All Colors").tag(HighlightHue?.none)
                        ForEach(legend.entries) { entry in
                            Label(legend.name(for: entry.hue), systemImage: "circle.fill")
                                .tint(entry.hue.color)
                                .tag(HighlightHue?.some(entry.hue))
                        }
                    }
                } label: {
                    Label("Filter", systemImage: filter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
    }
}
