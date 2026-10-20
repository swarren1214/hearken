import SafariServices
import SwiftData
import SwiftUI

// The screens for v2 module items, which are completed by passing a check:
// article (section checks), reading (focus questions, then a quiz), practice (a matching set),
// module quiz, and essay (rubric-scored on device). LearningItemView sends v2 items here.

struct StudyItemView: View {
    let path: ScholarPathFile
    let item: PathItem
    let progress: ScholarProgress

    private var course: PathCourse? { path.stages.flatMap(\.courses).first { $0.allItems.contains { $0.id == item.id } } }
    private var unlocked: Bool { course.map { progress.isUnlocked(item, in: $0) } ?? false }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                StudyHeader(item: item, progress: progress)
                if !unlocked {
                    Label(lockReason, systemImage: "lock.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
                }
                switch item.kind {
                case .article: ArticleBody(path: path, item: item, progress: progress, unlocked: unlocked)
                case .reading: ReadingBody(path: path, item: item, progress: progress, unlocked: unlocked)
                case .practice: PracticeBody(path: path, item: item, progress: progress, unlocked: unlocked)
                case .quiz: ModuleQuizBody(path: path, item: item, progress: progress, unlocked: unlocked)
                case .essay: EssayBody(path: path, item: item, progress: progress, unlocked: unlocked)
                case .lesson, .video: EmptyView()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(item.kindName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var lockReason: String {
        guard let course, progress.isUnlocked(course) else { return "Finish the earlier course first. You can look around, but this can't be completed yet." }
        return "Finish the step before this one in the module first."
    }
}

private struct StudyHeader: View {
    let item: PathItem
    let progress: ScholarProgress

    var body: some View {
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
}

/// The card a finished item shows.
private struct DoneCard: View {
    let text: String
    let xp: Int?

    var body: some View {
        Label(xp.map { "\(text) · +\($0) XP" } ?? text, systemImage: Feedback.correctSymbol)
            .font(.headline)
            .foregroundStyle(Feedback.correct)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Feedback.correct.opacity(0.1), in: .rect(cornerRadius: 18))
    }
}

// MARK: - Article

private struct ArticleBody: View {
    let path: ScholarPathFile
    let item: PathItem
    let progress: ScholarProgress
    let unlocked: Bool

    @Environment(\.modelContext) private var modelContext
    @State private var passed: Set<String> = []
    @State private var justCompleted = 0

    private struct Section: Identifiable {
        let id: Int
        let heading: String
        let paragraphs: [String]
    }

    /// Splits the article's Markdown at its "## " headings; the "# " title is dropped (the header shows it).
    private var sections: [Section] {
        var result: [Section] = []
        var heading = ""
        var lines: [String] = []
        func flush() {
            let paragraphs = lines.joined(separator: "\n").components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if !heading.isEmpty || !paragraphs.isEmpty { result.append(Section(id: result.count, heading: heading, paragraphs: paragraphs)) }
            lines = []
        }
        for line in (item.body ?? "").components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                flush()
                heading = String(line.dropFirst(3))
            } else if line.hasPrefix("# ") {
                continue
            } else {
                lines.append(line)
            }
        }
        flush()
        return result
    }

    private var checkIDs: [String] { (item.sectionChecks ?? []).flatMap(\.questionIDs) }
    private var done: Bool { progress.isDone(item) }
    private var remaining: Int { checkIDs.filter { !passed.contains($0) }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !done && !checkIDs.isEmpty {
                Text("\(checkIDs.count) quick checks along the way. Answer each one to finish the article.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 12) {
                    if !section.heading.isEmpty {
                        Text(section.heading).font(.title3.bold()).accessibilityAddTraits(.isHeader)
                    }
                    ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(markdown(paragraph))
                            .font(.body)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(checks(for: section.heading), id: \.id) { question in
                        InlineCheckView(question: question, isPassed: done || passed.contains(question.id)) {
                            passed.insert(question.id)
                        }
                        .disabled(!unlocked)
                    }
                }
            }
            if done {
                DoneCard(text: "Article complete", xp: progress.isAwarded(item) ? item.xp : nil)
            } else {
                Button {
                    ScholarLedger(context: modelContext).complete(item, in: path, response: "Passed \(checkIDs.count) section checks", feedback: "")
                    justCompleted += 1
                } label: {
                    Text(remaining == 0 ? "Finish Article" : "\(remaining) check\(remaining == 1 ? "" : "s") to go").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(!unlocked || remaining > 0)
            }
        }
        .sensoryFeedback(.success, trigger: justCompleted)
    }

    private func checks(for heading: String) -> [BankQuestion] {
        (item.sectionChecks ?? []).filter { $0.section == heading }.flatMap(\.questionIDs).compactMap { QuestionBank.shared.question($0) }
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

// MARK: - Reading

private struct ReaderTarget: Identifiable {
    let chapterID: String
    let verse: Int
    var id: String { "\(chapterID):\(verse)" }
}

private struct ReadingBody: View {
    let path: ScholarPathFile
    let item: PathItem
    let progress: ScholarProgress
    let unlocked: Bool

    @Environment(ContentService.self) private var content
    @State private var reader: ReaderTarget?
    @State private var safari: URL?
    @State private var quiz: QuizRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let focus = item.focusQuestions, !focus.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Look for").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(focus, id: \.self) { question in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "eye").font(.footnote).foregroundStyle(.tint).accessibilityHidden(true)
                            Text(question).font(.subheadline)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
            }

            ForEach(item.allPassages, id: \.self) { passage in passageCard(passage) }
            if let source = item.source { sourceCard(source) }

            if let itemQuiz = item.quiz {
                if progress.isDone(item) {
                    DoneCard(text: "Reading quiz passed", xp: progress.isAwarded(item) ? item.xp : nil)
                }
                let start = {
                    quiz = QuizRequest(title: "Reading Quiz", item: item, quiz: itemQuiz, path: path)
                }
                let label = VStack(spacing: 2) {
                    Text(progress.isDone(item) ? "Retake the Reading Quiz" : "Take the Reading Quiz")
                    Text("\(itemQuiz.questionCount) questions · \(itemQuiz.passCount) to pass").font(.caption).opacity(0.8)
                }
                .frame(maxWidth: .infinity)
                if progress.isDone(item) {
                    Button(action: start) { label }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                        .disabled(!unlocked)
                } else {
                    Button(action: start) { label }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .disabled(!unlocked)
                }
            }
        }
        .sheet(item: $reader) { target in
            NavigationStack {
                ReaderView(chapterID: target.chapterID, verse: target.verse)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            SheetDoneButton { reader = nil }
                        }
                    }
            }
        }
        .sheet(item: Binding(get: { safari.map(IdentifiedURL.init) }, set: { safari = $0?.url })) { link in
            SafariSheet(url: link.url).ignoresSafeArea()
        }
        .fullScreenCover(item: $quiz) { QuizRunnerView(request: $0) }
    }

    private func passageCard(_ passage: PathPassage) -> some View {
        let chapter = content.chapter(passage.chapterID)
        let verses = chapter?.verses.filter { $0.number >= passage.from && $0.number <= passage.to } ?? []
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
            Label(source.url?.host() ?? "Source", systemImage: "safari")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(source.title).font(.headline)
            if let note = source.note {
                Text(note).font(.caption.weight(.semibold)).foregroundStyle(.tint)
            }
            Text("Read the whole page, then take the quiz.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let url = source.url {
                Button {
                    safari = url
                } label: {
                    Label("Open Reading", systemImage: "arrow.up.right")
                }
                .buttonStyle(.glass)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
    }
}

