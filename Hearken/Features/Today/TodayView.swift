import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(ContentService.self) private var content
    @Query private var reviews: [ItemReview]
    @Query private var progress: [ReadingProgress]
    @Query private var xpEvents: [XPEvent]
    @Query private var highlights: [Highlight]
    @Query private var notes: [Note]
    @Query(sort: \GameSession.playedAt, order: .reverse) private var sessions: [GameSession]
    @Query(sort: \PlanEnrollment.createdAt, order: .reverse) private var enrollments: [PlanEnrollment]
    @Query private var awards: [SubjectAward]
    @Query private var grants: [RankGrant]
    @State private var showSettings = false
    @State private var activeGame: GameRequest?
    @AppStorage(SettingsKey.accent) private var accent: AccentOption = .blue

    private let mastery = MasteryService()

    var body: some View {
        let snapshot = MasterySnapshot(reviews: reviews, progress: progress)
        let totalXP = AccountXP.total(events: xpEvents, awards: awards)
        let streak = MasteryMath.streak(activityDates: xpEvents.map(\.createdAt), now: .now)

        let plan = PlanReading.active(enrollments)
        let planState = plan.flatMap { PlanEngine.shared.state(for: $0, content: content, read: PlanReading.readSet(progress)) }

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let plan, let planState {
                        // A running plan leads; the Daily Challenge steps down to a row.
                        PlanTodayCard(state: planState, enrollment: plan)
                        compactDailyChallenge(snapshot: snapshot)
                    } else {
                        dailyChallenge(snapshot: snapshot)
                        StartPlanCard()
                    }
                    GroupsSection(defaultPlanID: plan?.planID, customPlan: planState.flatMap { $0.plan.isCustom ? $0.plan : nil })
                    progressCard(totalXP: totalXP)
                    continueReading
                        .id(TourController.Step.today)
                        .tourTarget(.today)
                    subjectsSection(snapshot: snapshot)
                }
                // Exactly the screen's width (less the margins): a row that comes out too wide for
                // very large text can't widen the page and push every other section off its edges.
                .containerRelativeFrame(.horizontal, alignment: .leading) { width, _ in max(width - 32, 0) }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                        Text("\(streak)")
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .fixedSize()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(streak) day streak")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Profile and settings", systemImage: "person.crop.circle") { showSettings = true }
                        .tint(Color.primary)
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView() }
            }
            .fullScreenCover(item: $activeGame) { request in
                GameView(request: request)
            }
            // The tour's first step points at Continue Reading; bring it on screen first.
            .onChange(of: TourController.shared.step) { _, step in
                guard step == .today else { return }
                withAnimation { proxy.scrollTo(TourController.Step.today, anchor: .center) }
            }
            // The tour ended with Start Reading: open where they left off.
            .onChange(of: TourController.shared.startReadingRequested) { _, requested in
                guard requested else { return }
                TourController.shared.startReadingRequested = false
                let last = progress.max(by: { $0.updatedAt < $1.updatedAt })
                AppNavigator.shared.open(chapterID: last?.chapterID ?? content.defaultChapterID)
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private func dailyChallenge(snapshot: MasterySnapshot) -> some View {
        let doneToday = sessions.contains { $0.gameType == GameKind.daily.rawValue && Calendar.current.isDateInToday($0.playedAt) }
        let questions = mastery.dailyChallenge(content: content, snapshot: snapshot)

        Button {
            activeGame = GameRequest(title: "Daily Challenge", kind: .daily, subjectID: nil, questions: questions)
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("DAILY CHALLENGE")
                        .font(.footnote.weight(.semibold))
                    Spacer()
                    Text(doneToday ? "Done" : "+\(MasteryConfig.standard.dailyChallengeBonus) XP")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.2), in: Capsule())
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Test what you remember")
                        .font(.title2.bold())
                    Text("\(questions.count) questions · about 3 minutes")
                        .font(.subheadline)
                        .opacity(0.9)
                }
                AdaptiveStack(spacing: 12) {
                    Text("Picked from what you're most likely to forget")
                        .font(.footnote)
                        .opacity(0.9)
                    Spacer()
                    Text(doneToday ? "Play again" : "Start")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18)
                        .frame(height: 40)
                        .background(.white, in: Capsule())
                        .foregroundStyle(.tint)
                }
            }
            .foregroundStyle(.white)
            .padding(20)
            .background(accent.color.gradient, in: .rect(cornerRadius: 26))
        }
        .buttonStyle(.plain)
        .disabled(questions.isEmpty)
    }

    private func compactDailyChallenge(snapshot: MasterySnapshot) -> some View {
        let doneToday = sessions.contains { $0.gameType == GameKind.daily.rawValue && Calendar.current.isDateInToday($0.playedAt) }
        let questions = mastery.dailyChallenge(content: content, snapshot: snapshot)

        return Button {
            activeGame = GameRequest(title: "Daily Challenge", kind: .daily, subjectID: nil, questions: questions)
        } label: {
            AdaptiveStack(spacing: 14) {
                SymbolTile(systemName: "sun.max.fill", size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily Challenge").font(.headline)
                    Text(doneToday ? "Done today · play again for practice" : "\(questions.count) questions · +\(MasteryConfig.standard.dailyChallengeBonus) XP")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(doneToday ? "Again" : "Start")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .background(accent.color, in: Capsule())
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(questions.isEmpty)
    }

    /// Account XP and the best badge earned so far. (Subject ranks live on each subject.)
    private func progressCard(totalXP: Int) -> some View {
        let best = grants.max { $0.rankRaw < $1.rankRaw }?.rank
        let badges = Set(grants.map { "\($0.subjectID)|\($0.rankRaw)" }).count
        return VStack(alignment: .leading, spacing: 8) {
            Text("Progress").font(.title2.bold())
            Card {
                AdaptiveStack(spacing: 18) {
                    if let best {
                        ScholarBadge(rank: best, size: 88)
                    } else {
                        ScholarBadge(rank: .novice, size: 88, status: .locked)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(totalXP.formatted()) XP").font(.title3.bold()).monospacedDigit()
                            Text(badges == 0 ? "Earn badges on the Scholar Path" : "\(badges) badge\(badges == 1 ? "" : "s") earned")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        AdaptiveStack(spacing: 16) {
                            Stat(value: highlights.count, label: "Marked")
                            Stat(value: notes.count, label: "Notes")
                            Stat(value: sessions.count, label: "Games")
                        }
                    }
                }
            }
        }
    }

    private var continueReading: some View {
        let last = progress.max(by: { $0.updatedAt < $1.updatedAt })
        let chapterID = last?.chapterID ?? content.defaultChapterID

        return NavigationLink {
            ReaderView(chapterID: chapterID)
        } label: {
            HStack(spacing: 14) {
                SymbolTile(systemName: "book.fill", size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(last == nil ? "Start reading" : "Continue reading")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(content.title(forChapter: chapterID))
                        .font(.scripture(size: 19, weight: .semibold))
                    if let verse = last?.lastVerse, verse > 0 {
                        Text("Verse \(verse)").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
    }

    private func subjectsSection(snapshot: MasterySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Subjects").font(.title2.bold())
            VStack(spacing: 0) {
                ForEach(content.subjects) { subject in
                    if subject.isAvailable {
                        NavigationLink {
                            SubjectDetailView(subject: subject)
                        } label: {
                            SubjectRow(subject: subject, mastery: mastery.subjectMastery(subject, content: content, snapshot: snapshot))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    } else {
                        SubjectRow(subject: subject, mastery: 0, comingSoon: true)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                    if subject.id != content.subjects.last?.id {
                        Divider().padding(.leading, 62)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
        }
    }
}

private struct Stat: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading) {
            Text(value.formatted()).font(.headline.monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A subject with its symbol, mastery bar and tier. Used on Today and Subjects.
struct SubjectRow: View {
    let subject: Subject
    let mastery: Double
    /// Off inside a List, where NavigationLink already draws the chevron.
    var showsChevron = true
    /// Not built yet: grayed out, with a Coming Soon tag instead of mastery.
    var comingSoon = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// One line at ordinary sizes; long names wrap at accessibility sizes instead of being cut off.
    private var nameLines: Int? { dynamicTypeSize.isAccessibilitySize ? nil : 1 }

    var body: some View {
        HStack(spacing: 12) {
            SymbolTile(systemName: subject.symbol)
                .grayscale(comingSoon ? 1 : 0)
                .opacity(comingSoon ? 0.6 : 1)
            if comingSoon {
                Text(subject.name).font(.body).foregroundStyle(.secondary).lineLimit(nameLines)
                Spacer()
                ComingSoonTag()
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(subject.name).font(.body).lineLimit(nameLines)
                        Spacer()
                        Text(mastery.formatted(.percent.precision(.fractionLength(0))))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    MasteryBar(value: mastery)
                }
            }
            if showsChevron && !comingSoon {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack { TodayView() }
        .previewEnvironment()
}
