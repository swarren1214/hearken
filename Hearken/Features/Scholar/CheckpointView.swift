import SwiftData
import SwiftUI

/// A v2 course checkpoint or stage advancement exam, in two parts: objective questions drawn
/// across every module (a quiz with its own pass mark), then an essay scored against the rubric.
/// The check passes once both parts are done; a checkpoint then pays its XP once, and an
/// advancement exam opens the next stage. Either part can be retaken or revised on its own.
struct CheckpointView: View {
    let request: AssessmentRequest

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ContentService.self) private var content
    @Query private var attempts: [AssessmentAttempt]
    @State private var quiz: QuizRequest?
    @State private var finishedNow = false

    init(request: AssessmentRequest) {
        self.request = request
        let id = request.assessment.id, quizID = id + "-quiz", essayID = id + "-essay"
        _attempts = Query(filter: #Predicate<AssessmentAttempt> { $0.assessmentID == id || $0.assessmentID == quizID || $0.assessmentID == essayID },
                          sort: \AssessmentAttempt.attemptedAt, order: .reverse)
    }

    private var assessment: PathAssessment { request.assessment }
    private var quizID: String { assessment.id + "-quiz" }
    private var essayID: String { assessment.id + "-essay" }
    private var isExam: Bool { request.kind == "advancement" }

    private var quizAttempts: [AssessmentAttempt] { attempts.filter { $0.assessmentID == quizID } }
    private var essayAttempts: [AssessmentAttempt] { attempts.filter { $0.assessmentID == essayID } }
    private var quizPassed: Bool { quizAttempts.contains(where: \.passed) }
    private var essayDone: Bool {
        guard let essay = assessment.essay else { return true }
        return essayAttempts.contains { $0.passed || !$0.aiScored } || essayAttempts.count >= essay.revisionsBeforeCompletion
    }
    private var passed: Bool { attempts.contains { $0.assessmentID == assessment.id && $0.passed } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    quizCard
                    if let essay = assessment.essay {
                        partLabel(number: 2, title: "Essay", done: essayDone)
                        EssayWorkspace(path: request.path, assessmentID: essayID, essay: essay, unlocked: true, isComplete: essayDone,
                                       sources: sources) { _, _ in finishIfReady() }
                    }
                    if passed { doneCard }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", role: .close) { dismiss() }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .fullScreenCover(item: $quiz, onDismiss: finishIfReady) { QuizRunnerView(request: $0) }
        .sensoryFeedback(.success, trigger: finishedNow) { _, new in new }
        .onChange(of: attempts.count) { _, _ in finishIfReady() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(request.title).font(.largeTitle.bold()).padding(.top, 12)
            Text(isExam
                 ? "Questions from every module in this stage, then an essay. Pass both to open the next stage. No XP; it opens the next rank."
                 : "Questions from every module in this course, then an essay. Pass both to complete the course and earn +\(assessment.xp) XP once.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Label("Scored on understanding and evidence, never on belief", systemImage: "person.badge.shield.checkmark")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func partLabel(number: Int, title: String, done: Bool) -> some View {
        Label("Part \(number) · \(title)\(done ? " · done" : "")", systemImage: done ? Feedback.correctSymbol : "\(number).circle")
            .font(.headline)
            .foregroundStyle(done ? Feedback.correct : .primary)
    }

    @ViewBuilder
    private var quizCard: some View {
        if let spec = assessment.quiz {
            VStack(alignment: .leading, spacing: 12) {
                partLabel(number: 1, title: "Questions", done: quizPassed)
                Text("\(spec.questionCount) questions drawn across every module, \(spec.passCount) to pass. Multiple choice, true/false and matching; explanations after you submit.")
                    .font(.subheadline)
                if let best = quizAttempts.max(by: { $0.points < $1.points }) {
                    Text("Best: \(best.points)/\(best.maxPoints)\(best.passed ? ", passed" : "")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button {
                    quiz = QuizRequest(title: isExam ? "Advancement Exam" : "Checkpoint Questions", assessmentID: quizID, kind: "\(request.kind)-quiz", quiz: spec, path: request.path)
                } label: {
                    Text(quizAttempts.isEmpty ? "Start the Questions" : quizPassed ? "Retake for Practice" : "Retake").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        }
    }

    private var doneCard: some View {
        Label(isExam ? "Exam passed · the next stage is open" : "Checkpoint passed · +\(assessment.xp) XP", systemImage: Feedback.correctSymbol)
            .font(.headline)
            .foregroundStyle(Feedback.correct)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Feedback.correct.opacity(0.1), in: .rect(cornerRadius: 18))
    }

    /// The scripture assigned in the course (checkpoint) or stage (exam), for the essay scorer.
    private func sources() -> String {
        let path = request.path
        if let stage = path.stages.first(where: { $0.advancementCheck?.id == assessment.id }) {
            return EssaySources.text(for: stage.courses.flatMap(\.modules), content: content)
        }
        if let course = path.stages.flatMap(\.courses).first(where: { $0.checkpoint?.id == assessment.id }) {
            return EssaySources.text(for: course.modules, content: content)
        }
        return ""
    }

    /// Records the passed check once both parts are done; the ledger pays a checkpoint's XP.
    private func finishIfReady() {
        guard quizPassed, essayDone, !passed else { return }
        let best = quizAttempts.filter(\.passed).max { $0.points < $1.points }
        ScholarLedger(context: modelContext).record(
            AssessmentAttempt(assessmentID: assessment.id, subjectID: request.path.subjectID, kind: request.kind,
                              questionIDs: best?.questionIDs ?? [], points: best?.points ?? 0, maxPoints: best?.maxPoints ?? 0,
                              passed: true, aiScored: essayAttempts.contains(where: \.aiScored), answersJSON: ""),
            in: request.path)
        finishedNow = true
    }
}
