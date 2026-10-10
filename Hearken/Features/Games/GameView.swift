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

    private let mastery = MasteryService()

    init(request: GameRequest) {
        self.request = request
        _questions = State(initialValue: request.questions)
    }

    private var current: Question? { questions.indices.contains(index) ? questions[index] : nil }
    private var score: Int { results.filter { $0 }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            if finished {
                resultsView
            } else if let current {
                questionView(current)
            } else {
                ContentUnavailableView("No questions yet", systemImage: "questionmark.circle", description: Text("Questions for this subject are coming soon."))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 16)
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
                .padding(.horizontal, 10)
                .frame(height: 32)
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

    private func questionView(_ question: Question) -> some View {
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

            Spacer(minLength: 0)

            if let picked {
                feedbackCard(correct: picked == question.answer, question: question)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
            HStack(alignment: .firstTextBaseline) {
                Label(correct ? "Correct" : "Not quite", systemImage: correct ? Feedback.correctSymbol : Feedback.incorrectSymbol)
                    .font(.title3.bold())
                    .foregroundStyle(correct ? Feedback.correct : Feedback.incorrect)
                    .symbolEffect(.bounce, value: picked)
                Spacer()
                Text(question.reference).font(.footnote).foregroundStyle(.secondary)
            }
            Text(question.explanation)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if let chapterID = question.chapterID {
                    Button("Read") { readerLink = ReaderLink(chapterID: chapterID) }
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
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
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
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                ProgressRing(progress: ringProgress, lineWidth: 16) {
                    Text("\(score)/\(questions.count)").font(.largeTitle.bold().monospacedDigit())
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
            .frame(height: 64)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))

            Spacer()

            VStack(spacing: 10) {
                Button { dismiss() } label: { Text("Done").frame(maxWidth: .infinity) }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                Button { restart() } label: { Text("Play Again").frame(maxWidth: .infinity) }
                    .buttonStyle(.glass)
                    .controlSize(.large)
            }
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