private struct IdentifiedURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// An in-app browser for a linked source.
struct SafariSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

// MARK: - Practice

private struct PracticeBody: View {
    let path: ScholarPathFile
    let item: PathItem
    let progress: ScholarProgress
    let unlocked: Bool

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let id = item.questionID, let question = QuestionBank.shared.question(id) {
                Text("Pair every item, then check. Wrong pairs are cleared so you can fix them.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                InlineCheckView(question: question, isPassed: progress.isDone(item)) {
                    ScholarLedger(context: modelContext).complete(item, in: path, response: "Matched every pair", feedback: "")
                }
                .disabled(!unlocked)
                if progress.isDone(item) {
                    DoneCard(text: "Practice complete", xp: progress.isAwarded(item) ? item.xp : nil)
                }
            } else {
                Text("This practice set isn't available yet.").foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Module quiz

private struct ModuleQuizBody: View {
    let path: ScholarPathFile
    let item: PathItem
    let progress: ScholarProgress
    let unlocked: Bool

    @State private var quiz: QuizRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let itemQuiz = item.quiz {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Questions from the whole module: the article, every reading and the practice set. Each retake draws a new mix.")
                        .font(.subheadline)
                    Label("\(itemQuiz.questionCount) questions, \(itemQuiz.passCount) to pass", systemImage: "number.circle")
                    Label("Drawn from \(itemQuiz.questionPool.count) in this module", systemImage: "square.stack.3d.up")
                }
                .font(.subheadline)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
                if progress.isDone(item) {
                    DoneCard(text: "Module quiz passed", xp: progress.isAwarded(item) ? item.xp : nil)
                }
                Button {
                    quiz = QuizRequest(title: "Module Quiz", item: item, quiz: itemQuiz, path: path)
                } label: {
                    Text(progress.isDone(item) ? "Retake" : "Start the Quiz").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(!unlocked)
            }
        }
        .fullScreenCover(item: $quiz) { QuizRunnerView(request: $0) }
    }
}

