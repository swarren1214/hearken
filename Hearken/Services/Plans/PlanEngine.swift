import Foundation

/// Builds schedules for enrollments and caches them, plus each chapter's word count
/// (the schedule balances days by words read, so long chapters get lighter days).
@MainActor
final class PlanEngine {
    static let shared = PlanEngine()

    private var wordCounts: [String: Int] = [:]
    private var schedules: [String: [PlanDay]] = [:]

    /// A chapter's word count; an average guess for chapters whose text isn't imported.
    func words(in chapterID: String, content: ContentService) -> Int {
        if let count = wordCounts[chapterID] { return count }
        let count = content.chapter(chapterID).map { chapter in
            chapter.verses.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
        } ?? 700
        wordCounts[chapterID] = max(count, 1)
        return max(count, 1)
    }

    /// The days of a plan from an anchor point (the start, or the last reschedule).
    func days(
        for plan: ReadingPlan,
        fromIndex index: Int,
        dayCount: Int,
        firstDayNumber: Int,
        start: Date,
        readingDays: ReadingDays,
        content: ContentService
    ) -> [PlanDay] {
        let key = "\(plan.id)|\(plan.chapterIDs.count)|\(plan.chapterIDs.first ?? "")|\(plan.chapterIDs.last ?? "")|\(index)|\(dayCount)|\(firstDayNumber)|\(start.timeIntervalSinceReferenceDate)|\(readingDays.rawValue)"
        if let cached = schedules[key] { return cached }
        let remaining = Array(plan.chapterIDs.dropFirst(min(index, plan.chapterIDs.count)))
        guard !remaining.isEmpty else { return [] }
        let result = PlanScheduler.days(
            chapterIDs: remaining,
            words: remaining.map { words(in: $0, content: content) },
            dayCount: max(1, dayCount),
            firstDayNumber: firstDayNumber,
            start: start,
            readingDays: readingDays
        )
        if schedules.count > 24 { schedules.removeAll() }
        schedules[key] = result
        return result
    }

    func state(for enrollment: PlanEnrollment, content: ContentService, read: Set<String>, now: Date = .now) -> PlanState? {
        guard let plan = ReadingPlanCatalog.plan(for: enrollment) else { return nil }
        let days = days(
            for: plan,
            fromIndex: enrollment.anchorIndex,
            dayCount: enrollment.anchorDays,
            firstDayNumber: enrollment.anchorDayNumber,
            start: enrollment.anchorDate,
            readingDays: ReadingDays(rawValue: enrollment.readingDays),
            content: content
        )
        let total = (days.last?.number ?? enrollment.totalDays)
        return PlanState(plan: plan, days: days, read: read, totalDays: total, now: now)
    }

    /// A preview for the start sheet: the days a new plan would have.
    func preview(plan: ReadingPlan, dayCount: Int, start: Date, readingDays: ReadingDays, content: ContentService) -> [PlanDay] {
        days(for: plan, fromIndex: 0, dayCount: dayCount, firstDayNumber: 1, start: start, readingDays: readingDays, content: content)
    }

    /// Moves the schedule so the first unfinished day starts today and every remaining day
    /// keeps its length. The end date moves out by however many days were behind.
    func reschedule(_ enrollment: PlanEnrollment, state: PlanState, now: Date = .now) {
        guard let firstPending = state.days.first(where: { !state.isDone($0) }), let last = state.days.last else { return }
        let firstUnread = state.plan.chapterIDs.firstIndex { !state.read.contains($0) } ?? state.plan.chapterIDs.count
        enrollment.anchorDate = Calendar.current.startOfDay(for: now)
        enrollment.anchorIndex = firstUnread
        enrollment.anchorDays = last.number - firstPending.number + 1
        enrollment.anchorDayNumber = firstPending.number
    }
}
