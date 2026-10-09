import SwiftUI

/// The search tab: scripture text and subjects.
struct SearchView: View {
    @Environment(ContentService.self) private var content
    @State private var query = ""

    var body: some View {
        let verseHits = content.search(query)
        let subjectHits = query.count < 2 ? [] : content.subjects.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.summary.localizedCaseInsensitiveContains(query)
        }

        List {
            if query.isEmpty {
                ContentUnavailableView("Search the scriptures", systemImage: "magnifyingglass", description: Text("Find verses, subjects and topics."))
                    .listRowBackground(Color.clear)
            } else if verseHits.isEmpty && subjectHits.isEmpty && query.count >= 2 {
                ContentUnavailableView.search(text: query)
                    .listRowBackground(Color.clear)
            }

            if !subjectHits.isEmpty {
                Section("Subjects") {
                    ForEach(subjectHits) { subject in
                        NavigationLink {
                            SubjectDetailView(subject: subject)
                        } label: {
                            Label(subject.name, systemImage: subject.symbol)
                        }
                    }
                }
            }

            if !verseHits.isEmpty {
                Section("Verses") {
                    ForEach(verseHits) { hit in
                        NavigationLink {
                            ReaderView(chapterID: hit.chapterID)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(hit.reference)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tint)
                                Text(hit.verse.text)
                                    .font(.scripture(size: 16))
                                    .lineLimit(3)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Verses, subjects, topics")
    }
}
