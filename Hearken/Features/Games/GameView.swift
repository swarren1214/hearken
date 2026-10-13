import SwiftData
import SwiftUI

enum GameKind: String {
    case daily, chronology, unitCheck, review
}

struct GameRequest: Identifiable {
    let id = UUID()
    let title: String
    let kind: GameKind
    let subjectID: String?
    let questions: [Question]
}

private struct ReaderLink: Identifiable {
    let chapterID: String
    var id: String { chapterID }
}

/// A full-screen multiple-choice game. Correct answers are green with a checkmark,
/// incorrect answers red with an X. Signed-out players can practice, but nothing is saved.
struct GameView: View {
    let request: GameRequest

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AccountService.self) private var account

    @State private var questions: [Question]
    @State private var index = 0
    @State private var picked: Int?
    @State private var results: [Bool] = []
    @State private var xpEarned = 0
    @State private var finished = false
    @State private var readerLink: ReaderLink?
    @State private var showConfetti = false
    @State private var ringProgress = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let mastery = MasteryService()

    /// Scroll target for the explanation card that appears after answering.
    private let feedbackID = "feedback"

    /// Side-by-side rows stack vertically at accessibility text sizes so nothing is squeezed off screen.
    private var feedbackHeaderLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
    }

    private var actionButtonLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
    }

    init(request: GameRequest) {
        self.request = request
        _questions = State(initialValue: request.questions)
    }

    private var current: Question? { questions.indices.contains(index) ? questions[index] : nil }
    private var score: Int { results.filter { $0 }.count }

    var body: some View {
        Group {
            if finished {
                resultsView
            } else if let current {
                questionView(current)
                    .id(index) // Fresh scroll position for each question.
            } else {
                ContentUnavailableView("No questions yet", systemImage: "questionmark.circle", description: Text("Questions for this subject are coming soon."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The header (Close + progress) stays pinned so it's always reachable, whatever the text size.
        .safeAreaInset(edge: .top, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(Color(.systemGroupedBackground))
        }
        .background(Color(.systemGroupedBackground))
        .sensoryFeedback(trigger: picked) { _, newValue in
            guard let newValue, let current else { return nil }
            return newValue == current.answer ? .success : .error
        }
        .overlay {
            ZStack {
                if showConfetti {
                    ConfettiView()
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.4), value: showConfetti)
        }
        .sensoryFeedback(.success, trigger: showConfetti) { _, new in new }
        .sheet(item: $readerLink) { link in
            NavigationStack {
                ReaderView(chapterID: link.chapterID)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done", systemImage: "checkmark") { readerLink = nil }
                        }
                    }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Button("Close", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)

            HStack(spacing: 4) {
                ForEach(questions.indices, id: \.self) { i in
                    ProgressSegment(fill: segmentFill(i), color: segmentColor(i))
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: results)
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: picked)
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: index)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Question \(min(index + 1, questions.count)) of \(questions.count)")

            Text("+\(xpEarned) XP")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .contentTransition(.numericText())
                .foregroundStyle(.tint)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .frame(minHeight: 32)
                .background(.tint.opacity(0.15), in: Capsule())
        }
    }

    /// Answered and current segments are full; the current one turns green or red as soon as an answer is picked.
    private func segmentColor(_ i: Int) -> Color {
        if i < results.count { return results[i] ? Feedback.correct : Feedback.incorrect }
        if i == index && !finished {
            if let picked, let current { return picked == current.answer ? Feedback.correct : Feedback.incorrect }
            return .primary
        }
        return .clear
    }

    private func segmentFill(_ i: Int) -> Double {
        i < results.count || (i == index && !finished) ? 1 : 0
    }

    // MARK: Question

    /// Scrolls, so large accessibility text never pushes the answers or explanation off screen.
    /// After answering, Continue/Read are pinned to the bottom edge and the explanation scrolls into view.
    private func questionView(_ question: Question) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(request.title.uppercased()) · \(index + 1) OF \(questions.count)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(question.prompt)
                            .font(.title2.bold())
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 10) {
                        ForEach(question.options.indices, id: \.self) { option in
                            AnswerButton(text: question.options[option], state: answerState(option, question: question)) {
                                choose(option, question: question)
                            }
                            .disabled(picked != nil)
                        }
                    }

                    if let picked {
                        feedbackCard(correct: picked == question.answer, question: question)
                            .id(feedbackID)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if picked != nil {
                    actionBar(question)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onChange(of: picked) { _, newValue in
                guard newValue != nil else { return }
                // Wait a beat for the card to lay out, then bring it into view.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(80))
                    withAnimation(reduceMotion ? nil : .snappy) {
                        proxy.scrollTo(feedbackID, anchor: .top)
                    }
                }
            }
        }
        .animation(.snappy, value: picked)
    }

    private func answerState(_ option: Int, question: Question) -> AnswerButton.Mark {
        guard let picked else { return .idle }
        if option == question.answer { return .correct }
        if option == picked { return .incorrect }
        return .dimmed
    }

    private func choose(_ option: Int, question: Question) {
        picked = option
        let correct = option == question.answer
        if correct { xpEarned += MasteryConfig.standard.xpPerCorrect }
        mastery.record(questionID: question.id, correct: correct, in: modelContext)
    }

    private func feedbackCard(correct: Bool, question: Question) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            feedbackHeaderLayout {
                Label(correct ? "Correct" : "Not quite", systemImage: correct ? Feedback.correctSymbol : Feedback.incorrectSymbol)
                    .font(.title3.bold())
                    .foregroundStyle(correct ? Feedback.correct : Feedback.incorrect)
                    .symbolEffect(.bounce, value: picked)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                Text(question.reference)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .truncationMode(.middle)
            }
            Text(question.explanation)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
    }

    /// Read / Continue, pinned to the bottom of the screen once a question is answered.
    private func actionBar(_ question: Question) -> some View {
        actionButtonLayout {
            if let chapterID = question.chapterID {
                Button { readerLink = ReaderLink(chapterID: chapterID) } label: {
                    Text("Read")
                        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
            Button {
                advance()
            } label: {
                Text(index == questions.count - 1 ? "See Results" : "Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color(.systemGroupedBackground).ignoresSafeArea(edges: .bottom))
    }

    private func advance() {
        guard let picked, let current else { return }
        results.append(picked == current.answer)
        self.picked = nil
        if index + 1 < questions.count {
            index += 1
        } else {
            finish()
        }
    }

    private func finish() {
        withAnimation { finished = true }
        if !questions.isEmpty && score == questions.count && !reduceMotion {
            showConfetti = true
            Task {
                try? await Task.sleep(for: .seconds(4.5))
                showConfetti = false
            }
        }
        var bonus = 0
        let alreadyDoneToday = request.kind == .daily && dailyAlreadyPlayed()
        if request.kind == .daily && !alreadyDoneToday {
            bonus = MasteryConfig.standard.dailyChallengeBonus
            mastery.award(bonus, reason: "daily", in: modelContext)
        }
        xpEarned += bonus
        modelContext.insert(GameSession(gameType: request.kind.rawValue, subjectID: request.subjectID ?? "", correct: score, total: questions.count, xpEarned: xpEarned))
    }

    private func dailyAlreadyPlayed() -> Bool {
        let daily = GameKind.daily.rawValue
        let start = Calendar.current.startOfDay(for: .now)
        let descriptor = FetchDescriptor<GameSession>(predicate: #Predicate { $0.gameType == daily && $0.playedAt >= start })
        return ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
    }

    private func restart() {
        questions = request.questions.shuffled()
        index = 0
        picked = nil
        results = []
        xpEarned = 0
        showConfetti = false
        ringProgress = 0
        withAnimation { finished = false }
    }

    // MARK: Results

    private var resultsView: some View {
        ScrollView {
            resultsContent
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        // Done / Play Again stay pinned and reachable at any text size.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                Button { dismiss() } label: { Text("Done").frame(maxWidth: .infinity) }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                Button { restart() } label: { Text("Play Again").frame(maxWidth: .infinity) }
                    .buttonStyle(.glass)
                    .controlSize(.large)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Color(.systemGroupedBackground).ignoresSafeArea(edges: .bottom))
        }
    }

    private var resultsContent: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                ProgressRing(progress: ringProgress, lineWidth: 16) {
                    Text("\(score)/\(questions.count)")
                        .font(.largeTitle.bold().monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .padding(.horizontal, 20)
                }
                .frame(width: 150, height: 150)
                .onAppear {
                    let target = questions.isEmpty ? 0 : Double(score) / Double(questions.count)
                    withAnimation(.easeOut(duration: 0.9).delay(0.15)) { ringProgress = target }
                }
                #if DEBUG
                // Testing aid: long-press the score ring to replay the confetti.
                .onLongPressGesture {
                    showConfetti = false
                    Task {
                        try? await Task.sleep(for: .milliseconds(50))
                        showConfetti = true
                    }
                }
                #endif
                Text(score == questions.count ? "Flawless" : score * 2 >= questions.count ? "Nicely done" : "Good start")
                    .font(.title.bold())
                Text("Missed questions come back in Spaced Review.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)

            HStack(spacing: 0) {
                ResultStat(value: "+\(xpEarned)", label: "XP")
                Divider()
                ResultStat(value: "\(score)", label: "Correct")
                Divider()
                ResultStat(value: "\(questions.count - score)", label: "To review")
            }
            .padding(.vertical, 10)
            .frame(minHeight: 64)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
        }
    }
}

/// One segment of the progress bar at the top of a game. Fills from the left when it becomes active.
private struct ProgressSegment: View {
    let fill: Double
    let color: Color

    var body: some View {
        Capsule()
            .fill(Color(.tertiarySystemFill))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(color)
                        .frame(width: proxy.size.width * fill)
                }
            }
            .clipShape(Capsule())
            .frame(height: 6)
    }
}

private struct ResultStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold().monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct AnswerButton: View {
    enum Mark { case idle, correct, incorrect, dimmed }

    let text: String
    let state: Mark
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(text)
                    .font(.body)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                switch state {
                case .correct:
                    Image(systemName: Feedback.correctSymbol)
                        .font(.title2)
                        .foregroundStyle(.white, Feedback.correct)
                        .accessibilityLabel("Correct answer")
                case .incorrect:
                    Image(systemName: Feedback.incorrectSymbol)
                        .font(.title2)
                        .foregroundStyle(.white, Feedback.incorrect)
                        .accessibilityLabel("Your answer, incorrect")
                default:
                    EmptyView()
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(minHeight: 58)
            .background(background, in: .rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(border, lineWidth: 2)
            }
            .opacity(state == .dimmed ? 0.5 : 1)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var background: Color {
        switch state {
        case .correct: Feedback.correct.opacity(0.14)
        case .incorrect: Feedback.incorrect.opacity(0.12)
        default: Color(.secondarySystemGroupedBackground)
        }
    }

    private var border: Color {
        switch state {
        case .correct: Feedback.correct
        case .incorrect: Feedback.incorrect
        default: .clear
        }
    }
}

#Preview {
    GameView(request: GameRequest(title: "Chronology Challenge", kind: .chronology, subjectID: "bofm-history", questions: ContentService().questions(forSubject: "bofm-history")))
        .previewEnvironment()
}
