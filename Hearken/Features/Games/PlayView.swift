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
    @AppStorage(SettingsKey.accent) private var accent: AccentOption = .blue
    @State private var activeGame: GameRequest?

    private let mastery = MasteryService()
    private static let reviewLimit = 10

    var body: some View {
        let snapshot = MasterySnapshot(reviews: reviews, progress: progress)
        let level = MasteryMath.level(forXP: xpEvents.reduce(0) { $0 + $1.amount })
        let streak = MasteryMath.streak(activityDates: xpEvents.map(\.createdAt), now: .now)

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 12) {
                    dailyCard(snapshot: snapshot)
                    reviewCard(snapshot: snapshot)
                }
                .fixedSize(horizontal: false, vertical: true)

                quickPlay
                subjectsGrid(snapshot: snapshot)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Play")
        .navigationSubtitle("Level \(level.level)")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                    Text("\(streak)").monospacedDigit()
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 8)
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(streak) day streak")
            }
        }
        .fullScreenCover(item: $activeGame) { GameView(request: $0) }
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
                    .foregroundStyle(accent.color)
            }
            .foregroundStyle(.white)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(accent.color.gradient, in: .rect(cornerRadius: 24))
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
                            activeGame = GameRequest(title: mode.name, kind: .review, subjectID: nil, questions: Array(content.questions.shuffled().prefix(10)))
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top) {
                                    SymbolTile(systemName: mode.symbol, size: 38)
                                    Spacer()
                                    if !mode.available {
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
                            .frame(width: 140, alignment: .leading)
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

    private func subjectsGrid(snapshot: MasterySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Subjects").font(.title2.bold())
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(content.subjects) { subject in
                    subjectCard(subject, mastery: mastery.subjectMastery(subject, content: content, snapshot: snapshot))
                }
            }
        }
    }

    private func subjectCard(_ subject: Subject, mastery value: Double) -> some View {
        let questions = content.questions(forSubject: subject.id)
        let percent = Int((value * 100).rounded())
        let tier = Tier(mastery: value)

        return NavigationLink {
            SubjectDetailView(subject: subject)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    SymbolTile(systemName: subject.symbol, size: 38)
                    Spacer()
                    ProgressRing(progress: value, lineWidth: 4) {
                        Text("\(percent)").font(.caption2.weight(.bold).monospacedDigit())
                    }
                    .frame(width: 40, height: 40)
                }
                Text(subject.name)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                Text(tier.name)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(height: 34)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 156, alignment: .topLeading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
            .contentShape(.rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(subject.name), \(percent) percent, \(tier.name)")
        .accessibilityHint("Opens the subject")
        .overlay(alignment: .bottomTrailing) {
            Button {
                activeGame = GameRequest(title: "Chronology Challenge", kind: .chronology, subjectID: subject.id, questions: questions.shuffled())
            } label: {
                Image(systemName: "play.fill")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(questions.isEmpty ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(.tint), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(questions.isEmpty)
            .padding(14)
            .accessibilityLabel("Play \(subject.name)")
        }
    }
}

#Preview {
    NavigationStack { PlayView() }
        .previewEnvironment()
}
