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
    @State private var showSettings = false
    @State private var activeGame: GameRequest?
    @AppStorage(SettingsKey.accent) private var accent: AccentOption = .blue

    private let mastery = MasteryService()

    var body: some View {
        let snapshot = MasterySnapshot(reviews: reviews, progress: progress)
        let totalXP = xpEvents.reduce(0) { $0 + $1.amount }
        let level = MasteryMath.level(forXP: totalXP)
        let streak = MasteryMath.streak(activityDates: xpEvents.map(\.createdAt), now: .now)

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                dailyChallenge(snapshot: snapshot)
                progressCard(level: level)
                continueReading
                subjectsSection(snapshot: snapshot)
            }
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
                HStack {
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

    private func progressCard(level: LevelProgress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Progress").font(.title2.bold())
            Card {
                HStack(spacing: 18) {
                    ProgressRing(progress: level.fraction, lineWidth: 12) {
                        VStack(spacing: 0) {
                            Text("\(level.level)").font(.title2.bold().monospacedDigit())
                            Text("LEVEL").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 88, height: 88)
                    .accessibilityLabel("Level \(level.level)")

                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(level.xpToNext.formatted()) XP to Level \(level.level + 1)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        HStack(spacing: 16) {
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
                    NavigationLink {
                        SubjectDetailView(subject: subject)
                    } label: {
                        SubjectRow(subject: subject, mastery: mastery.subjectMastery(subject, content: content, snapshot: snapshot))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
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

    var body: some View {
        HStack(spacing: 12) {
            SymbolTile(systemName: subject.symbol)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(subject.name).font(.body).lineLimit(1)
                    Spacer()
                    Text(mastery.formatted(.percent.precision(.fractionLength(0))))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                MasteryBar(value: mastery)
                Text(Tier(mastery: mastery).name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if showsChevron {
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
