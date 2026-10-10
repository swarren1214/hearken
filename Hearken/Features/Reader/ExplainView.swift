import SwiftUI
import UIKit

/// The Explain sheet: the quoted passage, then In Plain Words, Words to Know, Context and
/// Related Passages, streaming in as the on-device model writes them. Sheet on iPhone
/// (medium and large), form sheet on iPad.
struct ExplainSheet: View {
    let request: ExplainRequest
    /// Open a related passage in the reader.
    var onOpenPassage: (BookmarkTarget) -> Void
    /// Save text as a note on the first selected verse. Returns false if that needs sign-in.
    var onSaveNote: (String) -> Bool

    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.accent) private var accent: AccentOption = .blue
    @State private var model: ExplainModel
    @State private var question = ""
    @State private var asking = false
    @State private var saved = false
    @State private var copied = false
    @FocusState private var questionFocused: Bool

    init(request: ExplainRequest, onOpenPassage: @escaping (BookmarkTarget) -> Void, onSaveNote: @escaping (String) -> Bool) {
        self.request = request
        self.onOpenPassage = onOpenPassage
        self.onSaveNote = onSaveNote
        _model = State(initialValue: ExplainModel(request: request))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    quote
                    switch model.phase {
                    case .unavailable(let message), .failed(let message):
                        notice(message)
                    case .generating, .done:
                        explanation
                    }
                    relatedSection
                    followUps
                    disclaimer
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
                .animation(.snappy, value: model.phase)
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", role: .close) { dismiss() }
                        .tint(Color.primary)
                }
                ToolbarItem(placement: .principal) {
                    Label("Explain", systemImage: "sparkles")
                        .labelStyle(.titleAndIcon)
                        .font(.headline)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Copy", systemImage: copied ? "checkmark" : "doc.on.doc") {
                        UIPasteboard.general.string = "\(request.reference)\n\n\(model.plainText)"
                        copied = true
                    }
                    .tint(Color.primary)
                    .disabled(model.phase != .done)
                }
            }
        }
        .tint(accent.color)
        .task { await model.start() }
        .sensoryFeedback(.success, trigger: saved) { _, new in new }
        .sensoryFeedback(.success, trigger: copied) { _, new in new }
    }

    // MARK: Sections

    private var quote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(request.reference)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tint)
            Text(request.selectedText)
                .font(.scripture(size: 16))
                .foregroundStyle(.secondary)
                .lineLimit(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var explanation: some View {
        let generating = model.phase == .generating

        card("In plain words") {
            if model.summary.isEmpty {
                placeholderLines(3)
            } else {
                Text(model.summary).font(.body)
            }
        }

        if generating || !model.terms.isEmpty {
            card("Words to know") {
                if model.terms.isEmpty {
                    placeholderLines(2)
                } else {
                    VStack(spacing: 0) {
                        ForEach(model.terms) { term in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(term.word)
                                    .font(.scripture(size: 16, weight: .semibold))
                                    .frame(width: 112, alignment: .leading)
                                Text(term.meaning)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 8)
                            .accessibilityElement(children: .combine)
                            if term.id != model.terms.last?.id { Divider() }
                        }
                    }
                }
            }
        }

        if generating || !model.context.isEmpty {
            card("Context") {
                if model.context.isEmpty {
                    placeholderLines(2)
                } else {
                    Text(model.context).font(.body)
                }
            }
        }
    }

    @ViewBuilder
    private var relatedSection: some View {
        if !model.relatedLoaded || !model.related.isEmpty {
            card("Related passages") {
                if !model.relatedLoaded {
                    placeholderLines(2)
                } else {
                    VStack(spacing: 0) {
                        ForEach(model.related) { passage in
                            Button {
                                dismiss()
                                onOpenPassage(BookmarkTarget(chapterID: passage.chapterID, verse: passage.verse))
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(passage.reference)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.tint)
                                        Text(passage.text)
                                            .font(.scripture(size: 15))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 2)
                                }
                                .padding(.vertical, 8)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens this verse in the reader")
                            if passage.id != model.related.last?.id { Divider() }
                        }
                        Text("Verses elsewhere that share key words with this one.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var followUps: some View {
        ForEach(model.exchanges) { exchange in
            VStack(alignment: .leading, spacing: 8) {
                Text(exchange.question)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.tint.opacity(0.14), in: .rect(cornerRadius: 14))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Group {
                    if exchange.answer.isEmpty {
                        placeholderLines(2)
                    } else {
                        Text(exchange.answer)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
            }
        }
    }

    private func notice(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "sparkles")
                .font(.subheadline)
            if let url = request.studyHelpsURL {
                Link(destination: url) {
                    Label("Open \(request.chapterTitle) in Gospel Library", systemImage: "arrow.up.right.square")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
    }

    private var disclaimer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("AI-generated study help, made privately on this device. It can be imperfect, so read it alongside the scriptures and the Church's study helps.", systemImage: "lock")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let url = request.studyHelpsURL, model.phase == .done {
                Link("Study helps for \(request.chapterTitle)", destination: url)
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        if model.phase == .done {
            Group {
                if asking {
                    HStack(spacing: 8) {
                        TextField("Ask about this passage", text: $question, axis: .vertical)
                            .lineLimit(1...3)
                            .focused($questionFocused)
                            .submitLabel(.send)
                            .onSubmit(send)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .glassEffect(.regular.interactive(), in: .capsule)
                        Button("Send", systemImage: "arrow.up", action: send)
                            .labelStyle(.iconOnly)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(accent.color, in: Circle())
                            .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || model.isAnswering)
                    }
                } else {
                    VStack(spacing: 10) {
                        Button {
                            if onSaveNote("\(model.plainText)\n\n— Explained with Hearken (AI)") { saved = true }
                        } label: {
                            Label(saved ? "Saved" : "Save as Note", systemImage: saved ? "checkmark" : "square.and.pencil")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(saved)
                        Button {
                            asking = true
                            questionFocused = true
                        } label: {
                            Label("Ask a Follow-up", systemImage: "bubble.left")
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(ExplainEngine.shared.availability != .available)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .tint(Color.primary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func send() {
        let text = question
        question = ""
        Task { await model.ask(text) }
    }

    // MARK: Pieces

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
    }

    private func placeholderLines(_ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .frame(height: 14)
                    .frame(maxWidth: index == count - 1 ? CGFloat(220) : CGFloat.infinity, alignment: .leading)
            }
        }
        .phaseAnimator([0.45, 1.0]) { view, opacity in
            view.opacity(opacity)
        } animation: { _ in .easeInOut(duration: 0.8) }
        .accessibilityLabel("Loading")
    }
}
