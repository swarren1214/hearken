import Foundation

/// The weekdays a plan reads on, as a bitmask: Sunday = 1 << 0 … Saturday = 1 << 6.
struct ReadingDays: OptionSet, Hashable {
    let rawValue: Int

    static let everyDay = ReadingDays(rawValue: 0b111_1111)
    static let weekdays = ReadingDays(rawValue: 0b011_1110)

    /// `weekday` as Calendar numbers it: 1 = Sunday … 7 = Saturday.
    func includes(weekday: Int) -> Bool {
        rawValue & (1 << (weekday - 1)) != 0
    }
}

/// One day's assignment.
struct PlanDay: Identifiable, Hashable {
    /// 1-based day number in the whole plan.
    let number: Int
    /// Start of that day.
    let date: Date
    let chapterIDs: [String]
    let minutes: Int
    var id: Int { number }
}

/// Pure scheduling: no storage, no UI. Tested in PlanScheduleTests.
enum PlanScheduler {
    /// Words read per minute, for the time estimates.
    static let wordsPerMinute = 200.0

    /// The next `count` reading dates on or after `start`.
    static func readingDates(from start: Date, count: Int, days: ReadingDays, calendar: Calendar = .current) -> [Date] {
        let mask = days.rawValue == 0 ? ReadingDays.everyDay : days
        var dates: [Date] = []
        var day = calendar.startOfDay(for: start)
        var guardrail = 0
        while dates.count < count, guardrail < 4000 {
            if mask.includes(weekday: calendar.component(.weekday, from: day)) { dates.append(day) }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
            guardrail += 1
        }
        return dates
    }

    /// Splits chapters (by weight) into `dayCount` runs in order, each at least one chapter,
    /// keeping every day as close as it can to an even share of what's left.
    static func partition(weights: [Double], into dayCount: Int) -> [Range<Int>] {
        let total = weights.count
        guard total > 0, dayCount > 0 else { return [] }
        let days = min(dayCount, total)
        var ranges: [Range<Int>] = []
        var start = 0
        var remaining = weights.reduce(0, +)
        for day in 0..<days {
            let daysLeft = days - day
            if daysLeft == 1 {
                ranges.append(start..<total)
                break
            }
            let target = remaining / Double(daysLeft)
            var end = start + 1
            var sum = weights[start]
            // Leave at least one chapter for each day still to come.
            while end < total - (daysLeft - 1) {
                let next = sum + weights[end]
                guard abs(next - target) <= abs(sum - target) else { break }
                sum = next
                end += 1
            }
            ranges.append(start..<end)
            start = end
            remaining -= sum
        }
        return ranges
    }

    /// Lays `chapterIDs` over `dayCount` reading days from `start`, balanced by word count.
    static func days(
        chapterIDs: [String],
        words: [Int],
        dayCount: Int,
        firstDayNumber: Int,
        start: Date,
        readingDays: ReadingDays,
        calendar: Calendar = .current
    ) -> [PlanDay] {
        let ranges = partition(weights: words.map(Double.init), into: dayCount)
        let dates = readingDates(from: start, count: ranges.count, days: readingDays, calendar: calendar)
        return zip(ranges, dates).enumerated().map { index, pair in
            let (range, date) = pair
            let wordCount = words[range].reduce(0, +)
            return PlanDay(
                number: firstDayNumber + index,
                date: date,
                chapterIDs: Array(chapterIDs[range]),
                minutes: max(1, Int((Double(wordCount) / wordsPerMinute).rounded(.up)))
            )
        }
    }
}

/// Where someone is in a plan, worked out from the schedule and what they've read.
struct PlanState {
    enum DayStatus { case done, missed, today, upcoming }

    let plan: ReadingPlan
    let days: [PlanDay]
    let read: Set<String>
    let today: Date
    let totalDays: Int
    let chaptersRead: Int

    init(plan: ReadingPlan, days: [PlanDay], read: Set<String>, totalDays: Int, now: Date = .now, calendar: Calendar = .current) {
        self.plan = plan
        self.days = days
        self.read = read
        self.totalDays = totalDays
        self.today = calendar.startOfDay(for: now)
        self.chaptersRead = plan.chapterIDs.reduce(0) { $0 + (read.contains($1) ? 1 : 0) }
    }

    var chaptersTotal: Int { plan.chapterIDs.count }
    var fraction: Double { chaptersTotal == 0 ? 0 : Double(chaptersRead) / Double(chaptersTotal) }
    var isFinished: Bool { chaptersTotal > 0 && chaptersRead == chaptersTotal }
    var endDate: Date? { days.last?.date }

    func isDone(_ day: PlanDay) -> Bool { day.chapterIDs.allSatisfy(read.contains) }

    func status(of day: PlanDay) -> DayStatus {
        if isDone(day) { return .done }
        if day.date < today { return .missed }
        return day.date == today ? .today : .upcoming
    }

    /// Today's assignment, or the next one when today isn't a reading day.
    var currentDay: PlanDay? { days.first { $0.date >= today } }
    var isReadingDayToday: Bool { currentDay?.date == today }

    /// Earlier days that aren't finished.
    var overdueDays: [PlanDay] { days.filter { $0.date < today && !isDone($0) } }
    var overdueChapterIDs: [String] { overdueDays.flatMap(\.chapterIDs).filter { !read.contains($0) } }
    var daysBehind: Int { overdueDays.count }

    var dayNumber: Int { currentDay?.number ?? totalDays }

    /// Where to start reading: the first unread chapter of anything overdue, then today, then ahead.
    var nextChapterID: String? {
        days.lazy.filter { $0.date <= today || $0 == currentDay }.flatMap(\.chapterIDs).first { !read.contains($0) }
            ?? days.lazy.flatMap(\.chapterIDs).first { !read.contains($0) }
    }

    /// "1 day behind", "On track", "Plan complete".
    var statusLine: String {
        if isFinished { return "Plan complete" }
        switch daysBehind {
        case 0: return "On track"
        case 1: return "1 day behind"
        default: return "\(daysBehind) days behind"
        }
    }
}
