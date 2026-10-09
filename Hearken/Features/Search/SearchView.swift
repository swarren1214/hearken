import SwiftUI

/// What the search covers. Shown as native search scopes under the field.
enum SearchScope: String, CaseIterable, Identifiable {
    case all, scriptures, subjects

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All"
        case .scriptures: "Scriptures"
        case .subjects: "Subjects"
        }
    }
}

/// Recent searches, newest first, kept on this device.
enum SearchHistory {
    static let key = "search.recent"

    static func remember(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else { return }
        let stored = UserDefaults.standard.string(forKey: key) ?? ""
        var list = stored.split(separator: "\n").map(String.init).filter { $0.caseInsensitiveCompare(text) != .orderedSame }
        list.insert(text, at: 0)
        UserDefaults.standard.set(list.prefix(8).joined(separator: "\n"), forKey: key)
    }
}

private struct UnitHit: Identifiable {
    let subject: Subject
    let unit: StudyUnit
    var id: String { unit.id }
}

/// The search tab. Owns the query so `.searchable` sits on the tab's NavigationStack,
/// which is where iOS 26 expects it for the search tab's field.
struct SearchTab: View {
    @State private var query = ""
    @State private var scope: SearchScope = .all
    @State private var isSearchActive = false

    var body: some View {
        NavigationStack {
            SearchView(query: query, scope: scope) { recent in query = recent }
        }
        // Always show the field (never tucked under the title) and focus it, with the
        // keyboard up, whenever the Search tab opens.
        .searchable(
            text: $query,
            isPresented: $isSearchActive,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Verses, references, subjects"
        )
        .onAppear { activateSearch() }
        .searchScopes($scope, activation: .onSearchPresentation) {
            ForEach(SearchScope.allCases) { Text($0.title).tag($0) }
        }
        .onSubmit(of: .search) { SearchHistory.remember(query) }
    }

    private func activateSearch() {
        // A short hop lets the tab finish appearing; presenting sooner can be ignored.
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            isSearchActive = true
        }
    }
}

/// Results for a query: a jump-to reference ("Alma 32:27"), matching subjects and units,
/// and verses with the match emphasized. Empty query shows recent searches.
struct SearchView: View {
    let query: String
    let scope: SearchScope
    let onPickRecent: (String) -> Void

    @Environment(ContentService.self) private var content
    @AppStorage(SearchHistory.key) private var recentStorage = ""

    @State private var verseHits: [VerseHit] = []
    @State private var searchedQuery = ""
    @State private var isSearching = false

    private static let verseLimit = 200

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var recents: [String] { recentStorage.split(separator: "\n").map(String.init) }

    var body: some View {
        List {
            if trimmed.isEmpty {
                emptyState
            } else {
                results
            }
        }
        .navigationTitle("Search")
        .overlay {
            if !trimmed.isEmpty && isSearching && verseHits.isEmpty {
                ProgressView().controlSize(.large)
            }
        }
        .task(id: "\(trimmed)|\(scope.rawValue)") { await runSearch() }
    }

    // MARK: Empty state

    @ViewBuilder
    private var emptyState: some View {
        if recents.isEmpty {
            ContentUnavailableView {
                Label("Search the Scriptures", systemImage: "magnifyingglass")
            } description: {
                Text("Search for words in any verse, jump straight to a reference like Alma 32:27, or find a subject.")
            }
            .listRowBackground(Color.clear)

            Section("Try") {
                ForEach(["faith", "Alma 32:21", "charity", "Moroni 10:4"], id: \.self) { suggestion in
                    suggestionRow(suggestion, systemImage: "sparkle.magnifyingglass")
                }
            }
        } else {
            Section {
                ForEach(recents, id: \.self) { recent in
                    suggestionRow(recent, systemImage: "clock.arrow.circlepath")
                }
                .onDelete { offsets in
                    var list = recents
                    list.remove(atOffsets: offsets)
                    recentStorage = list.joined(separator: "\n")
                }
            } header: {
                HStack {
                    Text("Recent")
                    Spacer()
                    Button("Clear") { recentStorage = "" }
                        .font(.footnote)
                        .textCase(nil)
                }
            }
        }
    }

    private func suggestionRow(_ text: String, systemImage: String) -> some View {
        Button {
            onPickRecent(text)
        } label: {
            Label(text, systemImage: systemImage)
                .foregroundStyle(.primary)
        }
    }

