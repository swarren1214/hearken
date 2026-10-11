import SwiftData
import SwiftUI
import WebKit

/// One learning item: what to read or watch, then the written response that completes it.
///
/// Completing an item takes a genuine response, not just opening a link: at least
/// ScholarRules.minimumResponseWords words, and, when Apple Intelligence is available, a light
/// on-device review that it answers the prompt. A response flagged once can be revised; a second
/// submission is accepted with the reviewer's note kept.
struct LearningItemView: View {
    let path: ScholarPathFile
    let item: PathItem

    var body: some View {
        ScholarProgressReader(path: path) { progress in
            LearningItemContent(path: path, item: item, progress: progress)
        }
    }
}

private struct ReaderTarget: Identifiable {
    let chapterID: String
    let verse: Int
    var id: String { "\(chapterID):\(verse)" }
}

private struct LearningItemContent: View {
    let path: ScholarPathFile
    let item: PathItem
    let progress: ScholarProgress

    @Environment(ContentService.self) private var content
    @Environment(\.modelContext) private var modelContext
    @Query private var completions: [ItemCompletion]
    @State private var response = ""
    @State private var editing = false
    @State private var reviewing = false
    @State private var reviewNote: String?
    @State private var flaggedOnce = false
    @State private var reader: ReaderTarget?
    @State private var justCompleted = 0
    @FocusState private var editorFocused: Bool

