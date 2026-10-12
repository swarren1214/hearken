import SwiftData
import SwiftUI
import UIKit

/// The sheet every import lands on (Files picker, Share sheet, drag and drop). It opens at
/// once with a row per file; each row shows a spinner while its file is read, then the
/// book's cover, title and author (editable). Add waits until every file has been read.
struct AddToLibrarySheet: View {
    let batchID: UUID

    @Environment(\.modelContext) private var modelContext
    @Query private var shelfRecords: [LibraryShelfRecord]
    @State private var importer = BookImporter.shared
    @State private var shelfID = ""
    @State private var namingShelf = false
    @State private var newShelfName = ""

    private static let newShelfTag = "library.newShelf"
    private static let myBooksTag = "library.myBooks"

    private var batch: ImportBatch? {
        importer.batch.flatMap { $0.id == batchID ? $0 : nil }
    }

    private var usableShelves: [LibraryShelfRecord] {
        shelfRecords.filter { !$0.isRemoved && !$0.isLocked }.sorted { $0.order < $1.order }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let batch {
                    ForEach(batch.drafts) { draft in
                        draftSection(draft)
                    }
                }

                Section {
                    CheckPicker("Shelf", selection: shelfSelection, options: shelfOptions)
                } footer: {
                    Text("Title and author come from each file; change them if you like.")
                }
            }
            .animation(.snappy, value: batch?.drafts.map(\.state))
            .navigationTitle("Add to Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) {
                        if let batch { importer.cancel(batch) }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { addButton }
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

    // MARK: Rows

    @ViewBuilder
    private func draftSection(_ draft: ImportDraft) -> some View {
        switch draft.state {
        case .reading:
            Section {
                HStack(spacing: 14) {
                    FileBadge(format: draft.format)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(draft.fileName)
                            .font(.headline)
                            .lineLimit(2)
                        Text("Reading…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    ProgressView()
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(draft.fileName), reading")
            }
        case .failed(let reason):
            Section {
                HStack(spacing: 14) {
                    FileBadge(format: draft.format)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(draft.fileName)
                            .font(.headline)
                            .lineLimit(2)
                        Text(reason)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Couldn't be read")
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            } footer: {
                Text("This file won't be added.")
            }
        case .ready:
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
                        Text(draft.summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)

                LabeledContent("Title") {
                    TextField("Title", text: field(draft.id, \.title))
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Author") {
                    TextField("Author", text: field(draft.id, \.author))
                        .multilineTextAlignment(.trailing)
                }
            } footer: {
                if let duplicate = draft.duplicateOf {
                    Label("This file is already in your library as “\(duplicate)”. Adding it again makes a second copy.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    /// A text field's binding into the shared batch, so edits survive rows filling in.
    private func field(_ id: String, _ keyPath: WritableKeyPath<ImportDraft, String>) -> Binding<String> {
        Binding {
            importer.batch?.drafts.first { $0.id == id }?[keyPath: keyPath] ?? ""
        } set: { value in
            guard let index = importer.batch?.drafts.firstIndex(where: { $0.id == id }) else { return }
            importer.batch?.drafts[index][keyPath: keyPath] = value
        }
    }

    // MARK: Add

    private var addButton: some View {
        let reading = batch?.readingCount ?? 0
        let ready = batch?.ready.count ?? 0
        return Button(action: add) {
            HStack(spacing: 10) {
                if reading > 0 {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(reading > 0
                     ? "Reading \(reading) \(reading == 1 ? "file" : "files")…"
                     : ready == 1 ? "Add Book" : "Add \(ready) Books")
                    .contentTransition(.numericText())
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent)
        .disabled(reading > 0 || ready == 0)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .animation(.snappy, value: reading)
    }

    private func add() {
        guard let batch else { return }
        var target = shelfID
        if target == Self.myBooksTag || target.isEmpty || !usableShelves.contains(where: { $0.id == target }) {
            target = usableShelves.first?.id ?? LibraryStore.addShelf(named: "My Books", in: modelContext).id
        }
        importer.add(batch, toShelf: target, in: modelContext)
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
        if let preferred = batch?.preferredShelfID, usableShelves.contains(where: { $0.id == preferred }) {
            shelfID = preferred
        } else {
            shelfID = LibraryStore.defaultImportShelf(shelfRecords) ?? Self.myBooksTag
        }
    }
}

/// A file's type, before its cover is known.
private struct FileBadge: View {
    let format: ImportedBook.Format

    var body: some View {
        Text(format.title)
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.bottom, 8)
            .frame(width: 60, height: 90, alignment: .bottom)
            .background(format == .pdf ? Color(hex: 0xE5484D) : Color(hex: 0x7E57C2), in: .rect(cornerRadius: 6))
            .accessibilityHidden(true)
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