    // MARK: Results

    @ViewBuilder
    private var results: some View {
        let reference = scope == .subjects ? nil : LibraryCatalog.parseReference(trimmed)
        let subjects: [Subject] = scope == .scriptures ? [] : subjectHits
        let units: [UnitHit] = scope == .scriptures ? [] : unitHits

        if let reference {
            Section("Go To") {
                NavigationLink {
                    ReaderView(chapterID: reference.chapterID)
                        .onAppear { remember(trimmed) }
                } label: {
                    Label(reference.title, systemImage: "arrow.right.circle.fill")
                        .font(.headline)
                }
            }
        }

        if !subjects.isEmpty {
            Section("Subjects") {
                ForEach(subjects) { subject in
                    NavigationLink {
                        SubjectDetailView(subject: subject)
                    } label: {
                        HStack(spacing: 12) {
                            SymbolTile(systemName: subject.symbol)
                            Text(subject.name)
                        }
                    }
                }
            }
        }

        if !units.isEmpty {
            Section("Units") {
                ForEach(units) { item in
                    NavigationLink {
                        UnitView(subject: item.subject, unit: item.unit)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.unit.title)
                            Text(item.subject.name).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }

        if scope != .subjects && !verseHits.isEmpty && searchedQuery == trimmed {
            Section {
                ForEach(verseHits) { hit in
                    NavigationLink {
                        ReaderView(chapterID: hit.chapterID)
                            .onAppear { remember(trimmed) }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(hit.reference)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tint)
                            Text(emphasized(hit.verse.text))
                                .font(.scripture(size: 16))
                                .lineLimit(4)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            } header: {
                Text(verseHits.count >= Self.verseLimit ? "Verses · first \(Self.verseLimit)" : "Verses · \(verseHits.count)")
            }
        }

        if !isSearching && reference == nil && subjects.isEmpty && units.isEmpty
            && (verseHits.isEmpty || scope == .subjects) && searchedQuery == trimmed {
            ContentUnavailableView.search(text: trimmed)
                .listRowBackground(Color.clear)
        }
    }

    private var subjectHits: [Subject] {
        guard trimmed.count >= 2 else { return [] }
        return content.subjects.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) || $0.summary.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var unitHits: [UnitHit] {
        guard trimmed.count >= 2 else { return [] }
        return content.subjects.flatMap { subject in
            subject.units
                .filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
                .map { UnitHit(subject: subject, unit: $0) }
        }
    }

    /// The verse with every occurrence of the query highlighted. Long verses start a little
    /// before the first match, so the match is always visible within the row's line limit.
    private func emphasized(_ fullText: String) -> AttributedString {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        var text = fullText
        if let first = fullText.range(of: trimmed, options: options),
           fullText.distance(from: fullText.startIndex, to: first.lowerBound) > 90 {
            // Back up about 40 characters to a word boundary for a little context.
            var start = fullText.index(first.lowerBound, offsetBy: -40, limitedBy: fullText.startIndex) ?? fullText.startIndex
            while start > fullText.startIndex, !fullText[fullText.index(before: start)].isWhitespace {
                start = fullText.index(before: start)
            }
            text = "…" + fullText[start...]
        }

        var attributed = AttributedString(text)
        var searchStart = text.startIndex
        while let range = text.range(of: trimmed, options: options, range: searchStart..<text.endIndex) {
            if let lower = AttributedString.Index(range.lowerBound, within: attributed),
               let upper = AttributedString.Index(range.upperBound, within: attributed) {
                attributed[lower..<upper][AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute.self] = Self.matchColor
                attributed[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
            }
            searchStart = range.upperBound
        }
        return attributed
    }

    private static let matchColor = Color.yellow.opacity(0.4)

    // MARK: Actions

    private func runSearch() async {
        let text = trimmed
        guard text.count >= 2, scope != .subjects else {
            verseHits = []
            searchedQuery = text
            isSearching = false
            return
        }
        isSearching = true
        // Wait for typing to pause before scanning every verse.
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        verseHits = content.search(text, limit: Self.verseLimit)
        searchedQuery = text
        isSearching = false
    }

    private func remember(_ text: String) {
        SearchHistory.remember(text)
    }
}

#Preview {
    SearchTab()
        .previewEnvironment()
}