// MARK: - Essay

private struct EssayBody: View {
    let path: ScholarPathFile
    let item: PathItem
    let progress: ScholarProgress
    let unlocked: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(ContentService.self) private var content

    var body: some View {
        if let essay = item.essay {
            EssayWorkspace(path: path, assessmentID: item.id, essay: essay, unlocked: unlocked, isComplete: progress.isDone(item),
                           sources: { EssaySources.text(for: path, near: item.id, content: content) }) { draft, note in
                ScholarLedger(context: modelContext).complete(item, in: path, response: draft, feedback: note)
            }
            if progress.isDone(item) {
                DoneCard(text: "Essay complete", xp: progress.isAwarded(item) ? item.xp : nil)
            }
        }
    }
}

/// The scripture a module (or a whole course) assigns, as text for the essay scorer.
enum EssaySources {
    @MainActor
    static func text(for path: ScholarPathFile, near itemID: String, content: ContentService) -> String {
        guard let module = path.stages.flatMap(\.courses).flatMap(\.modules).first(where: { $0.items.contains { $0.id == itemID } }) else { return "" }
        return text(for: [module], content: content)
    }

    @MainActor
    static func text(for modules: [PathModule], content: ContentService, limit: Int = 12_000) -> String {
        var parts: [String] = []
        for module in modules {
            for reading in module.items where reading.kind == .reading {
                for passage in reading.allPassages {
                    let verses = content.chapter(passage.chapterID)?.verses.filter { $0.number >= passage.from && $0.number <= passage.to } ?? []
                    if !verses.isEmpty {
                        parts.append("\(reading.title): " + verses.map { "\($0.number) \($0.text)" }.joined(separator: " "))
                    }
                }
            }
        }
        // Keep the request within the on-device model's context.
        return String(parts.joined(separator: "\n").prefix(limit))
    }
}

/// Write, score and revise an essay. Every draft is kept as an attempt under `assessmentID`.
/// `onComplete` runs once: on a pass, after the last allowed draft, or on a device that can't score.
struct EssayWorkspace: View {
    let path: ScholarPathFile
    let assessmentID: String
    let essay: PathEssay
    let unlocked: Bool
    let isComplete: Bool
    let sources: () -> String
    let onComplete: (_ draft: String, _ note: String) -> Void

    private struct Draft: Codable {
        let promptID: String
        let text: String
        let result: ScoredEssay?
    }

    @Environment(\.modelContext) private var modelContext
    @Query private var attempts: [AssessmentAttempt]
    @State private var promptID: String?
    @State private var text = ""
    @State private var scoring = false
    @State private var error: String?
    @State private var result: ScoredEssay?
    @State private var justCompleted = 0
    @FocusState private var editorFocused: Bool

    init(path: ScholarPathFile, assessmentID: String, essay: PathEssay, unlocked: Bool, isComplete: Bool, sources: @escaping () -> String, onComplete: @escaping (_ draft: String, _ note: String) -> Void) {
        self.path = path
        self.assessmentID = assessmentID
        self.essay = essay
        self.unlocked = unlocked
        self.isComplete = isComplete
        self.sources = sources
        self.onComplete = onComplete
        let id = assessmentID
        _attempts = Query(filter: #Predicate<AssessmentAttempt> { $0.assessmentID == id }, sort: \AssessmentAttempt.attemptedAt, order: .reverse)
    }

    private var prompt: PathEssay.Prompt? { essay.prompts.first { $0.id == promptID } }
    private var words: Int { ScholarRules.wordCount(text) }
    private var drafts: Int { attempts.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            promptPicker
            rubricCard
            editor
            if let result { resultCard(result) }
        }
        .sensoryFeedback(.success, trigger: justCompleted)
        .onAppear(perform: restore)
    }

