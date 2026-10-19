import SwiftData
import SwiftUI

/// The Play tab (Subjects and Play in one): the Daily Challenge and Spaced Review side by side,
/// quick games across every subject, then a grid of subjects. Tap a subject to study it,
/// or its ▶ to play.
struct PlayView: View {
    @Environment(ContentService.self) private var content
    @Query private var reviews: [ItemReview]
    @Query private var progress: [ReadingProgress]
    @Query private var xpEvents: [XPEvent]
    @Query(sort: \GameSession.playedAt, order: .reverse) private var sessions: [GameSession]
    @Query private var awards: [SubjectAward]
    @Query private var grants: [RankGrant]
    @State private var activeGame: GameRequest?
    @State private var mapQuest: MapQuestCategory?
    /// Quick Play and Map Quest need Hearken Plus or Hearth+; the Daily Challenge and Spaced
    /// Review are always free.
    @State private var showsPaywall = false
    /// Quick Play cards grow with the text size, up to most of the screen's width.
    @ScaledMetric(relativeTo: .subheadline) private var quickPlayWidth: CGFloat = 140

    private let mastery = MasteryService()
    private static let reviewLimit = 10

    var body: some View {
        let snapshot = MasterySnapshot(reviews: reviews, progress: progress)
        let accountXP = AccountXP.total(events: xpEvents, awards: awards)
        let badges = Set(grants.map { "\($0.subjectID)|\($0.rankRaw)" }).count
        let streak = MasteryMath.streak(activityDates: xpEvents.map(\.createdAt), now: .now)

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HeaderTitle("Play", subtitle: "\(accountXP.formatted()) XP · \(badges) badge\(badges == 1 ? "" : "s")")
                // Side by side, or one above the other at accessibility text sizes.
                AdaptiveStack(alignment: .top, spacing: 12) {
                    dailyCard(snapshot: snapshot)
                    reviewCard(snapshot: snapshot)
                }
                .fixedSize(horizontal: false, vertical: true)
                .tourTarget(.play)

                quickPlay
                mapQuestSection
                subjectsGrid(snapshot: snapshot)
            }
            // Exactly the screen's width (less the margins), so nothing too wide for very large
            // text can widen the page. (Quick Play scrolls sideways inside it, as before.)
            .containerRelativeFrame(.horizontal, alignment: .leading) { width, _ in max(width - 32, 0) }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .refreshable { await CloudRefresh.refresh() }
        .colorHeader("Play")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                    Text("\(streak)").monospacedDigit()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(streak) day streak")
            }
        }
        .fullScreenCover(item: $activeGame) { GameView(request: $0) }
        .fullScreenCover(item: $mapQuest) { MapQuestView(category: $0) }
        .hearthPaywall(isPresented: $showsPaywall, feature: HearthPaywallFeature(
            "Every game",
            detail: "Quick Play and Map Quest, and each new game as it arrives. The Daily Challenge and Spaced Review stay free.",
            symbol: "gamecontroller.fill"
        ))
    }

    private var gamesUnlocked: Bool { HearthPurchases.shared.isUnlocked }

    /// A small lock on a game card that needs Hearken Plus or Hearth+.
    private func lockBadge(onColor: Bool) -> some View {
        Image(systemName: "lock.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(onColor ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .accessibilityLabel("Needs Hearken Plus or Hearth+")
    }

    // MARK: Map Quest

    /// Geography rounds: a place is named, you drop a pin on the map.
    private var mapQuestSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Map Quest").font(.title2.bold())
            AdaptiveStack(alignment: .top, spacing: 12) {
                ForEach(MapQuestCatalog.all) { category in
                    mapQuestCard(category)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func mapQuestCard(_ category: MapQuestCategory) -> some View {
        let colors: [Color] = category.id == MapQuestCatalog.bible.id
            ? [Color(red: 0.11, green: 0.42, blue: 0.62), Color(red: 0.16, green: 0.62, blue: 0.62)]
            : [Color(red: 0.60, green: 0.33, blue: 0.16), Color(red: 0.85, green: 0.55, blue: 0.22)]
        let best = sessions
            .filter { $0.gameType == "mapQuest" && $0.subjectID == category.id }
            .map(\.correct)
            .max()

        return Button {
            if gamesUnlocked { mapQuest = category } else { showsPaywall = true }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Image(systemName: category.symbol)
                        .font(.title2)
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.2), in: .rect(cornerRadius: 12))
                    Spacer(minLength: 0)
                    if !gamesUnlocked { lockBadge(onColor: true) }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(category.title)
                        .font(.headline)
                        .multilineTextAlignment(.leading)
                    Text(category.subtitle)
                        .font(.caption)
                        .opacity(0.9)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Text(best.map { "Best: \($0) of \(MapQuestCategory.roundLength) close" } ?? "\(category.places.count) places")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.22), in: Capsule())
            }
            .foregroundStyle(.white)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: .rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Drop pins on a map to find each place.")
    }

    // MARK: Daily and review

    private func dailyCard(snapshot: MasterySnapshot) -> some View {
        let questions = mastery.dailyChallenge(content: content, snapshot: snapshot)
        let doneToday = sessions.contains { $0.gameType == GameKind.daily.rawValue && Calendar.current.isDateInToday($0.playedAt) }

        return Button {
            activeGame = GameRequest(title: "Daily Challenge", kind: .daily, subjectID: nil, questions: questions)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("DAILY").font(.caption.weight(.bold))
                    Spacer()
                    Text(doneToday ? "Done" : "+\(MasteryConfig.standard.dailyChallengeBonus) XP")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.22), in: Capsule())
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Test what you remember")
                        .font(.title3.bold())
                        .multilineTextAlignment(.leading)
                    Text("\(questions.count) questions · 3 min")
                        .font(.footnote)
                        .opacity(0.9)
                }
                Spacer(minLength: 0)
                Label(doneToday ? "Again" : "Start", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(.white, in: Capsule())
                    .foregroundStyle(Accent.color)
            }
            .foregroundStyle(.white)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Accent.color.gradient, in: .rect(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .disabled(questions.isEmpty)
        .accessibilityHint("Starts the Daily Challenge")
    }

    private func reviewCard(snapshot: MasterySnapshot) -> some View {
        let due = mastery.dueQuestions(from: content.questions, snapshot: snapshot, limit: Self.reviewLimit)

        return Button {
            activeGame = GameRequest(title: "Spaced Review", kind: .review, subjectID: nil, questions: due)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Text("REVIEW")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                ProgressRing(progress: Double(due.count) / Double(Self.reviewLimit), lineWidth: 6) {
                    Text("\(due.count)").font(.headline.monospacedDigit())
                }
                .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(due.isEmpty ? "All caught up" : "Due now")
                        .font(.headline)
                    Text(due.isEmpty ? "Come back tomorrow" : "What you're close to forgetting")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                if !due.isEmpty {
                    Text("Review · \(max(1, due.count / 3)) min")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .disabled(due.isEmpty)
        .accessibilityElement(children: .combine)
    }

    // MARK: Quick play

    private struct Mode: Identifiable {
        let name: String
        let detail: String
        let symbol: String
        let available: Bool
        var id: String { name }
    }

    private let modes: [Mode] = [
        Mode(name: "Quick Quiz", detail: "10 from every subject", symbol: "questionmark.circle", available: true),
        Mode(name: "Verse Match", detail: "Reference ↔ text", symbol: "list.bullet", available: false),
        Mode(name: "Timeline", detail: "Put events in order", symbol: "calendar.day.timeline.left", available: false),
        Mode(name: "Fill the Blank", detail: "Mastery passages", symbol: "text.line.first.and.arrowtriangle.forward", available: false),
    ]

    private var quickPlay: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick play").font(.title2.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(modes) { mode in
                        Button {
                            guard gamesUnlocked else {
                                showsPaywall = true
                                return
                            }
                            activeGame = GameRequest(title: mode.name, kind: .review, subjectID: nil, questions: Array(content.questions.shuffled().prefix(10)))
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top) {
                                    SymbolTile(systemName: mode.symbol, size: 38)
                                    Spacer()
                                    if mode.available, !gamesUnlocked {
                                        lockBadge(onColor: false)
                                    } else if !mode.available {
                                        Text("Soon")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(.quaternary, in: Capsule())
                                    }
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mode.name).font(.subheadline.weight(.semibold))
                                    Text(mode.detail).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(14)
                            .frame(width: min(quickPlayWidth, 260), alignment: .leading)
                            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
                            .opacity(mode.available ? 1 : 0.6)
                        }
                        .buttonStyle(.plain)
                        .disabled(!mode.available || content.questions.isEmpty)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, -16)
            .scrollClipDisabled()
        }
    }

    // MARK: Subjects

    /// Subjects with a Scholar Path first, each with its medal in a ring toward the next badge.
    private func subjectsGrid(snapshot: MasterySnapshot) -> some View {
        let subjects = content.subjects.sorted { lhs, rhs in
            let l = PathCatalog.shared.path(for: lhs.id) != nil, r = PathCatalog.shared.path(for: rhs.id) != nil
            return l && !r
        }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your subjects").font(.title2.bold())
                Spacer()
                NavigationLink("Badges") { BadgesView() }
                    .font(.body)
            }
            ForEach(subjects) { subject in
                if let path = PathCatalog.shared.path(for: subject.id) {
                    NavigationLink {
                        SubjectDetailView(subject: subject)
                    } label: {
                        ScholarProgressReader(path: path) { progress in
                            PathSubjectCard(subject: subject, progress: progress)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    ComingSoonSubjectCard(subject: subject)
                }
            }
        }
    }
}

