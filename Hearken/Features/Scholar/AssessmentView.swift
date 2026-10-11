import SwiftData
import SwiftUI

/// A course checkpoint or stage advancement check. Questions can be multiple choice (graded
/// instantly) or short answer (scored 0–2 on device against the answer guide). Every question
/// is worth 2 points; the check passes at its pass percentage. Retakes draw fresh questions
/// from the pool where it allows. A checkpoint pays its XP once; an advancement check pays none.
struct AssessmentView: View {
    let request: AssessmentRequest

    private enum Phase { case intro, answering, scoring, results }

    private struct Answer: Codable {
        var choice: Int?
        var text: String = ""
        var points: Int = 0
        var feedback: String = ""
        var scoredByAI = false
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var previous: [AssessmentAttempt]
    @State private var phase: Phase = .intro
    @State private var questions: [PathQuestion] = []
    @State private var answers: [Answer] = []
    @State private var index = 0
    @State private var scoringError: String?
    @State private var ring = 0.0
    @State private var passedNow = false
    @State private var earnedXP = 0
    @FocusState private var textFocused: Bool

    init(request: AssessmentRequest) {
        self.request = request
        let id = request.assessment.id
        _previous = Query(filter: #Predicate<AssessmentAttempt> { $0.assessmentID == id }, sort: \AssessmentAttempt.attemptedAt, order: .reverse)
    }

    private var pool: [PathQuestion] { request.assessment.questionPool.compactMap { request.path.question($0) } }
    private var needsAI: Bool { pool.contains { $0.kind == .shortAnswer } }
    private var maxPoints: Int { questions.count * PathQuestion.maxPoints }
    private var points: Int { answers.reduce(0) { $0 + $1.points } }
    private var toPass: Int { ScholarRules.pointsToPass(maxPoints: maxPoints, passPercent: request.assessment.passPercent) }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .intro: intro
                case .answering: answering
                case .scoring: scoring
                case .results: results
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", role: .close) { dismiss() }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .sensoryFeedback(.success, trigger: passedNow) { _, new in new }
    }