    private var promptPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(essay.prompts.count == 1 ? "Prompt" : "Choose a prompt").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(essay.prompts) { option in
                let selected = option.id == promptID
                Button {
                    promptID = option.id
                    result = nil
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(selected ? Color.accentColor : .secondary)
                        Text(option.prompt).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var rubricCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How it's scored").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(essay.rubric) { criterion in
                VStack(alignment: .leading, spacing: 2) {
                    Text(criterion.title).font(.subheadline.weight(.semibold))
                    Text(criterion.full).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Text("Each criterion is scored 0–2. Pass with \(essay.pointsToPass) of \(essay.rubric.count * 2) and no zero. Revise as often as you like; after \(essay.revisionsBeforeCompletion) scored drafts the essay counts as complete either way.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }

    private var editor: some View {
        let inRange = words >= essay.minWords && words <= essay.maxWords
        return VStack(alignment: .leading, spacing: 10) {
            TextEditor(text: $text)
                .focused($editorFocused)
                .frame(minHeight: 220)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
                .disabled(!unlocked)
                .accessibilityLabel("Your essay")
            HStack {
                Text("\(words) words · \(essay.minWords)–\(essay.maxWords)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(inRange ? Feedback.correct : .secondary)
                Spacer()
                Label(ScholarGrader.isAvailable ? "Scored on device" : "Self-check", systemImage: ScholarGrader.isAvailable ? "apple.intelligence" : "checklist")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
            }
            Button {
                Task { await submit() }
            } label: {
                HStack {
                    if scoring { ProgressView().tint(.white) }
                    Text(scoring ? "Scoring…" : ScholarGrader.isAvailable ? "Submit for Scoring" : "Submit")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!unlocked || prompt == nil || !inRange || scoring)
            if drafts > 0 {
                Text("\(drafts) draft\(drafts == 1 ? "" : "s") submitted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func resultCard(_ result: ScoredEssay) -> some View {
        let passed = result.passes(essay)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(passed ? "Passed" : "Not yet").font(.title3.bold()).foregroundStyle(passed ? Feedback.correct : .orange)
                Spacer()
                Text("\(result.total)/\(essay.rubric.count * 2)").font(.title3.bold()).monospacedDigit()
            }
            ForEach(essay.rubric) { criterion in
                if let score = result.criteria.first(where: { $0.id == criterion.id }) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(criterion.title).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(score.points)/2").font(.subheadline.weight(.semibold)).monospacedDigit()
                                .foregroundStyle(score.points == 2 ? Feedback.correct : score.points == 1 ? Color.orange : Feedback.incorrect)
                        }
                        Text(score.points == 2 ? criterion.full : score.points == 1 ? criterion.partial : criterion.none)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if !score.evidence.isEmpty {
                            Text("“\(score.evidence)”").font(.footnote).italic()
                        }
                    }
                }
            }
            Label(result.suggestion, systemImage: "lightbulb")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Text("Scored automatically on this device. If a score seems wrong, revise and submit again.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }

    private func restore() {
        guard promptID == nil else { return }
        if let last = attempts.first, let data = last.answersJSON.data(using: .utf8), let draft = try? JSONDecoder().decode(Draft.self, from: data) {
            promptID = draft.promptID
            text = draft.text
            result = draft.result
        } else {
            promptID = essay.prompts.first?.id
        }
    }

    private func submit() async {
        guard let prompt else { return }
        editorFocused = false
        error = nil
        let draft = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var scored: ScoredEssay?
        if ScholarGrader.isAvailable {
            scoring = true
            do {
                scored = try await ScholarGrader.score(essay: essay, prompt: prompt, text: draft, sources: sources())
            } catch {
                self.error = "Couldn't score the essay just now. Try again in a moment."
                scoring = false
                return
            }
            scoring = false
        }
        let passed = scored?.passes(essay) ?? false
        let json = (try? JSONEncoder().encode(Draft(promptID: prompt.id, text: draft, result: scored))).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        ScholarLedger(context: modelContext).record(AssessmentAttempt(assessmentID: assessmentID, subjectID: path.subjectID, kind: "essay", questionIDs: [prompt.id], points: scored?.total ?? 0, maxPoints: essay.rubric.count * 2, passed: passed, aiScored: scored != nil, answersJSON: json), in: path)
        withAnimation(.snappy) { result = scored }
        let draftsNow = drafts + 1
        if passed || draftsNow >= essay.revisionsBeforeCompletion || scored == nil, !isComplete {
            let note = passed ? "Passed \(scored?.total ?? 0)/\(essay.rubric.count * 2)" : scored == nil ? "Self-checked; not scored" : "Completed after \(draftsNow) drafts without a pass"
            onComplete(draft, note)
            justCompleted += 1
        }
    }
}
