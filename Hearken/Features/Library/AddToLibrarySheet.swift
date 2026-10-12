import SwiftData
import SwiftUI
import UIKit

/// The sheet every import lands on (Files picker, Share sheet, drag and drop): each book's
/// cover, title and author, read from the file and editable, and the shelf they go on.
struct AddToLibrarySheet: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var shelfRecords: [LibraryShelfRecord]

    @State private var batch: ImportBatch
    @State private var shelfID = ""
    @State private var namingShelf = false
    @State private var newShelfName = ""

    private static let newShelfTag = "library.newShelf"
    private static let myBooksTag = "library.myBooks"

    init(batch: ImportBatch) {
        _batch = State(initialValue: batch)
    }

    private var usableShelves: [LibraryShelfRecord] {
        shelfRecords.filter { !$0.isRemoved && !$0.isLocked }.sorted { $0.order < $1.order }
    }

    var body: some View {
        NavigationStack {
            Form {
                ForEach($batch.drafts) { $draft in
                    Section {
                        HStack(spacing: 14) {
                            DraftCover(draft: draft)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(draft.title.isEmpty ? draft.fileName : draft.title)
                                    .font(.headline)
                                    .lineLimit(2)
                                if !draft.author.isEmpty {
                                    Text(draft.author)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Text(position(of: draft) + draft.summary)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)

                        LabeledContent("Title") {
                            TextField("Title", text: $draft.title)
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Author") {
                            TextField("Author", text: $draft.author)
                                .multilineTextAlignment(.trailing)
                        }
                    } footer: {
                        if let duplicate = draft.duplicateOf {
                            Label("This file is already in your library as “\(duplicate)”. Adding it again makes a second copy.", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Section {
                    CheckPicker("Shelf", selection: shelfSelection, options: shelfOptions)
                } footer: {
                    Text("Title and author come from the file; change them if you like.")
                }

                if !batch.failures.isEmpty {
                    Section("Couldn't Import") {
                        ForEach(batch.failures.indices, id: \.self) { index in
                            let failure = batch.failures[index]
                            VStack(alignment: .leading, spacing: 2) {
                                Text(failure.name)
                                Text(failure.reason)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add to Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) {
                        BookImporter.shared.cancel(batch)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: add) {
                    Text(batch.drafts.count == 1 ? "Add Book" : "Add \(batch.drafts.count) Books")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .alert("New Shelf", isPresented: $namingShelf) {
                TextField("Name", text: $newShelfName)
                Button("Cancel", role: .cancel) {}
                Button("Add") {
                    shelfID = LibraryStore.addShelf(named: newShelfName, in: modelContext).id
                }
            } message: {
                Text("Name the shelf, like “Apocryphal Texts”.")
            }
            .onAppear(perform: chooseShelf)
        }
        .interactiveDismissDisabled()
    }

    // MARK: Shelf

    private var shelfOptions: [CheckPickerOption<String>] {
        var options = usableShelves.map { CheckPickerOption(value: $0.id, title: $0.name, systemImage: "books.vertical") }
        if options.isEmpty {
            options.append(CheckPickerOption(value: Self.myBooksTag, title: "My Books", systemImage: "books.vertical"))
        }
        options.append(CheckPickerOption(value: Self.newShelfTag, title: "New Shelf…", systemImage: "plus"))
        return options
    }

    /// Picking New Shelf… asks for a name instead of selecting it.
    private var shelfSelection: Binding<String> {
        Binding {
            shelfID
        } set: { value in
            if value == Self.newShelfTag {
                newShelfName = ""
                // After the picker's popover has closed.
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    namingShelf = true
                }
            } else {
                shelfID = value
            }
        }
    }

    private func chooseShelf() {
        guard shelfID.isEmpty else { return }
        if let preferred = batch.preferredShelfID, usableShelves.contains(where: { $0.id == preferred }) {
            shelfID = preferred
        } else {
            shelfID = LibraryStore.defaultImportShelf(shelfRecords) ?? Self.myBooksTag
        }
    }

    private func add() {
        var target = shelfID
        if target == Self.myBooksTag || target.isEmpty || !usableShelves.contains(where: { $0.id == target }) {
            target = usableShelves.first?.id ?? LibraryStore.addShelf(named: "My Books", in: modelContext).id
        }
        BookImporter.shared.add(batch, toShelf: target, in: modelContext)
    }

    private func position(of draft: ImportDraft) -> String {
        guard batch.drafts.count > 1, let index = batch.drafts.firstIndex(where: { $0.id == draft.id }) else { return "" }
        return "\(index + 1) of \(batch.drafts.count) · "
    }
}

/// A draft's cover: its art, or the cloth cover it will get.
private struct DraftCover: View {
    let draft: ImportDraft

    var body: some View {
        Group {
            if let data = draft.coverData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 90)
                    .clipShape(.rect(cornerRadius: 4))
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 3)
            } else {
                BookCover(
                    work: LibraryWork(
                        id: draft.id, title: draft.title, subtitle: draft.author,
                        coverHex: UInt32(BookImporter.coverColor(for: draft.title)), summary: "", volumes: []
                    ),
                    size: CGSize(width: 60, height: 90)
                )
            }
        }
        .accessibilityHidden(true)
    }
}

/// Edit an imported book's title and author.
struct BookDetailsSheet: View {
    let book: ImportedBook

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var title = ""
    @State private var author = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Title") {
                        TextField("Title", text: $title)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Author") {
                        TextField("Author", text: $author)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("\(book.formatSummary) · \(book.fileName)")
                }
            }
            .navigationTitle("Edit Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        save()
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                title = book.title
                author = book.author
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        book.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        book.author = author.trimmingCharacters(in: .whitespacesAndNewlines)
        book.updatedAt = .now
        try? modelContext.save()
        ImportedLibrary.shared.refresh()
    }
}