    // MARK: Intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(request.title).font(.largeTitle.bold()).padding(.top, 12)
            VStack(alignment: .leading, spacing: 10) {
                fact("number.circle", "\(min(request.assessment.questionCount, pool.count)) questions, 2 points each")
                fact("checkmark.seal", "\(request.assessment.passPercent)% to pass")
                fact("arrow.counterclockwise", "Retake any time; XP is paid once")
                if needsAI {
                    fact("apple.intelligence", "Short answers are scored on this device by Apple Intelligence, against the course's answer guide")
                }
                fact("person.badge.shield.checkmark", "Scored on understanding and evidence, never on belief")
            }
            if let last = previous.first {
                Text("Last attempt: \(last.points)/\(last.maxPoints)\(last.passed ? ", passed" : "")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if needsAI && !ScholarGrader.isAvailable {
                Label("This check has short-answer questions, which need Apple Intelligence. Turn it on in Settings › Apple Intelligence & Siri, or use a supported device.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            Button {
                start()
            } label: {
                Text(previous.isEmpty ? "Start" : "Retake").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(pool.isEmpty || (needsAI && !ScholarGrader.isAvailable))
            .padding(.bottom, 12)
        }
    }

    private func fact(_ symbol: String, _ text: String) -> some View {
        Label { Text(text) } icon: { Image(systemName: symbol).foregroundStyle(.tint) }
            .font(.body)
    }

    private func start() {
        // Fresh questions first: anything not in the last attempt, then the rest.
        let recent = Set(previous.first?.questionIDs ?? [])
        let fresh = pool.filter { !recent.contains($0.id) }.shuffled()
        let repeats = pool.filter { recent.contains($0.id) }.shuffled()
        questions = Array((fresh + repeats).prefix(request.assessment.questionCount))
        answers = Array(repeating: Answer(), count: questions.count)
        index = 0
        ring = 0
        scoringError = nil
        passedNow = false
        earnedXP = 0
        withAnimation(.snappy) { phase = .answering }
    }

    // MARK: Answering

    private var answering: some View {
        let question = questions[index]
        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 4) {
                ForEach(questions.indices, id: \.self) { i in
                    Capsule()
                        .fill(i <= index ? Color.accentColor : Color(.tertiarySystemFill))
                        .frame(height: 6)
                }
            }
            .padding(.top, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Question \(index + 1) of \(questions.count)")

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(index + 1) OF \(questions.count) · \(question.kind == .multipleChoice ? "MULTIPLE CHOICE" : "SHORT ANSWER")")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(question.prompt)
                        .font(.title3.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    if question.kind == .multipleChoice {
                        VStack(spacing: 10) {
                            ForEach(Array((question.options ?? []).enumerated()), id: \.offset) { option, text in
                                choiceButton(text, selected: answers[index].choice == option) {
                                    answers[index].choice = option
                                }
                            }
                        }
                    } else {
                        TextEditor(text: $answers[index].text)
                            .focused($textFocused)
                            .frame(minHeight: 180)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
                            .accessibilityLabel("Your answer")
                        Text("A few sentences. Name a source where it helps.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)

            HStack(spacing: 10) {
                if index > 0 {
                    Button { index -= 1 } label: { Text("Back").frame(maxWidth: .infinity) }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                }
                Button {
                    textFocused = false
                    if index + 1 < questions.count {
                        index += 1
                    } else {
                        Task { await score() }
                    }
                } label: {
                    Text(index + 1 < questions.count ? "Next" : "Submit").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(!isAnswered(index))
            }
            .padding(.bottom, 12)
        }
    }

    private func isAnswered(_ i: Int) -> Bool {
        questions[i].kind == .multipleChoice ? answers[i].choice != nil : !answers[i].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func choiceButton(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                Text(text).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Scoring

    private var scoring: some View {
        VStack(spacing: 16) {
            Spacer()
            if let scoringError {
                Label(scoringError, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                Button("Try Again") { Task { await score() } }.buttonStyle(.glassProminent)
            } else {
                ProgressView().controlSize(.large)
                Text("Scoring your answers…").font(.headline)
                Text("Short answers are scored on this device.").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func score() async {
        withAnimation(.snappy) { phase = .scoring }
        scoringError = nil
        for i in questions.indices {
            let question = questions[i]
            switch question.kind {
            case .multipleChoice:
                answers[i].points = answers[i].choice == question.answer ? PathQuestion.maxPoints : 0
                answers[i].feedback = question.explanation ?? ""
            case .shortAnswer:
                do {
                    let result = try await ScholarGrader.score(question: question, answer: answers[i].text)
                    answers[i].points = result.points
                    answers[i].feedback = result.feedback
                    answers[i].scoredByAI = true
                } catch {
                    scoringError = "Apple Intelligence couldn't score your answers just now. Your answers are kept; try again."
                    return
                }
            }
        }
        let passed = points >= toPass
        let wasPassed = previous.contains { $0.passed }
        let json = (try? JSONEncoder().encode(answers)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let attempt = AssessmentAttempt(
            assessmentID: request.assessment.id,
            subjectID: request.path.subjectID,
            kind: request.kind,
            questionIDs: questions.map(\.id),
            points: points,
            maxPoints: maxPoints,
            passed: passed,
            aiScored: answers.contains { $0.scoredByAI },
            answersJSON: json
        )
        ScholarLedger(context: modelContext).record(attempt, in: request.path)
        earnedXP = passed && !wasPassed && request.kind == "checkpoint" ? ScholarRules.checkpointXP : 0
        passedNow = passed
        withAnimation(.snappy) { phase = .results }
    }

    // MARK: Results

    private var results: some View {
        ScrollView {
            VStack(spacing: 16) {
                ZStack {
                    Circle().stroke(Color(.tertiarySystemFill), lineWidth: 14)
                    Circle()
                        .trim(from: 0, to: ring)
                        .stroke(passedNow ? Feedback.correct : Feedback.incorrect, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    // The pass line.
                    Capsule()
                        .fill(Color.primary)
                        .frame(width: 3, height: 22)
                        .offset(y: -72)
                        .rotationEffect(.degrees(Double(request.assessment.passPercent) * 3.6))
                    VStack(spacing: 0) {
                        Text("\(points)").font(.system(size: 44, weight: .bold)).monospacedDigit()
                        + Text("/\(maxPoints)").font(.title2.weight(.semibold)).foregroundStyle(.secondary)
                        Text("\(Int((Double(points) / Double(max(maxPoints, 1)) * 100).rounded()))%").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 158, height: 158)
                .padding(.top, 16)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.9).delay(0.15)) { ring = Double(points) / Double(max(maxPoints, 1)) }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(points) of \(maxPoints) points. \(passedNow ? "Passed" : "Not passed yet"). \(toPass) needed to pass.")

                HStack(spacing: 8) {
                    Label(passedNow ? "Passed" : "Not yet", systemImage: passedNow ? Feedback.correctSymbol : "arrow.counterclockwise")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(passedNow ? Feedback.correct : .secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background((passedNow ? Feedback.correct : Color.secondary).opacity(0.14), in: Capsule())
                    if earnedXP > 0 {
                        Text("+\(earnedXP) XP")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.tint)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(.tint.opacity(0.14), in: Capsule())
                    }
                }
                Text(passedNow ? "The tick on the ring marks the \(request.assessment.passPercent)% pass line." : "You need \(toPass) of \(maxPoints). Review the feedback below and retake when you're ready.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                ForEach(questions.indices, id: \.self) { i in reviewCard(i) }

                if answers.contains(where: \.scoredByAI) {
                    Text("Short answers were scored on this device by Apple Intelligence against the course's answer guide. Scores can be imperfect; retakes are always open.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 10) {
                    Button { dismiss() } label: { Text("Done").frame(maxWidth: .infinity) }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                    Button { start() } label: { Text("Retake").frame(maxWidth: .infinity) }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                }
                .padding(.bottom, 16)
            }
        }
    }

    private func reviewCard(_ i: Int) -> some View {
        let question = questions[i]
        let answer = answers[i]
        let full = answer.points == PathQuestion.maxPoints
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(i + 1). \(question.prompt)").font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text("\(answer.points)/\(PathQuestion.maxPoints)")
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(full ? Feedback.correct : answer.points == 0 ? Feedback.incorrect : .orange)
            }
            if question.kind == .multipleChoice, let options = question.options {
                if let choice = answer.choice, choice != question.answer, options.indices.contains(choice) {
                    Label("Your answer: \(options[choice])", systemImage: Feedback.incorrectSymbol).foregroundStyle(Feedback.incorrect).font(.footnote)
                }
                if let correct = question.answer, options.indices.contains(correct) {
                    Label(options[correct], systemImage: Feedback.correctSymbol).foregroundStyle(Feedback.correct).font(.footnote)
                }
            } else {
                // The answer guide stays private so retakes still test understanding.
                Text(answer.text).font(.footnote).foregroundStyle(.secondary)
            }
            if !answer.feedback.isEmpty {
                Text(answer.feedback).font(.footnote)
            }
            if let reference = question.reference {
                Text(reference).font(.caption).foregroundStyle(.tint)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
    }
}