    init(path: ScholarPathFile, item: PathItem, progress: ScholarProgress) {
        self.path = path
        self.item = item
        self.progress = progress
        let itemID = item.id, subjectID = path.subjectID
        _completions = Query(filter: #Predicate<ItemCompletion> { $0.itemID == itemID && $0.subjectID == subjectID })
    }

    private var completion: ItemCompletion? { completions.first { !$0.cleared } }
    private var course: PathCourse? { path.stages.flatMap(\.courses).first { $0.allItems.contains { $0.id == item.id } } }
    private var unlocked: Bool { course.map { progress.isUnlocked($0) } ?? false }
    private var words: Int { ScholarRules.wordCount(response) }
    private var canSubmit: Bool { unlocked && words >= ScholarRules.minimumResponseWords && !reviewing }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                material
                if let completion, !editing {
                    completedCard(completion)
                } else {
                    responseCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(item.kindName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $reader) { target in
            NavigationStack {
                ReaderView(chapterID: target.chapterID, verse: target.verse)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done", systemImage: "checkmark") { reader = nil }
                        }
                    }
            }
        }
        .sensoryFeedback(.success, trigger: justCompleted)
        .onAppear { if let completion { response = completion.response } }
    }

    // MARK: Header and material

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(item.kindName.uppercased()) · \(item.required ? "REQUIRED" : "OPTIONAL") · \(progress.isAwarded(item) ? "XP EARNED" : "+\(item.xp) XP")")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tint)
            Text(item.title).font(.title2.bold())
            if let minutes = item.minutes {
                Text("About \(minutes) min").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var material: some View {
        switch item.kind {
        case .lesson:
            if let body = item.body {
                Text(markdown(body))
                    .font(.body)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
            }
        case .reading:
            if let passage = item.passage {
                passageCard(passage)
            } else if let source = item.source {
                sourceCard(source)
            }
        case .video:
            videoCard
        case .practice:
            if let criteria = item.successCriteria {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Success criteria").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    Text(criteria).font(.body)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
            }
        }
    }

    private func passageCard(_ passage: PathPassage) -> some View {
        let verses = content.chapter(passage.chapterID)?.verses.filter { $0.number >= passage.from && $0.number <= passage.to } ?? []
        return VStack(alignment: .leading, spacing: 12) {
            if verses.isEmpty {
                Text("This passage's text isn't in the app yet.").foregroundStyle(.secondary)
            } else {
                Text(verses.reduce(AttributedString()) { text, verse in
                    var number = AttributedString("\(verse.number) ")
                    number.swiftUI.font = .system(size: 12, weight: .bold)
                    number.swiftUI.foregroundColor = Color.accentColor
                    return text + number + AttributedString(verse.text + " ")
                })
                .font(.scripture(size: 18))
                .lineSpacing(4)
                .textSelection(.enabled)
            }
            Button {
                reader = ReaderTarget(chapterID: passage.chapterID, verse: passage.from)
            } label: {
                Label("Open in Reader", systemImage: "book")
            }
            .buttonStyle(.glass)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
    }

    private func sourceCard(_ source: PathResource) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(source.url?.host() ?? "External source", systemImage: "safari")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(source.title).font(.headline)
            if let perspective = source.note {
                Text(perspective).font(.caption.weight(.semibold)).foregroundStyle(.tint)
            }
            Text("Read it in Safari, then come back and write your response.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let url = source.url {
                Link(destination: url) {
                    Label("Open Reading", systemImage: "arrow.up.right")
                }
                .buttonStyle(.glass)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
    }

    @ViewBuilder
    private var videoCard: some View {
        if let video = item.video {
            VStack(alignment: .leading, spacing: 10) {
                YouTubeEmbed(videoID: video.videoID)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 16))
                if let speaker = video.speaker {
                    Text(speaker).font(.subheadline.weight(.semibold))
                }
                HStack(spacing: 10) {
                    if let transcript = video.transcriptURL {
                        Link(destination: transcript) { Label("Transcript", systemImage: "text.alignleft") }
                            .buttonStyle(.glass)
                    }
                    if let alternativeID = item.alternativeItemID, let alternative = path.item(alternativeID) {
                        NavigationLink {
                            LearningItemView(path: path, item: alternative)
                        } label: {
                            Label("Read Instead", systemImage: "doc.text")
                        }
                        .buttonStyle(.glass)
                    }
                }
                Text("Watching or reading the alternative both complete this item. Either way, write the response below; it earns its XP once.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
        }
    }

    // MARK: Response

    private var responseCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your response").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            Text(item.prompt).font(.headline)
            TextEditor(text: $response)
                .focused($editorFocused)
                .frame(minHeight: 160)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 14))
                .disabled(!unlocked)
                .accessibilityLabel("Your response")
            HStack {
                Text("\(words) words · at least \(ScholarRules.minimumResponseWords)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(words >= ScholarRules.minimumResponseWords ? Feedback.correct : .secondary)
                Spacer()
                if ScholarGrader.isAvailable {
                    Label("Reviewed on device", systemImage: "apple.intelligence")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let reviewNote {
                Label(reviewNote, systemImage: "lightbulb")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !unlocked {
                Label("Finish the earlier course first to complete this item.", systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await submit() }
            } label: {
                HStack {
                    if reviewing { ProgressView().tint(.white) }
                    Text(reviewing ? "Reviewing…" : completion == nil ? "Mark Complete" : "Save Response")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!canSubmit)
            if editing {
                Button("Cancel") {
                    editing = false
                    response = completion?.response ?? ""
                    reviewNote = nil
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
    }

    private func completedCard(_ completion: ItemCompletion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(progress.isAwarded(item) ? "Completed · +\(item.xp) XP" : "Completed", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(Feedback.correct)
            Text(item.prompt).font(.footnote).foregroundStyle(.secondary)
            Text(completion.response).font(.body).textSelection(.enabled)
            if !completion.feedback.isEmpty {
                Label(completion.feedback, systemImage: "apple.intelligence")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Edit Response", systemImage: "pencil") {
                    response = completion.response
                    editing = true
                }
                Spacer()
                Button("Mark Not Done", role: .destructive) {
                    ScholarLedger(context: modelContext).clear(item, in: path)
                    response = completion.response
                }
                .font(.footnote)
            }
            .buttonStyle(.borderless)
            Text("XP is paid once. Editing or unmarking never removes XP you've earned.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
    }

    private func submit() async {
        let text = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ScholarRules.wordCount(text) >= ScholarRules.minimumResponseWords else { return }
        editorFocused = false
        reviewing = true
        let review = await ScholarGrader.review(item: item, response: text)
        reviewing = false
        if let review, !review.meetsPrompt, !flaggedOnce {
            flaggedOnce = true
            withAnimation(.snappy) { reviewNote = review.feedback + " Revise and submit again." }
            return
        }
        ScholarLedger(context: modelContext).complete(item, in: path, response: text, feedback: review?.feedback ?? "")
        reviewNote = nil
        editing = false
        justCompleted += 1
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

/// The official YouTube embedded player. Playback and embedding availability vary by video
/// and region, so every video item also offers a transcript and a reading alternative.
struct YouTubeEmbed: UIViewRepresentable {
    let videoID: String

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.loaded != videoID else { return }
        context.coordinator.loaded = videoID
        let id = videoID.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;height:100%;background:#000}iframe{position:absolute;inset:0;width:100%;height:100%;border:0}</style></head>
        <body><iframe src="https://www.youtube.com/embed/\(id)?playsinline=1&rel=0" title="YouTube video player"
        allow="encrypted-media; picture-in-picture; fullscreen" allowfullscreen></iframe></body></html>
        """
        view.loadHTMLString(html, baseURL: URL(string: "https://www.hearken.app"))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var loaded: String?
    }
}
