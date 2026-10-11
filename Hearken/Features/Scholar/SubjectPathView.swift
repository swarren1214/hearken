import SwiftData
import SwiftUI

/// What a check needs to start.
struct AssessmentRequest: Identifiable {
    let id = UUID()
    let title: String
    /// "checkpoint" or "advancement".
    let kind: String
    let assessment: PathAssessment
    let path: ScholarPathFile
}

/// A subject's Scholar Path: the rank header with what the next badge needs, then the path:
/// badges as nodes, each stage between two of them.
struct SubjectPathView: View {
    let subject: Subject
    let path: ScholarPathFile

    var body: some View {
        ScholarProgressReader(path: path) { progress in
            SubjectPathContent(subject: subject, path: path, progress: progress)
        }
    }
}

private struct SubjectPathContent: View {
    let subject: Subject
    let path: ScholarPathFile
    let progress: ScholarProgress

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(SettingsKey.accent) private var accent: AccentOption = .blue
    @State private var check: AssessmentRequest?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                RankHeader(path: path, progress: progress)

                Text("The Scholar Path")
                    .font(.title2.bold())
                    .padding(.horizontal, 4)
                    .padding(.top, 26)
                    .padding(.bottom, 12)
                    .accessibilityAddTraits(.isHeader)

                track

