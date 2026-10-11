import SwiftData
import SwiftUI

// Objective questions for v2 modules: one view per question (multiple choice, true/false,
// matching), an inline check for articles and practice (feedback and retries), and the scored
// quiz runner for reading quizzes and module quizzes.

/// The display order of a question's options, or a matching set's two lists, fixed for one
/// attempt. Multiple-choice options and both matching lists are shuffled independently;
/// true/false keeps True before False.
struct QuestionLayout: Hashable {
    let optionOrder: [String]
    let leftOrder: [String]
    let rightOrder: [String]

    init(_ question: BankQuestion) {
        switch question.type {
        case .multipleChoice:
            optionOrder = (question.options ?? []).map(\.id).shuffled()
            leftOrder = []
            rightOrder = []
        case .trueFalse:
            optionOrder = (question.options ?? []).map(\.id)
            leftOrder = []
            rightOrder = []
        case .matching:
            optionOrder = []
            leftOrder = (question.leftItems ?? []).map(\.id).shuffled()
            rightOrder = (question.rightItems ?? []).map(\.id).shuffled()
        }
    }
}

// MARK: - One question

struct BankQuestionView: View {
    let question: BankQuestion
    let layout: QuestionLayout
    @Binding var answer: BankAnswer
    /// Mark right and wrong answers.
    var reveal = false
    var disabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title = question.title {
                Text(title).font(.headline)
            }
            Text(question.prompt)
                .font(question.type == .matching ? .body : .title3.bold())
                .fixedSize(horizontal: false, vertical: true)
            if let instructions = question.instructions {
                Text(instructions).font(.footnote).foregroundStyle(.secondary)
            }
            switch question.type {
            case .multipleChoice, .trueFalse: choices
            case .matching: matching
            }
        }
    }

    // MARK: Choices

    private var choices: some View {
        let options = Dictionary(uniqueKeysWithValues: (question.options ?? []).map { ($0.id, $0.text) })
        return VStack(spacing: 10) {
            ForEach(layout.optionOrder, id: \.self) { id in
                choiceButton(id: id, text: options[id] ?? "")
            }
        }
    }

    private func choiceButton(id: String, text: String) -> some View {
        let selected = answer.optionID == id
        let isKey = id == question.correctOptionID
        let tint: Color? = reveal ? (isKey ? Feedback.correct : selected ? Feedback.incorrect : nil) : (selected ? Color.accentColor : nil)
        let symbol = reveal ? (isKey ? Feedback.correctSymbol : selected ? Feedback.incorrectSymbol : "circle") : (selected ? "largecircle.fill.circle" : "circle")
        return Button {
            answer.optionID = id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .foregroundStyle(tint ?? .secondary)
                Text(text).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 56)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(tint ?? .clear, lineWidth: 2))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(disabled || reveal)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(reveal ? (isKey ? "Correct answer" : selected ? "Your answer, incorrect" : "") : "")
    }

    // MARK: Matching

    private var matching: some View {
        let left = Dictionary(uniqueKeysWithValues: (question.leftItems ?? []).map { ($0.id, $0.text) })
        let right = Dictionary(uniqueKeysWithValues: (question.rightItems ?? []).map { ($0.id, $0.text) })
        let key = question.answerKey
        return VStack(spacing: 10) {
            ForEach(layout.leftOrder, id: \.self) { leftID in
                let chosen = answer.pairs[leftID]
                let correct = chosen != nil && chosen == key[leftID]
                VStack(alignment: .leading, spacing: 10) {
                    Text(left[leftID] ?? "").font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    CheckMenu(layout.rightOrder.map { rightID in
                        CheckMenuItem.choice(right[rightID] ?? "", isSelected: chosen == rightID) { pair(leftID, rightID) }
                    }) {
                        HStack(spacing: 8) {
                            Text(chosen.flatMap { right[$0] } ?? "Choose a match")
                                .foregroundStyle(chosen == nil ? Color.accentColor : .primary)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: reveal ? (correct ? Feedback.correctSymbol : Feedback.incorrectSymbol) : "chevron.up.chevron.down")
                                .foregroundStyle(reveal ? (correct ? Feedback.correct : Feedback.incorrect) : .secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 12))
                    }
                    .disabled(disabled || (reveal && correct))
                    .accessibilityLabel("Match for \(left[leftID] ?? "")")
                    .accessibilityValue(chosen.flatMap { right[$0] } ?? "None chosen")
                    if reveal, !correct, let answerID = key[leftID] {
                        Text("Matches: \(right[answerID] ?? "")")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(reveal ? (correct ? Feedback.correct : Feedback.incorrect) : .clear, lineWidth: 2))
            }
        }
    }

    /// One-to-one: choosing a right item already used elsewhere moves it here.
    private func pair(_ leftID: String, _ rightID: String) {
        for (other, used) in answer.pairs where used == rightID && other != leftID {
            answer.pairs[other] = nil
        }
        answer.pairs[leftID] = rightID
    }
}

// MARK: - Inline check (articles and practice)

