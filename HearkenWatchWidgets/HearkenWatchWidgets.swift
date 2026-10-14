import SwiftUI
import WidgetKit

// The watch widget extension: today's reading in the Smart Stack and on watch faces.
// Reads the snapshot the watch app saves to its App Group whenever the iPhone sends a new one
// (see WatchStore), so it stays current without opening anything.

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: PlanSnapshot?
    /// Pushes the widget up the Smart Stack while today's reading is still to do, more so in the evening.
    let relevance: TimelineEntryRelevance?
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, snapshot: .sample, relevance: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        let snapshot = context.isPreview ? .sample : PlanSnapshotStore.load() ?? .sample
        completion(TodayEntry(date: .now, snapshot: snapshot, relevance: nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let snapshot = PlanSnapshotStore.load()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let evening = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: today) ?? .now
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? .now

        var entries = [TodayEntry(date: .now, snapshot: snapshot, relevance: relevance(snapshot, evening: false))]
        if evening > .now {
            entries.append(TodayEntry(date: evening, snapshot: snapshot, relevance: relevance(snapshot, evening: true)))
        }
        // The watch app reloads this whenever the iPhone sends news; refresh after midnight for the new day too.
        completion(Timeline(entries: entries, policy: .after(tomorrow.addingTimeInterval(60))))
    }

    private func relevance(_ plan: PlanSnapshot?, evening: Bool) -> TimelineEntryRelevance? {
        guard let plan, plan.isReadingDay, !plan.finished, !plan.todayDone else {
            return TimelineEntryRelevance(score: 0)
        }
        return TimelineEntryRelevance(score: evening ? 80 : 30)
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        Group {
            if let plan = entry.snapshot {
                switch family {
                case .accessoryCircular: circular(plan)
                case .accessoryCorner: corner(plan)
                case .accessoryInline: inline(plan)
                default: rectangular(plan)
                }
            } else {
                Label("No reading plan", systemImage: "book.closed")
                    .font(.footnote)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    /// Today's chapters read, as a ring.
    private func todayProgress(_ plan: PlanSnapshot) -> Double {
        guard !plan.todayChapters.isEmpty else { return plan.fraction }
        return Double(plan.chaptersDone) / Double(plan.todayChapters.count)
    }

    private func circular(_ plan: PlanSnapshot) -> some View {
        Gauge(value: todayProgress(plan)) {
            Image(systemName: "book.fill")
        } currentValueLabel: {
            if plan.todayDone {
                Image(systemName: "checkmark")
            } else {
                Text("\(plan.chaptersDone)/\(plan.todayChapters.count)")
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
    }

    private func corner(_ plan: PlanSnapshot) -> some View {
        Image(systemName: plan.todayDone ? "checkmark.circle.fill" : "book.fill")
            .font(.title3)
            .widgetAccentable()
            .widgetLabel {
                Gauge(value: todayProgress(plan)) {
                    Text("Reading")
                }
            }
    }

    private func inline(_ plan: PlanSnapshot) -> some View {
        Label(plan.todayDone ? "Read today · \(plan.streak) days" : plan.todayRange, systemImage: plan.todayDone ? "flame.fill" : "book.fill")
    }

    private func rectangular(_ plan: PlanSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(plan.isReadingDay ? plan.todayRange : "Rest day", systemImage: plan.todayDone ? "checkmark.circle.fill" : "book.fill")
                .font(.headline)
                .lineLimit(1)
                .widgetAccentable()
            Text(plan.todayDone ? "Done for today" : "\(plan.chaptersDone) of \(plan.todayChapters.count) read · \(plan.minutes) min")
                .font(.caption)
            Text("\(plan.streak)-day streak")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TodayReadingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchTodayReading", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Today's Reading")
        .description("Your reading plan for today and your streak.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

@main
struct HearkenWatchWidgets: WidgetBundle {
    var body: some Widget {
        TodayReadingWidget()
    }
}

#Preview(as: .accessoryRectangular) {
    TodayReadingWidget()
} timeline: {
    TodayEntry(date: .now, snapshot: .sample, relevance: nil)
}