                if !subject.summary.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("About this subject").font(.footnote.weight(.semibold))
                        Text(subject.summary).font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 28)
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(subject.name)
        .fullScreenCover(item: $check) { AssessmentView(request: $0) }
    }

    // MARK: Track

    private var trackDone: Color { colorScheme == .dark ? ScholarRank.apprentice.palette.mid : ScholarRank.apprentice.palette.rim }

    @ViewBuilder
    private var track: some View {
        let stages = path.stages.sorted { $0.number < $1.number }
        VStack(alignment: .leading, spacing: 0) {
            node(.novice)
            ForEach(stages.filter(\.published)) { stage in
                stageRow(stage)
                if let rank = ScholarRank(rawValue: stage.number + 1) {
                    node(rank)
                }
            }
            if stages.contains(where: { !$0.published }) {
                lineRow(done: false) {
                    Text(path.capstone != nil && stages.contains(where: { !$0.published && $0.number == 4 })
                         ? "More stages coming. Stage 4 and the Sage badge arrive once capstone review is ready."
                         : "More stages coming.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])).foregroundStyle(.quaternary))
                }
            }
        }
    }

    private func status(of rank: ScholarRank) -> ScholarBadge.Status {
        if let current = progress.rank, rank <= current { return .earned }
        if rank == progress.nextRank { return .next }
        return .locked
    }

    private func node(_ rank: ScholarRank) -> some View {
        let state = status(of: rank)
        let subtitle: String
        if state == .earned, let grant = progress.grant(rank) {
            subtitle = rank == .novice
                ? "Earned \(BookmarksSheet.date(grant.earnedAt)) · first learning item"
                : "Earned \(BookmarksSheet.date(grant.earnedAt)) · \(grant.xpAtAward.formatted()) XP"
        } else if state == .earned {
            subtitle = "Earned"
        } else {
            subtitle = rank.requirement + (state == .next ? " · next" : "")
        }
        return HStack(spacing: 12) {
            ScholarBadge(rank: rank, size: 56, status: state)
            VStack(alignment: .leading, spacing: 2) {
                Text(rank.name)
                    .font(.headline)
                    .foregroundStyle(state == .locked ? Color.secondary : Color.primary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// A row beside the track line: the line runs down the left column, the content sits right.
    private func lineRow<Content: View>(done: Bool, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle()
                .fill(done ? trackDone : Color(.tertiarySystemFill))
                .frame(width: 4)
                .frame(maxHeight: .infinity)
                .frame(width: 56)
            content()
                .padding(.vertical, 6)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func stageRow(_ stage: PathStage) -> some View {
        let complete = progress.isComplete(stage)
        let current = progress.currentStage?.number == stage.number
        lineRow(done: complete) {
            if current {
                currentStage(stage)
            } else {
                summaryStage(stage, complete: complete)
            }
        }
    }

    private func stageLabel(_ stage: PathStage) -> String { "STAGE \(stage.number) · \(stage.title.uppercased())" }

    private func summaryStage(_ stage: PathStage, complete: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(stageLabel(stage))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                if complete {
                    Label("Complete", systemImage: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Feedback.correct)
                } else if let rank = ScholarRank(rawValue: stage.number) {
                    Text("After \(rank.name)").font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(stage.courses) { course in
                NavigationLink {
                    CourseView(path: path, course: course)
                } label: {
                    HStack {
                        Text(course.title).font(.subheadline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(!progress.isUnlocked(course))
            }
            if complete, let check = stage.advancementCheck, let best = progress.best(check) {
                Text("Advancement check \(best.points)/\(best.maxPoints)").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
        .opacity(complete ? 1 : 0.7)
    }

    private func currentStage(_ stage: PathStage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(stageLabel(stage))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tint)
                Spacer()
                Text("In progress").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Text(stage.outcome)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(stage.courses) { course in
                CourseCard(path: path, course: course, progress: progress)
            }
            advancementRow(stage)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.tint.opacity(0.55), lineWidth: 2))
    }

    @ViewBuilder
    private func advancementRow(_ stage: PathStage) -> some View {
        if let check = stage.advancementCheck {
            let open = progress.isAdvancementOpen(stage) && check.isReady
            let passed = progress.hasPassed(check)
            Button {
                self.check = AssessmentRequest(title: "Stage \(stage.number) Advancement Check", kind: "advancement", assessment: check, path: path)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: passed ? "checkmark" : open ? "checklist" : "lock.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(passed ? Feedback.correct : open ? Color.accentColor : .secondary)
                        .frame(width: 40, height: 40)
                        .background(Color(.tertiarySystemFill), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Advancement check").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        Text(advancementDetail(check, stage: stage, open: open, passed: passed))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: open ? [] : [5, 4])).foregroundStyle(.quaternary))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!open)
        }
    }

    private func advancementDetail(_ check: PathAssessment, stage: PathStage, open: Bool, passed: Bool) -> String {
        let shape = "\(check.questionCount) questions, \(check.passPercent)% to pass"
        if passed { return "Passed · " + shape }
        if !check.isReady { return "Questions coming soon · " + shape }
        if !open { return "Opens when both courses are done · " + shape }
        return shape + " · no XP; it opens the next rank"
    }
}

// MARK: - Rank header

/// Where you stand on this path: your medal and rank, a ladder of all five badges with
/// "you are here", and exactly what the next badge needs.
private struct RankHeader: View {
    let path: ScholarPathFile
    let progress: ScholarProgress

    var body: some View {
        let rank = progress.rank
        let next = progress.nextRank
        let palette = (rank ?? .novice).palette
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                // The ring is XP toward the next badge, so it only appears once you hold a rank
                // and there's a next one with an XP requirement.
                let showsRing = rank != nil && (next?.xpThreshold ?? 0) > 0
                ScholarBadge(rank: rank ?? .novice, size: 112, status: rank == nil ? .next : .earned,
                             progress: showsRing ? progress.xpFraction : nil,
                             tint: showsRing ? (progress.xpReached ? Optional(Feedback.correct) : next?.palette.light) : nil)
                VStack(alignment: .leading, spacing: 3) {
                    Text(rank == nil ? "NOT STARTED" : "YOUR RANK")
                        .font(.caption.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(palette.light)
                    Text(rank?.name ?? "No badge yet")
                        .font(.title.bold())
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                    Text(rankDetail(rank))
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.75))
                    NavigationLink {
                        BadgesView()
                    } label: {
                        Text("All Badges")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(.white.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                }
            }

            ladder

            Divider().overlay(.white.opacity(0.16))

            if let next {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        ScholarBadge(rank: next, size: 32, status: .next)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Next badge: \(next.name)").font(.subheadline.weight(.semibold))
                            Text(nextDetail(next)).font(.caption).foregroundStyle(.white.opacity(0.75))
                        }
                        Spacer(minLength: 0)
                    }
                    if next > .novice {
                        HStack(spacing: 10) {
                            xpTile(next)
                            stageTile(next)
                        }
                    }
                }
            } else {
                Text("You've earned every badge this path offers so far. More stages are on the way.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(LinearGradient(colors: [palette.top, palette.bottom], startPoint: .topLeading, endPoint: .bottomTrailing), in: .rect(cornerRadius: 26))
        .shadow(color: palette.bottom.opacity(0.25), radius: 15, y: 10)
    }

    // MARK: Ladder

    /// All five badges left to right, earned ones lit, the next one marked, with the XP each needs.
    private var ladder: some View {
        let ranks = ScholarRank.allCases.sorted()
        let next = progress.nextRank
        return HStack(alignment: .top, spacing: 0) {
            ForEach(Array(ranks.enumerated()), id: \.element) { index, rank in
                let earned = progress.rank.map { rank <= $0 } ?? false
                let isNext = rank == next
                let isCurrent = rank == progress.rank
                let nextEarned = index < ranks.count - 1 && (progress.rank.map { ranks[index + 1] <= $0 } ?? false)
                VStack(spacing: 5) {
                    ZStack {
                        // Connector to the previous badge, lit once this one is earned.
                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(index == 0 ? .clear : (earned ? Color.white.opacity(0.85) : Color.white.opacity(0.18)))
                                .frame(height: 3)
                            Rectangle()
                                .fill(index == ranks.count - 1 ? .clear : (nextEarned ? Color.white.opacity(0.85) : Color.white.opacity(0.18)))
                                .frame(height: 3)
                        }
                        ScholarBadge(rank: rank, size: 38, status: earned ? .earned : isNext ? .next : .locked)
                            .padding(3)
                            .overlay {
                                if isCurrent || (progress.rank == nil && isNext) {
                                    Circle().strokeBorder(.white, lineWidth: 2)
                                }
                            }
                    }
                    Text(rank.name)
                        .font(.caption2.weight(isCurrent || isNext ? .bold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(rank.xpThreshold == 0 ? "Start" : "\(rank.xpThreshold.formatted()) XP")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(isCurrent ? "YOU" : isNext ? "NEXT" : " ")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(isCurrent ? Color.white : rank.palette.light)
                }
                .frame(maxWidth: .infinity)
                .opacity(earned || isNext ? 1 : 0.6)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(rank.name), \(earned ? "earned" : isNext ? "next" : "locked")")
            }
        }
    }

    // MARK: Text

    private func rankDetail(_ rank: ScholarRank?) -> String {
        guard let rank else { return "Finish your first learning item to earn Novice, badge 1 of 5." }
        if let grant = progress.grant(rank) { return "Badge \(rank.rawValue) of 5 · earned \(BookmarksSheet.date(grant.earnedAt))" }
        return "Badge \(rank.rawValue) of 5 · \(progress.xp.formatted()) XP"
    }

    private func nextDetail(_ next: ScholarRank) -> String {
        if next == .novice {
            if let course = progress.currentStage?.courses.first {
                return "Finish any item, like the first lesson in \(course.title)"
            }
            return "Finish any learning item"
        }
        if next == .sage { return "\(next.xpThreshold.formatted()) XP, Stage \(next.requiredStages) and the capstone" }
        return "\(next.xpThreshold.formatted()) XP and Stage \(next.requiredStages) complete"
    }

    // MARK: Tiles

    private func tile<Ring: View>(@ViewBuilder ring: () -> Ring, title: String, detail: String) -> some View {
        HStack(spacing: 8) {
            ring()
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).monospacedDigit()
                Text(detail).font(.caption).foregroundStyle(.white.opacity(0.7))
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    private func xpTile(_ next: ScholarRank) -> some View {
        let reached = progress.xpReached
        let remaining = max(next.xpThreshold - progress.xp, 0)
        return tile(
            ring: { RequirementRing(progress: progress.xpFraction, label: "\(Int((progress.xpFraction * 100).rounded()))%", color: reached ? Feedback.correct : next.palette.light, track: .white.opacity(0.14)) },
            title: "\(progress.xp.formatted()) XP",
            detail: reached ? "XP reached" : "of \(next.xpThreshold.formatted()) · \(remaining.formatted()) to go"
        )
    }

    private func stageTile(_ next: ScholarRank) -> some View {
        let stage = progress.nextStage
        let total = stage?.courses.count ?? 0
        let done = stage.map { progress.coursesComplete(in: $0) } ?? 0
        let complete = stage.map { progress.isComplete($0) } ?? false
        let fraction = total == 0 ? 0 : (Double(done) + (complete ? 1 : 0)) / Double(total + 1)
        return tile(
            ring: { RequirementRing(progress: fraction, label: complete ? "✓" : "\(done)/\(total)", color: complete ? Feedback.correct : next.palette.light, track: .white.opacity(0.14)) },
            title: "Stage \(next.requiredStages)",
            detail: complete ? "Complete" : done == total ? "check left" : "\(done) of \(total) courses"
        )
    }
}

// MARK: - Course card

struct CourseCard: View {
    let path: ScholarPathFile
    let course: PathCourse
    let progress: ScholarProgress

    var body: some View {
        let status = progress.status(of: course)
        let unlocked = progress.isUnlocked(course)
        NavigationLink {
            CourseView(path: path, course: course)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RequirementRing(progress: status.fraction, label: "", color: status.isComplete ? Feedback.correct : .accentColor, size: 40, lineWidth: 4)
                    if status.isComplete {
                        Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(Feedback.correct)
                    } else if !unlocked {
                        Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(course.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                    Text("\(status.requiredDone) of \(status.requiredTotal) required · \(status.xpEarned) / \(status.xpAvailable) XP")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(checkpointLine(status))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(status.checkpointPassed ? Feedback.correct : .secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 16))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .opacity(unlocked ? 1 : 0.6)
        .accessibilityHint(unlocked ? "Opens the course" : "Finish the earlier course first")
    }

    private func checkpointLine(_ status: ScholarProgress.CourseStatus) -> String {
        guard let checkpoint = course.checkpoint else { return "No checkpoint" }
        if status.checkpointPassed, let best = progress.best(checkpoint) { return "Checkpoint passed · \(best.points)/\(best.maxPoints)" }
        if !checkpoint.isReady { return "Checkpoint questions coming soon" }
        if !status.requiredComplete { return "Checkpoint opens after \(status.requiredTotal - status.requiredDone) more items" }
        return "Checkpoint ready · +\(ScholarRules.checkpointXP) XP"
    }
}

// MARK: - Routes

struct CourseRoute: Hashable {
    let subjectID: String
    let courseID: String
}

struct ItemRoute: Hashable {
    let subjectID: String
    let itemID: String
}

struct BadgesRoute: Hashable {}

/// Destinations for the Scholar Path, added to any stack that shows it.
struct ScholarDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationDestination(for: CourseRoute.self) { route in
                if let path = PathCatalog.shared.path(for: route.subjectID), let course = path.course(route.courseID) {
                    CourseView(path: path, course: course)
                }
            }
            .navigationDestination(for: ItemRoute.self) { route in
                if let path = PathCatalog.shared.path(for: route.subjectID), let item = path.item(route.itemID) {
                    LearningItemView(path: path, item: item)
                }
            }
            .navigationDestination(for: BadgesRoute.self) { _ in BadgesView() }
    }
}

extension View {
    func scholarDestinations() -> some View { modifier(ScholarDestinations()) }
}
