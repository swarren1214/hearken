import SwiftData
import SwiftUI

struct SubjectsView: View {
    @Environment(ContentService.self) private var content
    @Query private var reviews: [ItemReview]
    @Query private var progress: [ReadingProgress]

    private let mastery = MasteryService()

    var body: some View {
        let snapshot = MasterySnapshot(reviews: reviews, progress: progress)
        List(content.subjects) { subject in
            NavigationLink {
                SubjectDetailView(subject: subject)
            } label: {
                SubjectRow(subject: subject, mastery: mastery.subjectMastery(subject, content: content, snapshot: snapshot))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Subjects")
    }
}

struct SubjectDetailView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case learn = "Learn", play = "Play", library = "Library"
        var id: String { rawValue }
    }

    let subject: Subject

    @Environment(ContentService.self) private var content
    @Query private var reviews: [ItemReview]
    @Query private var progress: [ReadingProgress]
    @State private var pane: Pane = .learn
    @State private var activeGame: GameRequest?

    private let mastery = MasteryService()

    var body: some View {
        let snapshot = MasterySnapshot(reviews: reviews, progress: progress)
        let subjectMastery = mastery.subjectMastery(subject, content: content, snapshot: snapshot)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(subject.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                masteryCard(subjectMastery)

                Picker("Section", selection: $pane) {
                    ForEach(Pane.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                switch pane {
                case .learn: learn(snapshot: snapshot)
                case .play: play(snapshot: snapshot)
                case .library: library
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(subject.name)
        .fullScreenCover(item: $activeGame) { GameView(request: $0) }
    }

    private func masteryCard(_ value: Double) -> some View {
        let tier = Tier(mastery: value)
        let next = Tier.allCases.first { $0 > tier }
        return Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    ProgressRing(progress: value, lineWidth: 10) {
                        Text(value.formatted(.percent.precision(.fractionLength(0))))
                            .font(.headline.monospacedDigit())
                    }
                    .frame(width: 76, height: 76)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Mastery").font(.footnote).foregroundStyle(.secondary)
                        Text(tier.name).font(.title2.bold())
                        if let next {
                            let points = Int(((next.lowerBound - value) * 100).rounded(.up))
                            Text("\(points) points to \(next.name)").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                TierBar(mastery: value)
            }
        }
    }

    // MARK: Learn

    private func learn(snapshot: MasterySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("UNITS").font(.footnote).foregroundStyle(.secondary).padding(.leading, 16)
            VStack(spacing: 0) {
                ForEach(subject.units) { unit in
                    let value = mastery.unitMastery(unit, content: content, snapshot: snapshot)
                    NavigationLink {
                        UnitView(subject: subject, unit: unit)
                    } label: {
                        HStack(spacing: 14) {
                            ProgressRing(progress: value, lineWidth: 4) {
                                Text("\(unit.number)").font(.caption.bold())
                            }
                            .frame(width: 34, height: 34)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(unit.title).font(.body).multilineTextAlignment(.leading)
                                Text("\(unit.range) · \(value.formatted(.percent.precision(.fractionLength(0))))")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    if unit.id != subject.units.last?.id {
                        Divider().padding(.leading, 64)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
        }
    }

    // MARK: Play

    private func play(snapshot: MasterySnapshot) -> some View {
        let questions = content.questions(forSubject: subject.id)
        let due = mastery.dueQuestions(from: questions, snapshot: snapshot, limit: 10)

        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            GameTile(symbol: "calendar.day.timeline.left", kind: "TIMELINE", name: "Chronology Challenge", detail: "Events and people in the order they happened.", status: questions.isEmpty ? "Coming soon" : "\(questions.count) questions") {
                activeGame = GameRequest(title: "Chronology Challenge", kind: .chronology, subjectID: subject.id, questions: questions.shuffled())
            }
            .disabled(questions.isEmpty)

            GameTile(symbol: "arrow.counterclockwise", kind: "REVIEW", name: "Spaced Review", detail: "Questions picked from what you're about to forget.", status: due.isEmpty ? "All caught up" : "\(due.count) due") {
                activeGame = GameRequest(title: "Spaced Review", kind: .review, subjectID: subject.id, questions: due)
            }
            .disabled(due.isEmpty)

            GameTile(symbol: "quote.bubble", kind: "MATCHING", name: "Who Said It?", detail: "Match a passage to the person who spoke it.", status: "Coming soon") {}
                .disabled(true)

            GameTile(symbol: "map", kind: "GEOGRAPHY", name: "Map Quest", detail: "Place cities and events on the map.", status: "Coming soon") {}
                .disabled(true)
        }
    }

    // MARK: Library

    private var library: some View {
        let groups = Resource.Kind.allCases.compactMap { kind -> ResourceGroup? in
            let items = subject.resources.filter { $0.kind == kind }
            return items.isEmpty ? nil : ResourceGroup(kind: kind, items: items)
        }
        return VStack(alignment: .leading, spacing: 18) {
            ForEach(groups) { group in
                let items = group.items
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.kind.title.uppercased()).font(.footnote).foregroundStyle(.secondary).padding(.leading, 16)
                    VStack(spacing: 0) {
                        ForEach(items) { resource in
                            ResourceRow(resource: resource)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            if resource.id != items.last?.id {
                                Divider().padding(.leading, 62)
                            }
                        }
                    }
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
                }
            }
        }
    }
}

private struct ResourceGroup: Identifiable {
    let kind: Resource.Kind
    let items: [Resource]
    var id: String { kind.rawValue }
}

private struct GameTile: View {
    let symbol: String
    let kind: String
    let name: String
    let detail: String
    let status: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                SymbolTile(systemName: symbol, size: 38)
                Text(kind).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text(name).font(.headline).multilineTextAlignment(.leading)
                Text(detail).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Text(status).font(.caption.weight(.semibold)).foregroundStyle(isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
            .opacity(isEnabled ? 1 : 0.6)
        }
        .buttonStyle(.plain)
    }
}

private struct ResourceRow: View {
    let resource: Resource

    var body: some View {
        if let chapterID = resource.chapterID {
            NavigationLink { ReaderView(chapterID: chapterID) } label: { row(trailing: "chevron.right") }
                .buttonStyle(.plain)
        } else if let url = resource.url {
            Link(destination: url) { row(trailing: "arrow.up.right") }
                .buttonStyle(.plain)
        } else {
            row(trailing: nil)
        }
    }

    private func row(trailing: String?) -> some View {
        HStack(spacing: 12) {
            SymbolTile(systemName: resource.kind.symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(resource.title).font(.body).multilineTextAlignment(.leading)
                Text(resource.author).font(.footnote).foregroundStyle(.secondary)
                if let note = resource.note {
                    Text(note).font(.caption).foregroundStyle(.tint)
                }
            }
            Spacer()
            if let trailing {
                Image(systemName: trailing).font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// A unit's lesson: its readings and a five-question check.
struct UnitView: View {
    let subject: Subject
    let unit: StudyUnit

    @Environment(ContentService.self) private var content
    @Query private var progress: [ReadingProgress]
    @State private var activeGame: GameRequest?

    var body: some View {
        let completed = Set(progress.filter { $0.completedAt != nil }.map(\.chapterID))
        let questions = content.questions(forUnit: unit.id)

        List {
            Section {
                Text(unit.range).foregroundStyle(.secondary)
            }

            Section("Reading") {
                if unit.readingChapterIDs.isEmpty {
                    Text("Readings for this unit are being prepared.")
                        .foregroundStyle(.secondary)
                }
                ForEach(unit.readingChapterIDs, id: \.self) { chapterID in
                    NavigationLink {
                        ReaderView(chapterID: chapterID)
                    } label: {
                        Label {
                            Text(content.title(forChapter: chapterID))
                        } icon: {
                            Image(systemName: completed.contains(chapterID) ? "checkmark.circle.fill" : "book")
                                .foregroundStyle(completed.contains(chapterID) ? AnyShapeStyle(.green) : AnyShapeStyle(.tint))
                        }
                    }
                }
            }

            Section {
                Button {
                    activeGame = GameRequest(title: "Unit \(unit.number) Check", kind: .unitCheck, subjectID: subject.id, questions: Array(questions.shuffled().prefix(5)))
                } label: {
                    Label("Start Unit Check", systemImage: "checklist")
                }
                .disabled(questions.isEmpty)
            } footer: {
                Text(questions.isEmpty ? "Questions for this unit are coming soon." : "\(min(questions.count, 5)) questions from this unit.")
            }
        }
        .navigationTitle("Unit \(unit.number): \(unit.title)")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $activeGame) { GameView(request: $0) }
    }
}

#Preview {
    NavigationStack { SubjectsView() }
        .previewEnvironment()
}
