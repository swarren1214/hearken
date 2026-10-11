import SwiftData
import SwiftUI

/// One course: objectives and progress, its modules' items (Required or Optional, with XP),
/// the checkpoint, then optional videos and books.
struct CourseView: View {
    let path: ScholarPathFile
    let course: PathCourse

    var body: some View {
        ScholarProgressReader(path: path) { progress in
            CourseContent(path: path, course: course, progress: progress)
        }
    }
}

private struct CourseContent: View {
    let path: ScholarPathFile
    let course: PathCourse
    let progress: ScholarProgress

    @State private var check: AssessmentRequest?

    private var stage: PathStage? { path.stage(containing: course.id) }

    var body: some View {
        let status = progress.status(of: course)
        let unlocked = progress.isUnlocked(course)

        List {
            Section {
                HStack(spacing: 14) {
                    RequirementRing(progress: status.fraction, label: "\(status.requiredDone)/\(status.requiredTotal)", color: status.isComplete ? Feedback.correct : .accentColor, size: 64, lineWidth: 7)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(status.requiredDone) of \(status.requiredTotal) required done").font(.headline)
                        Text("\(status.xpEarned) of \(status.xpAvailable) XP earned").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)

                if !unlocked {
                    Label("Finish the earlier course first. You can look around, but items here can't be completed yet.", systemImage: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                // The title block lives in the header so it sits above the card, unclipped by
                // the section's rounded corners and with no separator under it.
                VStack(alignment: .leading, spacing: 6) {
                    if let stage {
                        Text("STAGE \(stage.number) · COURSE \(course.number)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tint)
                    }
                    Text(course.title).font(.title2.bold()).foregroundStyle(.primary)
                    Text(course.summary).font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        chip("About \(hours(course.minutes))")
                        chip("Up to \(course.requiredXP) XP")
                        chip("\(course.requiredItems.count) required")
                    }
                    .padding(.top, 4)
                }
                .textCase(nil)
                .padding(.bottom, 10)
            }

            ForEach(course.modules) { module in
                Section {
                    if !module.objectives.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("You'll be able to").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                            ForEach(module.objectives, id: \.self) { objective in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.subheadline)
                                        .foregroundStyle(.tint)
                                        .accessibilityHidden(true)
                                    Text(objective).font(.subheadline)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    ForEach(module.items) { item in itemRow(item, unlocked: unlocked) }
                } header: {
                    HStack {
                        Text("\(module.number) \(module.title)")
                        Spacer()
                        let required = module.items.filter(\.required)
                        Text("\(required.filter { progress.isDone($0) }.count) of \(required.count)").textCase(nil)
                    }
                }
            }

            if let checkpoint = course.checkpoint {
                Section {
                    Button {
                        check = AssessmentRequest(title: "\(course.title) Checkpoint", kind: "checkpoint", assessment: checkpoint, path: path)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: status.checkpointPassed ? "checkmark.circle.fill" : "checklist")
                                .font(.title3)
                                .foregroundStyle(status.checkpointPassed ? Feedback.correct : Color.accentColor)
                                .frame(width: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Course checkpoint").font(.body.weight(.semibold)).foregroundStyle(.primary)
                                Text(checkpointDetail(checkpoint, status: status))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(status.checkpointPassed ? "Passed" : "+\(checkpoint.xp) XP")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(status.checkpointPassed ? Feedback.correct : .secondary)
                        }
                    }
                    .disabled(!(checkpoint.isReady && (status.requiredComplete || ScholarDebug.unlockAll) && unlocked))
                } footer: {
                    Text("XP is paid once per item. Optional items earn the same XP but can't stand in for required ones.")
                }
            }

            if !course.videos.isEmpty {
                Section("Optional videos") {
                    ForEach(course.videos) { item in itemRow(item, unlocked: unlocked) }
                }
            }

            if !course.books.isEmpty {
                Section {
                    ForEach(course.books, id: \.title) { book in
                        if let url = book.url {
                            Link(destination: url) { bookRow(book) }
                        } else {
                            bookRow(book)
                        }
                    }
                } header: {
                    Text("Optional books")
                } footer: {
                    Text("No purchase is needed to advance. Books earn no XP.")
                }
            }
        }
        .navigationTitle("Course \(course.number)")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $check) { AssessmentView(request: $0) }
    }

    private func itemRow(_ item: PathItem, unlocked: Bool) -> some View {
        let done = progress.isDone(item)
        let paid = progress.isAwarded(item)
        return NavigationLink {
            LearningItemView(path: path, item: item)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.symbol)
                    .font(.subheadline)
                    .foregroundStyle(done ? Feedback.correct : .accentColor)
                    .frame(width: 34, height: 34)
                    .background((done ? Feedback.correct : Color.accentColor).opacity(0.14), in: .rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.body).lineLimit(2)
                    Text("\(item.kindName) · \(item.required ? "Required" : "Optional")\(item.minutes.map { " · about \($0) min" } ?? "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if done {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Feedback.correct).font(.title3)
                } else if unlocked && !progress.isUnlocked(item, in: course) {
                    // A v2 module's steps open in order.
                    Image(systemName: "lock.fill").font(.footnote).foregroundStyle(.tertiary)
                        .accessibilityLabel("Opens after the step before it")
                } else {
                    Text(paid ? "Earned" : "+\(item.xp)")
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityValue(done ? "Done" : "Not done")
    }

    private func bookRow(_ book: PathResource) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(book.title).font(.body).foregroundStyle(.primary)
            if let note = book.note { Text(note).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Color(.secondarySystemGroupedBackground), in: Capsule())
    }

    private func hours(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }

    private func checkpointDetail(_ checkpoint: PathAssessment, status: ScholarProgress.CourseStatus) -> String {
        let shape = checkpoint.quiz.map { "\($0.questionCount) questions and an essay · \($0.passCount) to pass" } ?? "\(checkpoint.questionCount) questions · \(checkpoint.passPercent)% to pass"
        if status.checkpointPassed, let best = progress.best(checkpoint) { return "\(best.points)/\(best.maxPoints) · retake any time" }
        if !checkpoint.isReady { return "Questions coming soon · " + shape }
        if !status.requiredComplete { return shape + " · opens after \(status.requiredTotal - status.requiredDone) more required items" }
        return shape
    }
}
