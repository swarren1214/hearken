import SwiftData
import SwiftUI
import UIKit

/// Where a bookmark points: a verse in a chapter.
struct BookmarkTarget: Hashable, Identifiable {
    let chapterID: String
    let verse: Int
    var id: String { "\(chapterID):\(verse)" }
}

extension Bookmark {
    var target: BookmarkTarget { BookmarkTarget(chapterID: chapterID, verse: verse) }

    var hasName: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The bookmark's name, or its reference ("Alma 32:27") when it has none.
    func displayName(in content: ContentService) -> String {
        hasName ? name.trimmingCharacters(in: .whitespacesAndNewlines) : content.reference(chapterID: chapterID, verse: verse)
    }
}

/// A screen inside the bookmarks sheet.
enum BookmarkRoute: Hashable {
    case new
    case edit(Bookmark)
}

/// The list of bookmarks, from the reader or an opened book in the Library.
///
/// iPhone: a sheet with medium and large detents. iPad: a popover from the bookmark button.
/// Add, rename, move and delete all happen inside it; New and Edit push onto its stack.
struct BookmarksSheet: View {
    enum Scope: Hashable { case book, all }

    private struct BookmarkGroup: Identifiable {
        let id: String
        let title: String
        let items: [Bookmark]
    }

    /// The work being read; This Book shows only its bookmarks.
    let workID: String?
    /// Where the reader is (the verse at the top of the page), for Add Bookmark Here and
    /// Move Here. Nil from the Library.
    let current: BookmarkTarget?
    let onGo: (BookmarkTarget) -> Void