/// A question answered in place, with immediate feedback and unlimited retries. A wrong
/// matching set marks which pairs are wrong so they can be fixed.
struct InlineCheckView: View {
    let question: BankQuestion
    /// Already answered correctly (earlier, or the item is complete).
    let isPassed: Bool
    let onCorrect: () -> Void

    @State private var layout: QuestionLayout
    @State private var answer = BankAnswer()
    @State private var result: Bool?
    @State private var misses = 0

    init(question: BankQuestion, isPassed: Bool, onCorrect: @escaping () -> Void) {
        self.question = question
        self.isPassed = isPassed
        self.onCorrect = onCorrect
        _layout = State(initialValue: QuestionLayout(question))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(isPassed ? "Check · done" : "Check yourself", systemImage: isPassed ? Feedback.correctSymbol : "questionmark.circle")
                .font(.caption.weight(.bold))
                .foregroundStyle(isPassed ? Feedback.correct : Color.accentColor)
            BankQuestionView(question: question, layout: layout, answer: $answer, reveal: result == true || isPassed, disabled: isPassed)
            if isPassed || result == true {
                Text(question.explanation).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                if result == false {
                    Label(misses >= 2 ? question.explanation : question.type == .matching ? "Not quite. Fix the pairs that aren't right yet." : "Not quite. Look back at the section and try again.", systemImage: "arrow.uturn.backward.circle")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Check Answer") { check() }
                    .buttonStyle(.glassProminent)
                    .disabled(!answer.isComplete(for: question))
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground).opacity(0.6), in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.accentColor.opacity(isPassed ? 0 : 0.35), lineWidth: 1.5))
        .sensoryFeedback(trigger: result) { _, new in
            switch new {
            case true?: .success
            case false?: .error
            case nil: nil
            }
        }
        // A new choice clears "not quite". A matching set keeps it until the next check,
        // since the wrong pairs were just cleared for fixing.
        .onChange(of: answer) { _, _ in if result == false && question.type != .matching { result = nil } }
    }

    private func check() {
        let correct = answer.isCorrect(for: question)
        withAnimation(.snappy) { result = correct }
        if correct {
            onCorrect()
        } else {
            misses += 1
            if question.type == .matching {
                // Keep the right pairs; clear the wrong ones.
                let key = question.answerKey
                answer.pairs = answer.pairs.filter { key[$0.key] == $0.value }
                result = false
            }
        }
    }
}

// MARK: - Scored quiz

/// What a scored quiz is, and where its result goes: a quiz item (passing completes it and
/// pays its XP) or the objective part of a checkpoint or exam (recorded; CheckpointView pays).
struct QuizRequest: Identifiable {
    let id = UUID()
    let title: String
    let item: PathItem?
    let quiz: PathQuiz
    let path: ScholarPathFile
    /// The attempt's assessment ID and kind.
    let assessmentID: String
    let kind: String

    init(title: String, item: PathItem, quiz: PathQuiz, path: ScholarPathFile) {
        self.title = title
        self.item = item
        self.quiz = quiz
        self.path = path
        assessmentID = item.id
        kind = "quiz"
    }

    init(title: String, assessmentID: String, kind: String, quiz: PathQuiz, path: ScholarPathFile) {
        self.title = title
        item = nil
        self.quiz = quiz
        self.path = path
        self.assessmentID = assessmentID
        self.kind = kind
    }
}

/// A reading quiz or module quiz: questions one at a time, then the score, every question with
/// its explanation, and a retake that draws fresh questions where the pool allows. Passing
/// completes the item and pays its XP once.
struct QuizRunnerView: View {
    let request: QuizRequest

    private enum Phase { case intro, answering, results }

    private struct Record: Codable {
        let questionID: String
        let revision: Int
        let answer: BankAnswer
        let correct: Bool
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var previous: [AssessmentAttempt]
    @State private var phase: Phase = .intro
    @State private var questions: [BankQuestion] = []
    @State private var layouts: [QuestionLayout] = []
    @State private var answers: [BankAnswer] = []
    @State private var index = 0
    @State private var score = 0
    @State private var passMark = 0
    @State private var passedNow = false
    @State private var earnedXP = 0

