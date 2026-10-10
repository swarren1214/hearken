import SwiftData
import SwiftUI

/// Chapters marked read, the source of truth for plan progress.
enum PlanReading {
    static func readSet(_ progress: [ReadingProgress]) -> Set<String> {
        Set(progress.filter { $0.completedAt != nil }.map(\.chapterID))
    }

    static func active(_ enrollments: [PlanEnrollment]) -> PlanEnrollment? {
        enrollments.first { $0.endedAt == nil }
    }
}

/// Library › Reading Plans: your plan, then the plans you can start.
struct ReadingPlansView: View {
    @Environment(ContentService.self) private var content
    @Environment(AccountService.self) private var account
    @Query(sort: \PlanEnrollment.createdAt, order: .reverse) private var enrollments: [PlanEnrollment]
    @Query private var progress: [ReadingProgress]
    @AppStorage(SettingsKey.onboardingDone) private var onboardingDone = false
    @State private var starting: ReadingPlan?

    var body: some View {
        let active = PlanReading.active(enrollments)
        let read = PlanReading.readSet(progress)
        let past = enrollments.filter { $0.endedAt != nil }

        List {
            if let active, let state = PlanEngine.shared.state(for: active, content: content, read: read) {
                Section("Your Plan") {
                    NavigationLink {
                        PlanDetailView(enrollment: active)
                    } label: {
                        ActivePlanRow(state: state)
                    }
                }
            }

            Section {
                ForEach(ReadingPlanCatalog.plans) { plan in
                    Button { start(plan) } label: { PlanRow(plan: plan) }
                        .buttonStyle(.plain)
                }
                Button { start(ReadingPlanCatalog.custom) } label: { PlanRow(plan: ReadingPlanCatalog.custom) }
                    .buttonStyle(.plain)
            } header: {
                Text(active == nil ? "Start a Plan" : "Other Plans")
            } footer: {
                Text("Days are balanced by length, so a long chapter gets a lighter day. Your plan syncs through iCloud.")
            }

            if !past.isEmpty {
                Section("Past Plans") {
                    ForEach(past) { enrollment in
                        LabeledContent {
                            Text(enrollment.endedAt.map { PlanFormat.shortDate($0) } ?? "")
                        } label: {
                            Text(ReadingPlanCatalog.plan(for: enrollment)?.title ?? "Plan")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Reading Plans")
        .sheet(item: $starting) { plan in
            PlanStartSheet(plan: plan, replacing: active)
        }
    }

    private func start(_ plan: ReadingPlan) {
        starting = plan
    }
}

/// A plan's cover: a small book in the work's color.
struct PlanCover: View {
    let plan: ReadingPlan
    var width: CGFloat = 40

    var body: some View {
        UnevenRoundedRectangle(topLeadingRadius: width * 0.14, bottomLeadingRadius: width * 0.14, bottomTrailingRadius: width * 0.22, topTrailingRadius: width * 0.22)
            .fill(plan.coverColor.gradient)
            .overlay(alignment: .leading) {
                Rectangle().fill(.black.opacity(0.18)).frame(width: width * 0.08)
            }
            .overlay {
                Image(systemName: plan.isCustom ? "plus" : "book.closed")
                    .font(.system(size: width * 0.4, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: width * 0.14, bottomLeadingRadius: width * 0.14, bottomTrailingRadius: width * 0.22, topTrailingRadius: width * 0.22))
            .frame(width: width, height: width * 1.3)
            .accessibilityHidden(true)
    }
}

private struct PlanRow: View {
    let plan: ReadingPlan

    var body: some View {
        HStack(spacing: 14) {
            PlanCover(plan: plan)
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.title).font(.headline)
                Text(meta).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows the plan's schedule and starts it")
    }

    private var meta: String {
        if plan.isCustom { return plan.subtitle }
        let perDay = PlanFormat.perDay(chapters: plan.chapterIDs.count, days: plan.days)
        let unit = plan.id.hasPrefix("dc") ? "sections" : "chapters"
        return "\(plan.days) days · \(perDay) \(unit) a day"
    }
}

private struct ActivePlanRow: View {
    let state: PlanState

    var body: some View {
        HStack(spacing: 14) {
            ProgressRing(progress: state.fraction, lineWidth: 5) {
                Text(state.fraction.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption2.weight(.bold).monospacedDigit())
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.plan.title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        if state.isFinished { return "Plan complete" }
        guard let day = state.currentDay else { return state.statusLine }
        let when = state.isReadingDayToday ? "Today" : day.date.formatted(.dateTime.weekday(.abbreviated))
        return "Day \(day.number) of \(state.totalDays) · \(when): \(PlanFormat.range(day.chapterIDs))"
    }
}

// MARK: - Start

/// Starting a plan: what it asks of you each day, when you'd finish, and when to remind you.
struct PlanStartSheet: View {
    let plan: ReadingPlan
    let replacing: PlanEnrollment?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ContentService.self) private var content
    @AppStorage(SettingsKey.accent) private var accent: AccentOption = .blue

    @State private var startDate = Calendar.current.startOfDay(for: .now)
    @State private var weekdaysOnly = false
    @State private var reminder = true
    @State private var reminderTime = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: .now) ?? .now
    // Custom plans
    @State private var workID = LibraryCatalog.bookOfMormon.id
    @State private var firstBookID = ""
    @State private var lastBookID = ""
    @State private var customDays = 60
    @State private var customName = ""

    private static let customWorks = [LibraryCatalog.bookOfMormon, LibraryCatalog.bible, LibraryCatalog.doctrineAndCovenants, LibraryCatalog.pearlOfGreatPrice]

    private var workBooks: [LibraryBook] { LibraryCatalog.work(workID)?.books ?? [] }

    /// The catalog plan, or one built from the custom choices.
    private var effectivePlan: ReadingPlan {
        guard plan.isCustom else { return plan }
        let books = workBooks
        guard !books.isEmpty else { return plan }
        let a = books.firstIndex { $0.id == firstBookID } ?? 0
        let b = books.firstIndex { $0.id == lastBookID } ?? books.count - 1
        let chosen = Array(books[min(a, b)...max(a, b)])
        let ids = ReadingPlanCatalog.chapters(of: chosen)
        let name = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        let span = chosen.count == 1 ? PlanFormat.bookName(chosen[0]) : "\(PlanFormat.bookName(chosen[0])) to \(PlanFormat.bookName(chosen[chosen.count - 1]))"
        return ReadingPlan(
            id: ReadingPlan.customID,
            title: name.isEmpty ? "\(span) in \(min(customDays, ids.count)) Days" : name,
            subtitle: span,
            days: min(max(customDays, 1), max(ids.count, 1)),
            coverHex: 0x5A5A63,
            chapterIDs: ids
        )
    }

    private var readingDays: ReadingDays { weekdaysOnly ? .weekdays : .everyDay }

    var body: some View {
        let plan = effectivePlan
        let days = PlanEngine.shared.preview(plan: plan, dayCount: plan.days, start: startDate, readingDays: readingDays, content: content)
        let minutes = days.isEmpty ? 0 : days.reduce(0) { $0 + $1.minutes } / days.count

        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        PlanCover(plan: plan, width: 54)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(plan.title).font(.title2.bold())
                            Text("\(plan.chapterIDs.count) \(plan.id.hasPrefix("dc") ? "sections" : "chapters") · \(plan.subtitle)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                }

                if self.plan.isCustom {
                    Section("Books") {
                        Picker("Read from", selection: $workID) {
                            ForEach(Self.customWorks) { work in Text(work.title).tag(work.id) }
                        }
                        if workBooks.count > 1 {
                            Picker("First book", selection: $firstBookID) {
                                ForEach(workBooks) { book in Text(book.title).tag(book.id) }
                            }
                            Picker("Last book", selection: $lastBookID) {
                                ForEach(workBooks) { book in Text(book.title).tag(book.id) }
                            }
                        }
                        Stepper(value: $customDays, in: 1...max(plan.chapterIDs.count, 1), step: customDays >= 30 ? 5 : 1) {
                            LabeledContent("Days", value: "\(plan.days)")
                        }
                        TextField("Name (optional)", text: $customName)
                    }
                }

                Section {
                    HStack(spacing: 8) {
                        StatTile(value: PlanFormat.perDay(chapters: plan.chapterIDs.count, days: days.count), label: plan.id.hasPrefix("dc") ? "sections a day" : "chapters a day")
                        StatTile(value: "~\(minutes)", label: "minutes a day")
                        StatTile(value: days.last.map { PlanFormat.shortDate($0.date) } ?? "–", label: "you finish")
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    DatePicker("Start", selection: $startDate, in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date)
                    Picker("Reading days", selection: $weekdaysOnly) {
                        Text("Every day").tag(false)
                        Text("Weekdays").tag(true)
                    }
                    Toggle("Remind me", isOn: $reminder)
                    if reminder {
                        DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    Text(footer)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .close) { dismiss() }
                        .tint(Color.primary)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: start) {
                    Text(replacing == nil ? "Start Plan" : "Start New Plan")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(plan.chapterIDs.isEmpty)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .onChange(of: workID, initial: true) { _, _ in
                firstBookID = workBooks.first?.id ?? ""
                lastBookID = workBooks.last?.id ?? ""
            }
        }
        .tint(accent.color)
    }

    private var footer: String {
        var text = "Days are balanced by length, so a long chapter gets a lighter day. If you fall behind, you can catch up or reschedule."
        if let replacing, let current = ReadingPlanCatalog.plan(for: replacing) {
            text += " Starting this plan ends \(current.title); your reading progress stays."
        }
        return text
    }

    private func start() {
        let plan = effectivePlan
        guard !plan.chapterIDs.isEmpty else { return }
        replacing?.endedAt = .now
        let time = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        let enrollment = PlanEnrollment(
            planID: plan.id,
            startDate: startDate,
            days: plan.days,
            readingDays: readingDays.rawValue,
            reminderEnabled: reminder,
            reminderMinutes: (time.hour ?? 7) * 60 + (time.minute ?? 0)
        )
        if plan.isCustom {
            enrollment.customTitle = plan.title
            enrollment.customChapterIDs = plan.chapterIDs
        }
        modelContext.insert(enrollment)
        if reminder {
            Task { _ = await PlanReminders.requestPermission() }
        }
        dismiss()
    }
}

private struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.bold().monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Detail

/// A plan's progress: calendar, catch-up, and what's coming up.
struct PlanDetailView: View {
    let enrollment: PlanEnrollment

    @Environment(ContentService.self) private var content
    @Environment(\.dismiss) private var dismiss
    @Query private var progress: [ReadingProgress]
    @State private var month = Date.now
    @State private var confirmEnd = false
    @State private var creatingGroup = false

    var body: some View {
        let read = PlanReading.readSet(progress)
        Group {
            if let state = PlanEngine.shared.state(for: enrollment, content: content, read: read) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(state)
                        if state.isFinished {
                            finished(state)
                        } else if state.daysBehind > 0 {
                            behind(state)
                        }
                        PlanCalendar(state: state, month: $month)
                        comingUp(state)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .background(Color(.systemGroupedBackground))
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Reschedule", systemImage: "calendar.badge.clock") { reschedule(state) }
                                .disabled(state.daysBehind == 0)
                            Toggle("Daily Reminder", systemImage: "bell", isOn: reminderBinding)
                            if AppConfig.cloudSyncEnabled {
                                Button("Read with Others", systemImage: "person.3") { creatingGroup = true }
                            }
                            Divider()
                            Button("End Plan", systemImage: "xmark.circle", role: .destructive) { confirmEnd = true }
                        } label: {
                            Label("Plan Options", systemImage: "ellipsis")
                        }
                        .tint(Color.primary)
                    }
                }
                .sensoryFeedback(.success, trigger: state.isFinished) { _, done in done }
            } else {
                ContentUnavailableView("Plan Unavailable", systemImage: "calendar", description: Text("This plan's chapters couldn't be found."))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $creatingGroup) {
            CreateGroupSheet(defaultPlanID: enrollment.planID, customPlan: ReadingPlanCatalog.plan(for: enrollment).flatMap { $0.isCustom ? $0 : nil })
        }
        .confirmationDialog("End this plan?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End Plan", role: .destructive) {
                enrollment.endedAt = .now
                dismiss()
            }
        } message: {
            Text("Your reading progress stays. You can start a new plan any time.")
        }
    }

    private var reminderBinding: Binding<Bool> {
        Binding(get: { enrollment.reminderEnabled }, set: { on in
            enrollment.reminderEnabled = on
            if on { Task { _ = await PlanReminders.requestPermission() } }
        })
    }

    private func header(_ state: PlanState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(state.plan.title).font(.title.bold())
                Text(summary(state)).font(.subheadline).foregroundStyle(.secondary)
            }
            ProgressView(value: state.fraction)
                .progressViewStyle(.linear)
                .accessibilityLabel("\(state.fraction.formatted(.percent.precision(.fractionLength(0)))) read")
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    private func summary(_ state: PlanState) -> String {
        var parts = ["\(state.chaptersRead) of \(state.chaptersTotal) read"]
        if !state.isFinished {
            parts.append("Day \(state.dayNumber) of \(state.totalDays)")
            if let end = state.endDate { parts.append("finishes \(PlanFormat.shortDate(end))") }
        }
        return parts.joined(separator: " · ")
    }

    private func behind(_ state: PlanState) -> some View {
        let overdue = state.overdueChapterIDs
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.title3)
                    .foregroundStyle(.orange)
                Text("**\(state.statusLine).** \(PlanFormat.range(overdue)) \(overdue.count == 1 ? "is" : "are") still unread.")
                    .font(.subheadline)
            }
            HStack(spacing: 10) {
                if let first = overdue.first {
                    NavigationLink {
                        ReaderView(chapterID: first)
                    } label: {
                        Text("Catch Up").foregroundStyle(.white).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.orange)
                }
                Button {
                    reschedule(state)
                } label: {
                    Text("Reschedule").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .tint(Color.primary)
            }
            .controlSize(.regular)
            Text("Reschedule starts the unread days from today and moves your finish date.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 20))
    }

    private func finished(_ state: PlanState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("You finished \(state.plan.title)", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.tint)
            Text("All \(state.chaptersTotal) chapters read. Finish the plan to start another.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                enrollment.endedAt = .now
                dismiss()
            } label: {
                Text("Finish Plan").foregroundStyle(.white).frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }

    private func comingUp(_ state: PlanState) -> some View {
        let upcoming = Array(state.days.filter { $0.date >= state.today }.prefix(7))
        return VStack(alignment: .leading, spacing: 8) {
            Text("COMING UP")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(upcoming) { day in
                    NavigationLink {
                        ReaderView(chapterID: day.chapterIDs.first { !state.read.contains($0) } ?? day.chapterIDs[0])
                    } label: {
                        HStack(spacing: 12) {
                            Text(label(for: day, today: state.today))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(day.date == state.today ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                                .frame(width: 76, alignment: .leading)
                            Text(PlanFormat.range(day.chapterIDs))
                                .font(.scripture(size: 17, weight: .semibold))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            if state.isDone(day) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                                    .accessibilityLabel("Read")
                            } else {
                                Text("\(day.minutes) min").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    if day.id != upcoming.last?.id {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
        }
    }

    private func label(for day: PlanDay, today: Date) -> String {
        let calendar = Calendar.current
        if day.date == today { return "Today" }
        if calendar.isDateInTomorrow(day.date) { return "Tomorrow" }
        return day.date.formatted(.dateTime.weekday(.abbreviated).day())
    }

    private func reschedule(_ state: PlanState) {
        withAnimation(.snappy) {
            PlanEngine.shared.reschedule(enrollment, state: state)
        }
    }
}

/// A month of the plan: read, missed, today, and reading days ahead.
struct PlanCalendar: View {
    let state: PlanState
    @Binding var month: Date

    var body: some View {
        let calendar = Calendar.current
        let statusByDate = Dictionary(state.days.map { ($0.date, state.status(of: $0)) }, uniquingKeysWith: { first, _ in first })
        let monthStart = calendar.dateInterval(of: .month, for: month)?.start ?? month
        let dayCount = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let leading = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let ordered = Array(symbols[(calendar.firstWeekday - 1)...] + symbols[..<(calendar.firstWeekday - 1)])
        let firstMonth = state.days.first.flatMap { calendar.dateInterval(of: .month, for: $0.date)?.start } ?? monthStart
        let lastMonth = state.days.last.flatMap { calendar.dateInterval(of: .month, for: $0.date)?.start } ?? monthStart

        VStack(spacing: 10) {
            HStack {
                Text(monthStart.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                Spacer()
                HStack(spacing: 12) {
                    legend("Read", color: .accentColor, filled: true)
                    legend("Missed", color: .orange, filled: false)
                }
                Button("Previous Month", systemImage: "chevron.left") { shift(-1) }
                    .labelStyle(.iconOnly)
                    .disabled(monthStart <= firstMonth)
                Button("Next Month", systemImage: "chevron.right") { shift(1) }
                    .labelStyle(.iconOnly)
                    .disabled(monthStart >= lastMonth)
            }
            .buttonStyle(.borderless)
            .tint(Color.primary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(Array(ordered.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                ForEach(0..<leading, id: \.self) { _ in Color.clear.frame(height: 36) }
                ForEach(1...dayCount, id: \.self) { number in
                    let date = calendar.date(byAdding: .day, value: number - 1, to: monthStart) ?? monthStart
                    DayCell(number: number, status: statusByDate[date], isToday: date == state.today, date: date)
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
        .onAppear {
            // Open on the month with today in it (or the plan's first month if it hasn't started).
            if let first = state.days.first?.date, first > state.today { month = first } else { month = state.today }
        }
    }

    private func shift(_ months: Int) {
        withAnimation(.snappy) {
            month = Calendar.current.date(byAdding: .month, value: months, to: month) ?? month
        }
    }

    private func legend(_ title: String, color: Color, filled: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(filled ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.clear))
                .overlay { if !filled { Circle().strokeBorder(color, lineWidth: 1.5) } }
                .frame(width: 8, height: 8)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct DayCell: View {
    let number: Int
    let status: PlanState.DayStatus?
    let isToday: Bool
    let date: Date

    var body: some View {
        Text("\(number)")
            .font(.subheadline.weight(weight).monospacedDigit())
            .foregroundStyle(foreground)
            .frame(width: 34, height: 34)
            .background {
                switch status {
                case .done: Circle().fill(.tint)
                case .missed: Circle().strokeBorder(.orange, lineWidth: 2)
                case .today: Circle().strokeBorder(.tint, lineWidth: 2)
                case .upcoming, nil: if isToday { Circle().strokeBorder(.secondary, lineWidth: 1) }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(date.formatted(date: .long, time: .omitted))
            .accessibilityValue(accessibilityStatus)
    }

    private var weight: Font.Weight {
        switch status {
        case .done, .missed, .today: .semibold
        default: .regular
        }
    }

    private var foreground: AnyShapeStyle {
        switch status {
        case .done: AnyShapeStyle(Color.white)
        case .missed: AnyShapeStyle(Color.orange)
        case .today, .upcoming: AnyShapeStyle(Color.primary)
        case nil: AnyShapeStyle(.tertiary)
        }
    }

    private var accessibilityStatus: String {
        switch status {
        case .done: "Read"
        case .missed: "Missed"
        case .today: "Today's reading"
        case .upcoming: "Reading day"
        case nil: "No reading"
        }
    }
}

// MARK: - Today

/// The active plan's card on Today: today's range, a bar per chapter, and a way in.
struct PlanTodayCard: View {
    let state: PlanState
    let enrollment: PlanEnrollment

    @AppStorage(SettingsKey.accent) private var accent: AccentOption = .blue

    var body: some View {
        let day = state.currentDay
        let todayDone = day.map(state.isDone) ?? true

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.plan.title.uppercased())
                        .font(.caption.weight(.bold))
                        .opacity(0.9)
                    Text(dayLine(day))
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                ZStack {
                    Circle().stroke(.white.opacity(0.28), lineWidth: 6)
                    Circle().trim(from: 0, to: state.fraction)
                        .stroke(.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(state.fraction.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption.weight(.bold).monospacedDigit())
                }
                .frame(width: 52, height: 52)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(state.fraction.formatted(.percent.precision(.fractionLength(0)))) of the plan read")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(state.isFinished ? "Plan complete" : (todayDone && state.isReadingDayToday ? "Done for today" : PlanFormat.range(day?.chapterIDs ?? [])))
                    .font(.scripture(size: 30, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(detailLine(day, todayDone: todayDone))
                    .font(.subheadline)
                    .opacity(0.9)
            }

            if let day, !state.isFinished {
                HStack(spacing: 6) {
                    ForEach(day.chapterIDs, id: \.self) { id in
                        Capsule()
                            .fill(.white.opacity(state.read.contains(id) ? 1 : 0.35))
                            .frame(height: 6)
                    }
                }
                .accessibilityHidden(true)
            }

            ViewThatFits(in: .horizontal) {
                actionRow(todayDone: todayDone, listenTitle: true)
                actionRow(todayDone: todayDone, listenTitle: false)
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(accent.color.gradient, in: .rect(cornerRadius: 26))
    }

    /// Read, Listen and View Plan. Listen drops its title when the row is tight.
    private func actionRow(todayDone: Bool, listenTitle: Bool) -> some View {
        HStack(spacing: 10) {
            if let next = state.nextChapterID, !state.isFinished {
                NavigationLink {
                    ReaderView(chapterID: next)
                } label: {
                    Label(buttonTitle(todayDone: todayDone), systemImage: "book.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .background(.white, in: Capsule())
                        .foregroundStyle(accent.color)
                }
                .buttonStyle(.plain)
                .fixedSize()

                Button(action: listenToday) {
                    Label(isListening && ListenEngine.shared.isPlaying ? "Listening" : "Listen", systemImage: "headphones")
                        .labelStyle(ListenLabelStyle(showsTitle: listenTitle))
                        .font(.subheadline.weight(.semibold))
                        .symbolEffect(.pulse, isActive: isListening && ListenEngine.shared.isPlaying)
                        .padding(.horizontal, listenTitle ? 16 : 0)
                        .frame(minWidth: 40)
                        .frame(height: 40)
                        .background(.white.opacity(0.2), in: Capsule())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityLabel(isListening ? "Open the player" : "Listen to today's reading")
            }
            Spacer(minLength: 0)
            NavigationLink {
                PlanDetailView(enrollment: enrollment)
            } label: {
                Text("View Plan")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .background(.white.opacity(0.2), in: Capsule())
            }
            .buttonStyle(.plain)
            .fixedSize()
        }
    }

    // MARK: Listen

    /// Today's chapters still to read (anything overdue first), in order.
    private var listenQueue: [String] {
        var queue: [String] = []
        for id in state.overdueChapterIDs + (state.currentDay?.chapterIDs ?? []) where !state.read.contains(id) && !queue.contains(id) {
            queue.append(id)
        }
        if queue.isEmpty, let next = state.nextChapterID { queue = [next] }
        return queue
    }

    /// Listening to the plan (playing or paused): the button opens the player instead.
    private var isListening: Bool {
        let engine = ListenEngine.shared
        return engine.isActive && engine.source == .plan
    }

    private func listenToday() {
        let engine = ListenEngine.shared
        if isListening {
            engine.showsPlayer = true
        } else {
            engine.start(chapterIDs: listenQueue, source: .plan)
        }
    }

    private func dayLine(_ day: PlanDay?) -> String {
        if state.isFinished { return "All \(state.chaptersTotal) read" }
        guard let day else { return state.statusLine }
        if !state.isReadingDayToday {
            return "No reading today · next \(day.date.formatted(.dateTime.weekday(.wide)))"
        }
        return "Day \(day.number) of \(state.totalDays) · \(state.statusLine)"
    }

    private func detailLine(_ day: PlanDay?, todayDone: Bool) -> String {
        if state.isFinished { return "Open the plan to finish it and start another." }
        guard let day else { return "" }
        if todayDone && state.isReadingDayToday {
            if let next = state.days.first(where: { $0.date > state.today }) {
                return "Next: \(PlanFormat.range(next.chapterIDs))"
            }
            return "Nice work."
        }
        var text = "\(day.chapterIDs.count) \(day.chapterIDs.count == 1 ? "chapter" : "chapters") · about \(day.minutes) minutes"
        let overdue = state.overdueChapterIDs
        if !overdue.isEmpty { text += " · plus \(PlanFormat.range(overdue)) to catch up" }
        return text
    }

    private func buttonTitle(todayDone: Bool) -> String {
        if todayDone { return "Read Ahead" }
        let started = (state.currentDay?.chapterIDs ?? []).contains(where: state.read.contains)
        return started ? "Continue" : "Start Reading"
    }
}

/// On Today when no plan is running.
struct StartPlanCard: View {
    var body: some View {
        NavigationLink {
            ReadingPlansView()
        } label: {
            HStack(spacing: 14) {
                SymbolTile(systemName: "calendar", size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start a reading plan").font(.headline)
                    Text("The Book of Mormon in 90 days, and more").font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

#Preview("Plans") {
    NavigationStack { ReadingPlansView() }
        .previewEnvironment(signedIn: true)
}

/// An icon with or without its title (Listen on the plan card).
private struct ListenLabelStyle: LabelStyle {
    let showsTitle: Bool

    func makeBody(configuration: Configuration) -> some View {
        if showsTitle {
            HStack(spacing: 6) {
                configuration.icon
                configuration.title
            }
        } else {
            configuration.icon
        }
    }
}
