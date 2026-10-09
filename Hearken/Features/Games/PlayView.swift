import SwiftData
import SwiftUI

/// The Play tab: today's challenge, review, and a game per subject.
struct PlayView: View {
    @Environment(ContentService.self) private var content
    @Query private var reviews: [ItemReview]
    @Query private var progress: [ReadingProgress]
    @State private var activeGame: GameRequest?

    private let mastery = MasteryService()

    var body: some View {
        let snapshot = MasterySnapshot(reviews: reviews, progress: progress)
        let daily = mastery.dailyChallenge(content: content, snapshot: snapshot)
        let due = mastery.dueQuestions(from: content.questions, snapshot: snapshot, limit: 10)

        List {
            Section {
                gameRow(symbol: "sun.max.fill", title: "Daily Challenge", detail: "\(daily.count) questions from your weakest areas") {
                    activeGame = GameRequest(title: "Daily Challenge", kind: .daily, subjectID: nil, questions: daily)
                }
                .disabled(daily.isEmpty)

                gameRow(symbol: "arrow.counterclockwise", title: "Spaced Review", detail: due.isEmpty ? "All caught up" : "\(due.count) due across all subjects") {
                    activeGame = GameRequest(title: "Spaced Review", kind: .review, subjectID: nil, questions: due)
                }
                .disabled(due.isEmpty)
            }

            Section("By Subject") {
                ForEach(content.subjects) { subject in
                    let questions = content.questions(forSubject: subject.id)
                    gameRow(symbol: subject.symbol, title: subject.name, detail: questions.isEmpty ? "Questions coming soon" : "Chronology Challenge · \(questions.count) questions") {
                        activeGame = GameRequest(title: "Chronology Challenge", kind: .chronology, subjectID: subject.id, questions: questions.shuffled())
                    }
                    .disabled(questions.isEmpty)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Play")
        .fullScreenCover(item: $activeGame) { GameView(request: $0) }
    }

    private func gameRow(symbol: String, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                SymbolTile(systemName: symbol)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "play.fill").font(.footnote).foregroundStyle(.tint)
            }
        }
    }
}

#Preview {
    NavigationStack { PlayView() }
        .previewEnvironment()
}