    init(request: QuizRequest) {
        self.request = request
        let id = request.assessmentID
        _previous = Query(filter: #Predicate<AssessmentAttempt> { $0.assessmentID == id }, sort: \AssessmentAttempt.attemptedAt, order: .reverse)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .intro: intro
                case .answering: answering
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
        let quiz = request.quiz
        let typeNote = quiz.maxMatching.map { $0 > 0 ? "Multiple choice, true/false and matching" : "Multiple choice and true/false" } ?? "Multiple choice and true/false"
        return VStack(alignment: .leading, spacing: 18) {
            Text(request.title).font(.largeTitle.bold()).padding(.top, 12)
            VStack(alignment: .leading, spacing: 10) {
                fact("number.circle", "\(quiz.questionCount) questions, \(quiz.passCount) to pass")
                fact("list.bullet", typeNote)
                if (quiz.maxMatching ?? 0) > 0 {
                    fact("square.on.square.dashed", "A matching set counts as one question and needs every pair right")
                }
                fact("text.bubble", "Explanations for every question after you submit")
                fact("arrow.counterclockwise", "Retake any time with new questions; XP is paid once")
            }
            if let last = previous.first {
                Text("Last attempt: \(last.points)/\(last.maxPoints)\(last.passed ? ", passed" : "")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                start()
            } label: {
                Text(previous.isEmpty ? "Start" : "Retake").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(request.quiz.questionPool.isEmpty)
            .padding(.bottom, 12)
        }
    }

    private func fact(_ symbol: String, _ text: String) -> some View {
        Label { Text(text) } icon: { Image(systemName: symbol).foregroundStyle(.tint) }
            .font(.body)
    }

    private func start() {
        // Questions from the last two attempts go to the back of the line.
        let recent = Set(previous.prefix(2).flatMap(\.questionIDs))
        questions = QuizSampler.draw(request.quiz, recent: recent)
        layouts = questions.map(QuestionLayout.init)
        answers = Array(repeating: BankAnswer(), count: questions.count)
        passMark = QuizSampler.passMark(request.quiz, drawn: questions.count)
        index = 0
        score = 0
        passedNow = false
        earnedXP = 0
        guard !questions.isEmpty else { return }
        withAnimation(.snappy) { phase = .answering }
    }

    // MARK: Answering

    private var answering: some View {
        VStack(alignment: .leading, spacing: 18) {
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
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(index + 1) OF \(questions.count) · \(questions[index].kindName.uppercased())")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    BankQuestionView(question: questions[index], layout: layouts[index], answer: $answers[index])
                }
                .padding(.bottom, 12)
            }
            .id(index)

            HStack(spacing: 10) {
                if index > 0 {
                    Button { index -= 1 } label: { Text("Back").frame(maxWidth: .infinity) }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                }
                Button {
                    if index + 1 < questions.count {
                        index += 1
                    } else {
                        submit()
                    }
                } label: {
                    Text(index + 1 < questions.count ? "Next" : "Submit").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(!answers[index].isComplete(for: questions[index]))
            }
            .padding(.bottom, 12)
        }
    }

    private func submit() {
        let records = questions.indices.map { i in
            Record(questionID: questions[i].id, revision: questions[i].revision, answer: answers[i], correct: answers[i].isCorrect(for: questions[i]))
        }
        score = records.filter(\.correct).count
        let passed = score >= passMark
        let json = (try? JSONEncoder().encode(records)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let ledger = ScholarLedger(context: modelContext)
        let wasAwarded = awardExists()
        ledger.record(AssessmentAttempt(assessmentID: request.assessmentID, subjectID: request.path.subjectID, kind: request.kind, questionIDs: questions.map(\.id), points: score, maxPoints: questions.count, passed: passed, aiScored: false, answersJSON: json), in: request.path)
        if passed, let item = request.item {
            ledger.complete(item, in: request.path, response: "Passed \(score)/\(questions.count)", feedback: "")
            earnedXP = wasAwarded ? 0 : item.xp
        }
        passedNow = passed
        withAnimation(.snappy) { phase = .results }
    }

    private func awardExists() -> Bool {
        guard let item = request.item else { return true }
        let key = SubjectAward.key(subjectID: request.path.subjectID, activityID: item.awardKey, type: .firstCompletion)
        let descriptor = FetchDescriptor<SubjectAward>(predicate: #Predicate { $0.key == key })
        return ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
    }

    // MARK: Results

    private var results: some View {
        let passed = score >= passMark
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 10) {
                    RequirementRing(progress: questions.isEmpty ? 0 : Double(score) / Double(questions.count), label: "\(score)/\(questions.count)", color: passed ? Feedback.correct : .orange, size: 110, lineWidth: 10)
                    Text(passed ? "Passed" : "Not yet").font(.title.bold())
                    Text(passed
                         ? (request.item == nil ? "This part is done." : earnedXP > 0 ? "+\(earnedXP) XP" : "XP already earned for this quiz")
                         : "You need \(passMark) of \(questions.count). Review the explanations below, then retake with new questions.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)

                ForEach(questions.indices, id: \.self) { i in
                    let correct = answers[i].isCorrect(for: questions[i])
                    VStack(alignment: .leading, spacing: 12) {
                        Label(correct ? "Correct" : "Missed", systemImage: correct ? Feedback.correctSymbol : Feedback.incorrectSymbol)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(correct ? Feedback.correct : Feedback.incorrect)
                        BankQuestionView(question: questions[i], layout: layouts[i], answer: .constant(answers[i]), reveal: true, disabled: true)
                        Text(questions[i].explanation).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground).opacity(0.6), in: .rect(cornerRadius: 20))
                }

                HStack(spacing: 10) {
                    Button { start() } label: { Text("Retake").frame(maxWidth: .infinity) }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                    Button { dismiss() } label: { Text("Done").frame(maxWidth: .infinity) }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                }
                .padding(.bottom, 16)
            }
        }
    }
}