/// A subject with a Scholar Path: its medal in a ring toward the next badge, the rank, and
/// one line of status. When XP is reached the ring turns green and the line names what's left.
private struct PathSubjectCard: View {
    let subject: Subject
    let progress: ScholarProgress

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let rank = progress.rank
        let next = progress.nextRank
        // At accessibility sizes the medal, the name and Start stack, so Start never covers the name.
        AdaptiveStack(spacing: 12) {
            ScholarBadge(rank: rank ?? .novice, size: 72, status: rank == nil ? .locked : .earned,
                         progress: rank == nil || next == nil ? nil : progress.xpFraction,
                         tint: progress.xpReached ? Optional(Feedback.correct) : next?.palette.mid)
            VStack(alignment: .leading, spacing: 4) {
                Text(subject.name).font(.headline).multilineTextAlignment(.leading)
                if let rank {
                    (Text(rank.name).fontWeight(.semibold).foregroundStyle(rank.ink(dark: colorScheme == .dark))
                     + Text(next.map { " · next \($0.name)" } ?? "").foregroundStyle(.secondary))
                        .font(.footnote)
                    Text(statusLine)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(progress.xpReached && next != nil ? Feedback.correct : .secondary)
                } else {
                    Text("Not started · \(progress.path.publishedStages.count) stage\(progress.path.publishedStages.count == 1 ? "" : "s") published")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if rank == nil {
                Text("Start")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(.tint, in: Capsule())
            }
        }
        .padding(.vertical, 12)
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
        .contentShape(.rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the subject's Scholar Path")
    }

    private var statusLine: String {
        guard let next = progress.nextRank else { return "\(progress.xp.formatted()) XP · every rank so far earned" }
        if next == .novice { return "Finish any learning item" }
        let stage = progress.nextStage
        let done = stage.map { progress.coursesComplete(in: $0) } ?? 0
        let total = stage?.courses.count ?? 0
        let stageText = stage.map { progress.isComplete($0) ? "Stage \($0.number) done" : done == total ? "Stage \($0.number): check left" : "Stage \($0.number): \(done) of \(total)" } ?? ""
        if progress.xpReached { return "\(progress.xp.formatted()) / \(progress.threshold(next).formatted()) XP · \(stageText.isEmpty ? "XP reached" : stageText)" }
        return "\(progress.xp.formatted()) / \(progress.threshold(next).formatted()) XP · \(stageText)"
    }
}

/// A subject without a Scholar Path yet: its units and games are still here.
/// A subject that isn't built yet: grayed out, can't be opened.
private struct ComingSoonSubjectCard: View {
    let subject: Subject

    var body: some View {
        HStack(spacing: 12) {
            SymbolTile(systemName: subject.symbol, size: 52)
                .grayscale(1)
                .opacity(0.6)
                .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 6) {
                Text(subject.name).font(.headline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                ComingSoonTag()
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
        .opacity(0.8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(subject.name), coming soon")
    }
}

#Preview {
    NavigationStack { PlayView() }
        .previewEnvironment()
}
