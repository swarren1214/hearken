import SwiftUI
import WidgetKit

// The widget extension. Reads the snapshot the app writes to the shared App Group after
// every change (see PlanSnapshotStore in the app) and refreshes when the app asks.

struct PlanEntry: TimelineEntry {
    let date: Date
    let snapshot: PlanSnapshot?
}

struct PlanProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlanEntry { PlanEntry(date: .now, snapshot: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (PlanEntry) -> Void) {
        completion(PlanEntry(date: .now, snapshot: context.isPreview ? .sample : PlanSnapshotStore.load() ?? .sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PlanEntry>) -> Void) {
        // The app reloads timelines on changes; refresh after midnight for the new day too.
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) ?? .now
        completion(Timeline(entries: [PlanEntry(date: .now, snapshot: PlanSnapshotStore.load())], policy: .after(tomorrow.addingTimeInterval(60))))
    }
}

struct PlanWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PlanEntry

    var body: some View {
        Group {
            if let plan = entry.snapshot {
                switch family {
                case .systemMedium: medium(plan)
                case .accessoryCircular: circular(plan)
                case .accessoryRectangular: rectangular(plan)
                default: small(plan)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "calendar").font(.title2).foregroundStyle(.tint)
                    Text("Start a reading plan").font(.headline)
                    Text("Library › Reading Plans").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .widgetURL(entry.snapshot?.nextChapterID.map { URL(string: "hearken://read/\($0)")! })
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func ring(_ plan: PlanSnapshot, size: CGFloat, width: CGFloat) -> some View {
        ZStack {
            Circle().stroke(.tint.opacity(0.2), lineWidth: width)
            Circle().trim(from: 0, to: plan.fraction)
                .stroke(.tint, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(plan.fraction.formatted(.percent.precision(.fractionLength(0))))
                .font(.system(size: size * 0.24, weight: .bold).monospacedDigit())
        }
        .frame(width: size, height: size)
    }

    private func small(_ plan: PlanSnapshot) -> some View {
        VStack(alignment: .leading) {
            ring(plan, size: 56, width: 6)
            Spacer()
            Text(plan.finished ? "PLAN COMPLETE" : "DAY \(plan.dayNumber) OF \(plan.totalDays)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(plan.isReadingDay ? plan.todayRange : "Rest day")
                .font(.system(.title3, design: .serif).weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func medium(_ plan: PlanSnapshot) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.isReadingDay ? "TODAY'S READING" : "NEXT READING")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(plan.todayRange)
                    .font(.system(.title2, design: .serif).weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("About \(plan.minutes) minutes · \(plan.statusLine)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Label("\(plan.streak) days", systemImage: "flame.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(plan.todayChapters.prefix(4), id: \.chapterID) { chapter in
                    Label(chapter.name, systemImage: chapter.done ? "checkmark.circle.fill" : "circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(chapter.done ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                        .lineLimit(1)
                }
            }
            .frame(width: 110, alignment: .leading)
        }
    }

    private func circular(_ plan: PlanSnapshot) -> some View {
        Gauge(value: plan.fraction) {
            Image(systemName: "book.fill")
        } currentValueLabel: {
            Text(plan.fraction.formatted(.percent.precision(.fractionLength(0))))
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    private func rectangular(_ plan: PlanSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(plan.isReadingDay ? plan.todayRange : "Rest day", systemImage: "book.fill")
                .font(.headline)
                .widgetAccentable()
            Text("Day \(plan.dayNumber) of \(plan.totalDays)")
                .font(.caption)
            Text("\(plan.streak)-day streak")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct ReadingPlanWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ReadingPlan", provider: PlanProvider()) { entry in
            PlanWidgetView(entry: entry)
        }
        .configurationDisplayName("Reading Plan")
        .description("Today's reading and how far along you are.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

@main
struct HearkenWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ReadingPlanWidget()
    }
}

extension PlanSnapshot {
    static let sample = PlanSnapshot(
        title: "Book of Mormon in 90 Days", dayNumber: 38, totalDays: 90, fraction: 0.41, statusLine: "On track",
        isReadingDay: true, todayRange: "Alma 5–7",
        todayChapters: [
            Chapter(name: "Alma 5", chapterID: "bofm.alma.5", done: true),
            Chapter(name: "Alma 6", chapterID: "bofm.alma.6", done: false),
            Chapter(name: "Alma 7", chapterID: "bofm.alma.7", done: false),
        ],
        minutes: 18, streak: 12, nextChapterID: "bofm.alma.6", finished: false, updatedAt: .now
    )
}