    @Environment(ContentService.self) private var content
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.accent) private var accent: AccentOption = .blue
    @Query(sort: \Bookmark.updatedAt, order: .reverse) private var bookmarks: [Bookmark]
    @State private var path: [BookmarkRoute]
    @State private var scope: Scope

    init(workID: String?, current: BookmarkTarget?, startRoute: BookmarkRoute? = nil, onGo: @escaping (BookmarkTarget) -> Void) {
        self.workID = workID
        self.current = current
        self.onGo = onGo
        _path = State(initialValue: startRoute.map { [$0] } ?? [])
        _scope = State(initialValue: workID == nil ? .all : .book)
    }

    private var work: LibraryWork? { workID.flatMap(LibraryCatalog.work) }

    /// Bookmarks grouped by work, in shelf order, newest first within each.
    private var groups: [BookmarkGroup] {
        let works = LibraryCatalog.shelves.flatMap(\.works)
        var byWork: [String: [Bookmark]] = [:]
        for bookmark in bookmarks {
            let id = LibraryCatalog.location(ofChapter: bookmark.chapterID)?.work.id ?? "other"
            if scope == .book, let workID, id != workID { continue }
            byWork[id, default: []].append(bookmark)
        }
        var result = works.compactMap { work in
            byWork[work.id].map { BookmarkGroup(id: work.id, title: work.title, items: $0) }
        }
        if let other = byWork["other"] { result.append(BookmarkGroup(id: "other", title: "Other", items: other)) }
        return result
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let current {
                    Section {
                        Button { path.append(.new) } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Add Bookmark Here")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("\(content.reference(chapterID: current.chapterID, verse: current.verse)) · top of the page")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }

                if groups.isEmpty {
                    // In the list (not laid over it), so it sits below Add Bookmark Here.
                    Section {
                        ContentUnavailableView {
                            Label("No Bookmarks", systemImage: "bookmark")
                        } description: {
                            Text(emptyMessage)
                        }
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                    }
                } else {
                    ForEach(groups) { group in
                        Section(group.title) {
                            ForEach(group.items) { row($0) }
                        }
                    }
                }
            }
            .listSectionSpacing(.compact)
            .safeAreaInset(edge: .top, spacing: 0) {
                // Pinned under the title rather than a list row, so it doesn't float in its own gap.
                if let work {
                    Picker("Show", selection: $scope.animation(.snappy)) {
                        Text(work.title).tag(Scope.book)
                        Text("All Books").tag(Scope.all)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                }
            }
            .navigationTitle("Bookmarks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", role: .close) { dismiss() }
                        .tint(Color.primary)
                }
                if current != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Add Bookmark", systemImage: "plus") { path.append(.new) }
                            .tint(Color.primary)
                    }
                }
            }
            .navigationDestination(for: BookmarkRoute.self) { route in
                BookmarkEditor(route: route, current: current, onGo: onGo)
            }
        }
        .tint(accent.color)
        .sensoryFeedback(trigger: bookmarks.count) { old, new in
            new > old ? .success : .impact(weight: .light)
        }
    }

    private var emptyMessage: String {
        if current == nil { return "Bookmark a page from the reader and it shows up here." }
        if scope == .book, let work { return "No bookmarks in the \(work.title) yet. Add one here, or see All Books." }
        return "Tap + to bookmark the verse at the top of the page."
    }

    private func row(_ bookmark: Bookmark) -> some View {
        let reference = content.reference(chapterID: bookmark.chapterID, verse: bookmark.verse)
        let here = bookmark.chapterID == current?.chapterID
        let detail = bookmark.hasName ? "\(reference) · \(Self.date(bookmark.updatedAt))" : Self.date(bookmark.updatedAt)

        return Button { onGo(bookmark.target) } label: {
            HStack(spacing: 12) {
                Image(systemName: "bookmark.fill")
                    .font(.title3)
                    .foregroundStyle(accent.color)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(bookmark.displayName(in: content))
                            .font(.headline)
                            .lineLimit(1)
                        if here {
                            Text("HERE")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(accent.color)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(accent.color.opacity(0.15), in: Capsule())
                        }
                    }
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the bookmark. Swipe or touch and hold for more.")
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) { modelContext.delete(bookmark) }
                .tint(.red)
            Button("Edit", systemImage: "pencil") { path.append(.edit(bookmark)) }
                .tint(.gray)
        }
        .contextMenu {
            Button("Go to Bookmark", systemImage: "arrow.right") { onGo(bookmark.target) }
            Button("Rename", systemImage: "pencil") { path.append(.edit(bookmark)) }
            if let current, current != bookmark.target {
                Button("Move Here", systemImage: "arrow.down.to.line") {
                    bookmark.chapterID = current.chapterID
                    bookmark.verse = current.verse
                    bookmark.updatedAt = .now
                }
            }
            Divider()
            Button(role: .destructive) {
                modelContext.delete(bookmark)
            } label: {
                Label { Text("Delete") } icon: { Image.redTrash }
            }
        }
        // Menu icons follow the row's tint: black or white, not the accent. (The bookmark icon
        // and HERE badge above use the accent explicitly.)
        .tint(Color.primary)
    }

    static func date(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if calendar.isDate(date, equalTo: .now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

/// New or Edit: the name, where it points (with Move Here) and Delete.
struct BookmarkEditor: View {
    let route: BookmarkRoute
    let current: BookmarkTarget?
    let onGo: (BookmarkTarget) -> Void

    @Environment(ContentService.self) private var content
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var location: BookmarkTarget?
    @FocusState private var nameFocused: Bool

    init(route: BookmarkRoute, current: BookmarkTarget?, onGo: @escaping (BookmarkTarget) -> Void) {
        self.route = route
        self.current = current
        self.onGo = onGo
        switch route {
        case .new:
            _name = State(initialValue: "")
            _location = State(initialValue: current)
        case .edit(let bookmark):
            _name = State(initialValue: bookmark.name)
            _location = State(initialValue: bookmark.target)
        }
    }

    private var existing: Bookmark? {
        if case .edit(let bookmark) = route { return bookmark }
        return nil
    }

    private func reference(_ target: BookmarkTarget) -> String {
        content.reference(chapterID: target.chapterID, verse: target.verse)
    }

    var body: some View {
        Form {
            Section {
                TextField(location.map(reference) ?? "Name", text: $name)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit(save)
            } header: {
                Text("Name")
            } footer: {
                Text(existing == nil ? "Leave blank to use the reference." : "Shown in your bookmarks and beside the verse.")
            }

            Section {
                if let location {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(reference(location), systemImage: "bookmark.fill")
                            .font(.headline)
                            .labelStyle(TintedIconLabelStyle())
                        if let text = content.chapter(location.chapterID)?.verses.first(where: { $0.number == location.verse })?.text {
                            Text(text)
                                .font(.scripture(size: 15))
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
                if existing != nil {
                    if let current, current != location {
                        Button {
                            withAnimation(.snappy) { location = current }
                        } label: {
                            LabeledContent {
                                Text(reference(current))
                            } label: {
                                Label("Move Here", systemImage: "arrow.down.to.line")
                            }
                        }
                        .accessibilityHint("Moves this bookmark to where you're reading now. Save to keep it.")
                    }
                    if let location {
                        Button {
                            save()
                            onGo(location)
                        } label: {
                            Label("Go to Bookmark", systemImage: "arrow.right")
                        }
                    }
                }
            } header: {
                Text("Location")
            } footer: {
                if existing == nil {
                    Text("Bookmarks the verse at the top of the page.")
                } else if current != nil {
                    Text("Move Here moves this bookmark to where you're reading now.")
                }
            }

            if let existing {
                Section {
                    Button(role: .destructive) {
                        modelContext.delete(existing)
                        dismiss()
                    } label: {
                        Label("Delete Bookmark", systemImage: "trash")
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.red)
                    .controlSize(.large)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
        }
        .navigationTitle(existing == nil ? "New Bookmark" : "Edit Bookmark")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", systemImage: "checkmark", role: .confirm, action: save)
                    .disabled(location == nil)
            }
        }
        .onAppear {
            if existing == nil { nameFocused = true }
        }
    }

    private func save() {
        guard let location else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing {
            existing.name = trimmed
            existing.chapterID = location.chapterID
            existing.verse = location.verse
            existing.updatedAt = .now
        } else {
            modelContext.insert(Bookmark(name: trimmed, chapterID: location.chapterID, verse: location.verse))
        }
        dismiss()
    }
}

extension Image {
    /// A red trash icon for destructive menu items. Menu icons otherwise take the view's tint,
    /// so the color is baked into the image.
    static var redTrash: Image {
        let symbol = UIImage(systemName: "trash")?.withTintColor(.systemRed, renderingMode: .alwaysOriginal)
        return symbol.map { Image(uiImage: $0) } ?? Image(systemName: "trash")
    }
}

/// A label whose icon takes the accent color while the title keeps the primary color.
private struct TintedIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.foregroundStyle(.tint)
            configuration.title
        }
    }
}

/// The confirmation shown after a quick add from the bookmark button's menu.
struct BookmarkAddedPill: View {
    let reference: String
    let onName: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bookmark.fill")
                .foregroundStyle(.tint)
            Text("Bookmarked \(reference)")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Button("Name", action: onName)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.glass)
                .tint(Color.primary)
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityElement(children: .contain)
    }
}
