import SwiftData
import SwiftUI

/// Add or edit the note on a verse. Tags are typed as #words.
struct NoteEditorView: View {
    let chapterID: String
    let verse: Verse
    let reference: String
    let existing: Note?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var text: String
    @State private var tagsText: String
    @FocusState private var editorFocused: Bool

    init(chapterID: String, verse: Verse, reference: String, existing: Note?) {
        self.chapterID = chapterID
        self.verse = verse
        self.reference = reference
        self.existing = existing
        _text = State(initialValue: existing?.body ?? "")
        _tagsText = State(initialValue: existing?.tags.map { "#\($0)" }.joined(separator: " ") ?? "")
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section(reference) {
                    Text(verse.text)
                        .font(.scripture(size: 16))
                        .foregroundStyle(.secondary)
                }
                Section("Note") {
                    TextEditor(text: $text)
                        .frame(minHeight: 160)
                        .focused($editorFocused)
                        .accessibilityLabel("Note")
                }
                Section {
                    TextField("#faith #prayer", text: $tagsText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Tags")
                }
                if existing != nil {
                    Section {
                        Button("Delete Note", role: .destructive) {
                            if let existing { modelContext.delete(existing) }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "New Note" : "Edit Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") { save() }
                        .disabled(trimmed.isEmpty)
                }
            }
            .onAppear { editorFocused = existing == nil }
        }
        .presentationDetents([.medium, .large])
    }

    private var tags: [String] {
        tagsText
            .split(whereSeparator: { $0 == " " || $0 == "," })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "#")).lowercased() }
            .filter { !$0.isEmpty }
    }

    private func save() {
        if let existing {
            existing.body = trimmed
            existing.tags = tags
            existing.updatedAt = .now
        } else {
            modelContext.insert(Note(chapterID: chapterID, verse: verse.number, body: trimmed, tags: tags))
            MasteryService().award(MasteryConfig.standard.noteXP, reason: "note", in: modelContext)
        }
        dismiss()
    }
}
