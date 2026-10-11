import SwiftData
import SwiftUI

/// Every subject's five badges, earned or locked. Tap one for its detail: when it was earned,
/// XP at award and what earned it, or exactly what it still needs.
struct BadgesView: View {
    @Environment(ContentService.self) private var content
    @Query(sort: \RankGrant.earnedAt) private var grants: [RankGrant]
    @Query private var awards: [SubjectAward]
    @Query private var completions: [ItemCompletion]
    @Query private var attempts: [AssessmentAttempt]
    @State private var selected: Selection?

    private struct Selection: Hashable {
        let subjectID: String
        let rank: ScholarRank
    }

    private var paths: [ScholarPathFile] {
        PathCatalog.shared.paths.values.sorted { name(of: $0.subjectID) < name(of: $1.subjectID) }
    }

    var body: some View {
        let progresses = paths.map { ScholarProgress(path: $0, awards: awards, completions: completions, attempts: attempts, grants: grants, enrollments: []) }
        let current = selected ?? defaultSelection(progresses)

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(summary).font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 4)

                if let current, let progress = progresses.first(where: { $0.path.subjectID == current.subjectID }) {
                    detail(current, progress: progress)
                }

                ForEach(progresses, id: \.path.subjectID) { progress in
                    shelf(progress, current: current)
                }

                if paths.isEmpty {
                    ContentUnavailableView("No Scholar Paths Yet", systemImage: "medal", description: Text("Badges appear here when a subject's path is published."))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Badges")
    }

    private var summary: String {
        let subjects = Set(grants.map(\.subjectID)).count
        let count = Set(grants.map { "\($0.subjectID)|\($0.rankRaw)" }).count
        return count == 0 ? "Earn your first badge by finishing a learning item." : "\(count) earned across \(subjects) subject\(subjects == 1 ? "" : "s")"
    }

    private func name(of subjectID: String) -> String {
        content.subject(subjectID)?.name ?? PathCatalog.shared.path(for: subjectID)?.title ?? subjectID
    }

    private func defaultSelection(_ progresses: [ScholarProgress]) -> Selection? {
        guard let first = progresses.first else { return nil }
        let rank = first.nextRank ?? first.rank ?? .novice
        return Selection(subjectID: first.path.subjectID, rank: rank)
    }

    private func status(_ rank: ScholarRank, in progress: ScholarProgress) -> ScholarBadge.Status {
        if let current = progress.rank, rank <= current { return .earned }
        return rank == progress.nextRank ? .next : .locked
    }

    private func detail(_ selection: Selection, progress: ScholarProgress) -> some View {
        let rank = selection.rank
        let state = status(rank, in: progress)
        let grant = progress.grant(rank)
        let attainable = rank <= progress.path.highestAttainableRank
        return HStack(alignment: .top, spacing: 14) {
            Group {
                if state == .earned {
                    // Earned medals are coins: they spin in when picked and can be spun by hand.
                    ScholarCoin(rank: rank, size: 96, introSpin: true)
                        .id("\(selection.subjectID)|\(rank.rawValue)")
                } else {
                    ScholarBadge(rank: rank, size: 96, status: state)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(rank.name).font(.title2.bold())
                Text(name(of: selection.subjectID)).font(.subheadline).foregroundStyle(.secondary)
                if state == .earned, let grant {
                    Text("Earned \(grant.earnedAt.formatted(date: .long, time: .omitted))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Feedback.correct)
                    Text(rank == .novice ? "For your first learning item · \(grant.xpAtAward) XP" : "\(grant.xpAtAward.formatted()) XP at award · Stages 1–\(rank.requiredStages) complete")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text(attainable ? "\(state == .next ? "Next" : "Locked") · needs \(rank.requirement(xp: progress.threshold(rank)))" : "Not offered yet · this path's later stages are coming")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(state == .next ? Color.accentColor : .secondary)
                    if attainable {
                        Text("You have \(progress.xp.formatted()) XP and \(progress.completedStages) of \(rank.requiredStages) stages complete.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }

    private func shelf(_ progress: ScholarProgress, current: Selection?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(name(of: progress.path.subjectID)).font(.headline)
                Spacer()
                Text(progress.rank?.name ?? "Not started").font(.footnote).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            HStack {
                ForEach(ScholarRank.allCases) { rank in
                    let selection = Selection(subjectID: progress.path.subjectID, rank: rank)
                    Button {
                        withAnimation(.snappy) { selected = selection }
                    } label: {
                        ScholarBadge(rank: rank, size: 54, status: status(rank, in: progress))
                            .padding(4)
                            .background(selection == current ? Color.primary.opacity(0.08) : .clear, in: .rect(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("\(rank.name), \(name(of: progress.path.subjectID))")
                    .accessibilityAddTraits(selection == current ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
    }
}
