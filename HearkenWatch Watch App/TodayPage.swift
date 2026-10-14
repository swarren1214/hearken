import SwiftUI

/// Today's reading-plan chapters, the streak, and a button to start listening on the iPhone.
struct TodayPage: View {
    @Environment(WatchStore.self) private var store
    /// Moves to the Listen remote after starting today's reading.
    var showRemote: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if let plan = store.plan {
                    planView(plan)
                } else {
                    ContentUnavailableView {
                        Label("No Reading Plan", systemImage: "book.closed")
                    } description: {
                        Text("Start one in Hearken on your iPhone, in Library › Reading Plans.")
                    }
                }
            }
            .navigationTitle("Hearken")
        }
    }

    private func planView(_ plan: PlanSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.finished ? "PLAN COMPLETE" : plan.isReadingDay ? "TODAY'S READING" : "NEXT READING")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(plan.todayRange)
                        .font(.system(.title3, design: .serif).weight(.bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text("Day \(plan.dayNumber) of \(plan.totalDays) · about \(plan.minutes) min")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(plan.todayChapters, id: \.chapterID) { chapter in
                        Label(chapter.name, systemImage: chapter.done ? "checkmark.circle.fill" : "circle")
                            .font(.body.weight(.medium))
                            .foregroundStyle(chapter.done ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    }
                }

                Label("\(plan.streak)-day streak", systemImage: "flame.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)

                if !plan.finished && !plan.todayDone {
                    Button {
                        store.send(.listenToday)
                        showRemote()
                    } label: {
                        Label("Listen on iPhone", systemImage: "headphones")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
                }

                if let problem = store.problem {
                    Text(problem)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    TodayPage {}
        .environment(WatchStore.shared)
}
