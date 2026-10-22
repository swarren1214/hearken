import SwiftData
import SwiftUI

/// Edit Shelves: drag to reorder, tap a name to rename, add a shelf, delete one (choosing
/// where its books go first). The Standard Works can move but not be renamed or deleted.
struct ShelfEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [LibraryShelfRecord]
    @Query private var placements: [ShelfPlacement]
    @Query private var books: [ImportedBook]

    @State private var deleting: LibraryShelfRecord?
    @FocusState private var focused: String?

    private var shelves: [LibraryShelfRecord] {
        records
            .filter { !$0.isRemoved }
            .sorted { $0.order == $1.order ? $0.createdAt < $1.createdAt : $0.order < $1.order }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(shelves) { shelf in
                        row(shelf)
                            .deleteDisabled(shelf.isLocked)
                    }
                    .onMove(perform: move)
                    .onDelete(perform: delete)

                    Button(action: addShelf) {
                        Label("New Shelf", systemImage: "plus.circle.fill")
                    }
                    .tint(Color.primary)
                } header: {
                    Text("Shelves")
                } footer: {
                    Text("Drag to reorder. Tap a name to rename it. Standard Works can move, but not be renamed or deleted.")
                }

                let hidden = LibraryStore.hiddenWorks(placements)
                if !hidden.isEmpty {
                    Section {
                        Button("Put Back Removed Books", systemImage: "arrow.uturn.backward") {
                            withAnimation { LibraryStore.restoreHiddenWorks(in: modelContext) }
                        }
                        .tint(Color.primary)
                    } footer: {
                        Text(ListFormatter.localizedString(byJoining: hidden.map(\.title)))
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit Shelves")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    SheetDoneButton {
                        commitNames()
                        dismiss()
                    }
                }
            }
            .sheet(item: $deleting) { shelf in
                DeleteShelfSheet(shelf: shelf, targets: shelves.filter { $0.id != shelf.id && !$0.isLocked })
            }
            .onChange(of: focused) { old, _ in
                if old != nil { commitNames() }
            }
        }
    }

    private func row(_ shelf: LibraryShelfRecord) -> some View {
        HStack(spacing: 12) {
            if shelf.isLocked {
                Text(shelf.name)
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Locked")
            } else {
                TextField("Shelf Name", text: name(of: shelf))
                    .focused($focused, equals: shelf.id)
                    .submitLabel(.done)
                    .onSubmit(commitNames)
            }
            Spacer(minLength: 8)
            let count = itemCount(shelf)
            if count > 0 {
                Text(count.formatted())
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .accessibilityLabel("\(count) \(count == 1 ? "book" : "books")")
            }
        }
    }

    private func name(of shelf: LibraryShelfRecord) -> Binding<String> {
        Binding {
            shelf.name
        } set: { value in
            shelf.name = value
            shelf.updatedAt = .now
        }
    }

    /// Blank names go back to something readable, and edits are saved.
    private func commitNames() {
        for shelf in shelves where shelf.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            shelf.name = "Untitled Shelf"
        }
        try? modelContext.save()
    }

    private func itemCount(_ shelf: LibraryShelfRecord) -> Int {
        let standard = shelf.id == LibraryStore.standardShelfID ? LibraryStore.standardWorks.count : 0
        return standard
            + books.filter { $0.shelfID == shelf.id }.count
            + placements.filter { $0.shelfID == shelf.id }.count
    }

    private func move(from source: IndexSet, to destination: Int) {
        var list = shelves
        list.move(fromOffsets: source, toOffset: destination)
        LibraryStore.reorder(list, in: modelContext)
    }

    private func delete(at offsets: IndexSet) {
        let list = shelves
        for index in offsets where list.indices.contains(index) {
            let shelf = list[index]
            guard !shelf.isLocked else { continue }
            if itemCount(shelf) == 0 {
                withAnimation { LibraryStore.delete(shelf, books: .remove, in: modelContext) }
            } else {
                // Has books: ask where they go first.
                deleting = shelf
            }
        }
    }

    /// Adds a shelf at the bottom with its name ready to type.
    private func addShelf() {
        let shelf = LibraryStore.addShelf(named: "New Shelf", in: modelContext)
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            focused = shelf.id
        }
    }
}

/// Deleting a shelf that has books: move them to another shelf, or remove them (and what
/// the user made in them) from the Library.
struct DeleteShelfSheet: View {
    let shelf: LibraryShelfRecord
    let targets: [LibraryShelfRecord]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var books: [ImportedBook]
    @Query private var placements: [ShelfPlacement]
    @State private var choice: LibraryStore.BooksChoice = .remove

    private var shelfBooks: [ImportedBook] { books.filter { $0.shelfID == shelf.id } }
    private var count: Int { shelfBooks.count + placements.filter { $0.shelfID == shelf.id }.count }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(count == 1
                         ? "“\(shelf.name)” has a book on it. Choose where it goes."
                         : "“\(shelf.name)” has \(count) books on it. Choose where they go.")
                        .foregroundStyle(.secondary)
                        .hearthBareRow()
                }

                if !targets.isEmpty {
                    Section("Move \(count == 1 ? "It" : "Them") To") {
                        ForEach(targets) { target in
                            option(target.name, detail: nil, selected: choice == .move(to: target.id)) {
                                choice = .move(to: target.id)
                            }
                        }
                    }
                }

                Section {
                    option(
                        count == 1 ? "Remove the book from my library" : "Remove the books from my library",
                        detail: removeDetail,
                        selected: choice == .remove,
                        destructive: true
                    ) {
                        choice = .remove
                    }
                }
            }
            .navigationTitle("Delete Shelf")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetCancelButton { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(role: .destructive) {
                    // Close first: the sheet mustn't redraw from a deleted shelf.
                    let shelf = shelf, choice = choice, context = modelContext
                    dismiss()
                    Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        withAnimation { LibraryStore.delete(shelf, books: choice, in: context) }
                    }
                } label: {
                    Text(deleteTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(.red)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .onAppear {
                if let first = targets.first { choice = .move(to: first.id) }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var deleteTitle: String {
        switch choice {
        case .move: count == 1 ? "Move Book and Delete Shelf" : "Move Books and Delete Shelf"
        case .remove: count == 1 ? "Delete Shelf and Book" : "Delete Shelf and Books"
        }
    }

    private var removeDetail: String {
        let summary = LibraryStore.studySummary(forBooks: shelfBooks.map(\.id), in: modelContext)
        if let summary { return "Also deletes your \(summary) in them." }
        return "Hearken's own books can be put back later from Edit Shelves."
    }

    private func option(_ title: String, detail: String?, selected: Bool, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(destructive ? Color.red : Color.primary)
                    if let detail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 12)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(destructive ? Color.red : Color.primary)
                    .opacity(selected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
