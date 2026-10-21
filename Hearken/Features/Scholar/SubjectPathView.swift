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
        .refreshable { await CloudRefresh.refresh() }
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
                ? "Earned \(DateLabel.short(grant.earnedAt)) · first learning item"
                : "Earned \(DateLabel.short(grant.earnedAt)) · \(grant.xpAtAward.formatted()) XP"
        } else if state == .earned {
            subtitle = "Earned"
        } else {
            subtitle = rank.requirement(xp: progress.threshold(rank)) + (state == .next ? " · next" : "")
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
                } else if !stage.isBuilt {
                    ComingSoonTag()
                } else if let rank = ScholarRank(rawValue: stage.number) {
                    Text("After \(rank.name)").font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(stage.courses) { course in
                if course.isBuilt {
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
                } else {
                    HStack {
                        Text(course.title).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                        Spacer(minLength: 4)
                        // The stage header already says Coming Soon when the whole stage is.
                        if stage.isBuilt == false && stage.courses.contains(where: \.isBuilt) { ComingSoonTag() }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(course.title), coming soon")
                }
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
                    .foregroundStyle(.secondary)
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
                        .foregroundStyle(passed ? Feedback.correct : open ? Color.primary : .secondary)
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
        let shape = check.quiz.map { "\($0.questionCount) questions and an essay, \($0.passCount) to pass" } ?? "\(check.questionCount) questions, \(check.passPercent)% to pass"
        if passed { return "Passed · " + shape }
        if !stage.isBuilt { return "Coming soon" }
        if !check.isReady { return "Questions coming soon · " + shape }
        if !open { return "Opens when both courses are done · " + shape }
        return shape + " · no XP; it opens the next rank"
    }
}

// MARK: - Rank header

/// Where you stand on this path. Collapsed, a compact banner: your medal and rank, the next badge
/// and one XP bar. Tap it to expand: the medal (tap it to flip), the ladder of all five badges
/// filling toward the next one, and a bar for each thing the next badge needs. Remembers whether
/// it was left open.
private struct RankHeader: View {
    let path: ScholarPathFile
    let progress: ScholarProgress

    /// Saved so the card reopens the way it was left. The view animates from `expanded`, a plain
    /// @State: changes to @AppStorage don't carry the animation transaction with them.
    @AppStorage("scholarRankCardExpanded") private var savedExpanded = false
    @State private var expanded = false
    @Namespace private var space

    var body: some View {
        let rank = progress.rank
        let palette = (rank ?? .novice).palette
        VStack(alignment: .leading, spacing: 0) {
            if expanded {
                expandedCard
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)).animation(.easeOut(duration: 0.3).delay(0.08)),
                                            removal: .opacity.animation(.easeIn(duration: 0.15))))
            } else {
                compactCard
                    .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.25).delay(0.1)),
                                            removal: .opacity.animation(.easeIn(duration: 0.12))))
            }
        }
        .foregroundStyle(.white)
        .padding(expanded ? 18 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [palette.top, palette.bottom], startPoint: .topLeading, endPoint: .bottomTrailing), in: .rect(cornerRadius: 26))
        // Keep content inside the card while its height animates.
        .clipShape(.rect(cornerRadius: 26))
        .shadow(color: palette.bottom.opacity(0.25), radius: 15, y: 10)
        .contentShape(.rect(cornerRadius: 26))
        .onTapGesture(perform: toggle)
        .sensoryFeedback(.selection, trigger: expanded)
        .animation(.spring(duration: 0.45, bounce: 0.12), value: expanded)
        .onAppear { expanded = savedExpanded }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: expanded ? "Show less" : "Show more", toggle)
    }

    private func toggle() {
        withAnimation(.spring(duration: 0.45, bounce: 0.12)) { expanded.toggle() }
        savedExpanded = expanded
    }

    // MARK: Compact

    private var compactCard: some View {
        let rank = progress.rank
        let next = progress.nextRank
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                ScholarBadge(rank: rank ?? .novice, size: 64, status: rank == nil ? .next : .earned)
                    .matchedGeometryEffect(id: "medal", in: space)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rank?.name ?? "No badge yet")
                        .font(.title2.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(compactSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                chevron
            }
            if let next, next > .novice {
                bar(progress.xpFraction, color: barColor(next))
                    .padding(.top, 16)
                HStack {
                    Text(progress.xpReached ? "XP reached" : "\(progress.xp.formatted()) of \(progress.threshold(next).formatted()) XP")
                    Spacer(minLength: 8)
                    Text(stageSummary(next))
                }
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.top, 8)
            }
        }
    }

    private var compactSubtitle: String {
        guard progress.rank != nil else { return "Finish any item to earn Novice" }
        guard let next = progress.nextRank else { return "Every badge earned" }
        return "\(next.name) next"
    }

    // MARK: Expanded

    private var expandedCard: some View {
        let rank = progress.rank
        let next = progress.nextRank
        let palette = (rank ?? .novice).palette
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                Group {
                    if let rank {
                        // Tap the medal to turn it over; tap anywhere else to collapse.
                        FlippingCoin(rank: rank, size: 88) { ScholarBadge(rank: rank, size: 88) }
                    } else {
                        ScholarBadge(rank: .novice, size: 88, status: .next)
                    }
                }
                .matchedGeometryEffect(id: "medal", in: space)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rank == nil ? "NOT STARTED" : "YOUR RANK")
                        .font(.caption.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(palette.light)
                    Text(rank?.name ?? "No badge yet")
                        .font(.title.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(rank.map { "Badge \($0.rawValue) of 5" } ?? "Badge 1 of 5 is your first")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                }
                Spacer(minLength: 0)
                chevron
            }

            ladder.padding(.top, 20)

            Rectangle().fill(.white.opacity(0.12)).frame(height: 1).padding(.vertical, 16)

            if let next {
                HStack(spacing: 10) {
                    ScholarBadge(rank: next, size: 28, status: .next)
                    Text("Next: \(next.name)").font(.headline)
                }
                if next > .novice {
                    VStack(spacing: 12) {
                        requirement("XP", value: progress.xp.formatted(), of: "/ \(progress.threshold(next).formatted())",
                                    fraction: progress.xpFraction, color: barColor(next))
                        stageRequirement(next)
                    }
                    .padding(.top, 14)
                    if next == .sage {
                        Text("Plus the capstone")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.65))
                            .padding(.top, 10)
                    }
                } else {
                    Text(nextDetail(next))
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.72))
                        .padding(.top, 8)
                }
            } else {
                Text("You've earned every badge this path offers so far. More stages are on the way.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
            }

            NavigationLink {
                BadgesView()
            } label: {
                HStack {
                    Text("All Badges")
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.bold)).opacity(0.7)
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(.white.opacity(0.1), in: .rect(cornerRadius: 14))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.down")
            .font(.footnote.weight(.bold))
            .rotationEffect(.degrees(expanded ? 180 : 0))
            .frame(width: 30, height: 30)
            .background(.white.opacity(0.12), in: Circle())
            .matchedGeometryEffect(id: "chevron", in: space)
            .accessibilityHidden(true)
    }

    // MARK: Ladder

    /// The five badges with no labels. The line between them is lit up to your rank and fills
    /// toward the next one with your XP.
    private var ladder: some View {
        let ranks = ScholarRank.allCases.sorted()
        let current = progress.rank
        let next = progress.nextRank
        let toward = min(max(progress.xpFraction, 0), 1)
        return HStack(spacing: 0) {
            ForEach(Array(ranks.enumerated()), id: \.element) { index, rank in
                let earned = current.map { rank <= $0 } ?? false
                let isCurrent = rank == current
                let isNext = rank == next
                // How lit the segment from this badge to the next one is.
                let after: Double = index == ranks.count - 1 ? 0
                    : (current.map { ranks[index + 1] <= $0 } ?? false) ? 1
                    : isCurrent ? toward : 0
                let before: Double = index == 0 ? 0
                    : earned ? 1
                    : isNext && current != nil ? toward : 0
                ZStack {
                    HStack(spacing: 0) {
                        segment(fill: index == 0 ? nil : max(0, before * 2 - 1))
                        segment(fill: index == ranks.count - 1 ? nil : min(after * 2, 1))
                    }
                    let size: CGFloat = isCurrent || isNext ? 40 : 34
                    ScholarBadge(rank: rank, size: size, status: earned ? .earned : isNext ? .next : .locked)
                        .padding(3)
                        .overlay {
                            if isCurrent || (current == nil && isNext) {
                                Circle().strokeBorder(.white, lineWidth: 2.5)
                            }
                        }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 46)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ladderLabel)
    }

    /// Half the connector between two badges; `nil` draws nothing (the ends of the ladder).
    @ViewBuilder
    private func segment(fill: Double?) -> some View {
        if let fill {
            Rectangle()
                .fill(.white.opacity(0.14))
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Rectangle().fill(barColor(progress.nextRank ?? .novice)).frame(width: geo.size.width * fill)
                    }
                }
                .frame(height: 3)
        } else {
            Color.clear.frame(height: 3)
        }
    }

    private var ladderLabel: String {
        ScholarRank.allCases.sorted().map { rank in
            let earned = progress.rank.map { rank <= $0 } ?? false
            return "\(rank.name), \(earned ? "earned" : rank == progress.nextRank ? "next" : "locked")"
        }.joined(separator: "; ")
    }

    // MARK: Requirements

    private func barColor(_ next: ScholarRank) -> Color {
        progress.xpReached ? Feedback.correct : next.palette.light
    }

    private func bar(_ fraction: Double, color: Color) -> some View {
        Capsule()
            .fill(.white.opacity(0.14))
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    // A sliver shows even at 0, so the bar reads as a bar.
                    Capsule().fill(color).frame(width: max(6, geo.size.width * min(max(fraction, 0), 1)))
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
    }

    private func requirement(_ title: String, value: String, of total: String, fraction: Double, color: Color) -> some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline.weight(.bold))
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value).font(.subheadline.weight(.semibold))
                    if !total.isEmpty {
                        Text(total).font(.subheadline).foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            .monospacedDigit()
            bar(fraction, color: color)
        }
        .accessibilityElement(children: .combine)
    }

    private func stageRequirement(_ next: ScholarRank) -> some View {
        let s = stageCounts
        return requirement("Stage \(next.requiredStages)",
                           value: s.complete ? "Complete" : s.done == s.total ? "Exam left" : "\(s.done)",
                           of: s.complete || s.done == s.total ? "" : "/ \(s.total) courses",
                           fraction: s.fraction, color: s.complete ? Feedback.correct : next.palette.light)
    }

    private var stageCounts: (done: Int, total: Int, complete: Bool, fraction: Double) {
        let stage = progress.nextStage
        let total = stage?.courses.count ?? 0
        let done = stage.map { progress.coursesComplete(in: $0) } ?? 0
        let complete = stage.map { progress.isComplete($0) } ?? false
        // The stage's courses, then its exam.
        let fraction = total == 0 ? 0 : (Double(done) + (complete ? 1 : 0)) / Double(total + 1)
        return (done, total, complete, fraction)
    }

    private func stageSummary(_ next: ScholarRank) -> String {
        let s = stageCounts
        if s.complete { return "Stage \(next.requiredStages) complete" }
        if s.done == s.total { return "Stage \(next.requiredStages) · exam left" }
        return "Stage \(next.requiredStages) · \(s.done) of \(s.total) courses"
    }

    private func nextDetail(_ next: ScholarRank) -> String {
        if next == .novice {
            if let course = progress.currentStage?.courses.first {
                return "Finish any item, like the first lesson in \(course.title)"
            }
            return "Finish any learning item"
        }
        return "\(progress.threshold(next).formatted()) XP and Stage \(next.requiredStages) complete"
    }
}

// MARK: - Course card

struct CourseCard: View {
    let path: ScholarPathFile
    let course: PathCourse
    let progress: ScholarProgress

    var body: some View {
        if course.isBuilt { builtCard } else { comingSoonCard }
    }

    /// A course that isn't built yet: grayed out, can't be opened.
    private var comingSoonCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "hourglass")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .background(Color(.tertiarySystemFill), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(course.title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                ComingSoonTag()
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        .opacity(0.75)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(course.title), coming soon")
    }

    private var builtCard: some View {
        let status = progress.status(of: course)
        let unlocked = progress.isUnlocked(course)
        return NavigationLink {
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
        return "Checkpoint ready · +\(checkpoint.xp) XP"
    }
}

// MARK: - Coming soon

/// The capsule on courses and subjects that aren't built yet.
struct ComingSoonTag: View {
    var body: some View {
        Text("Coming Soon")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(.tertiarySystemFill), in: Capsule())
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
