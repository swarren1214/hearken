import CloudKit
import SwiftData
import SwiftUI

/// Navigation value for a group page.
struct GroupRoute: Hashable {
    let id: String
}

/// The group's shared schedule: everyone follows the same plan from the same start date.
@MainActor
enum GroupSchedule {
    static func days(for group: GroupStore.StudyGroup, content: ContentService) -> [PlanDay] {
        guard let plan = group.plan else { return [] }
        return PlanEngine.shared.days(for: plan, fromIndex: 0, dayCount: plan.days, firstDayNumber: 1,
                                      start: group.startDate, readingDays: .everyDay, content: content)
    }

    /// Today's assignment, or the next one if the group hasn't started yet.
    static func current(_ days: [PlanDay], now: Date = .now) -> PlanDay? {
        let today = Calendar.current.startOfDay(for: now)
        return days.first { $0.date == today } ?? days.first { $0.date > today }
    }

    static func week(_ days: [PlanDay], now: Date = .now) -> (start: Date, days: [PlanDay]) {
        let interval = Calendar.current.dateInterval(of: .weekOfYear, for: now)
        let start = interval?.start ?? Calendar.current.startOfDay(for: now)
        let end = interval?.end ?? start.addingTimeInterval(7 * 86_400)
        return (start, days.filter { $0.date >= start && $0.date < end })
    }

    /// My progress on the group's plan, for publishing to the group.
    static func progress(for group: GroupStore.StudyGroup, content: ContentService, read: Set<String>, streak: Int, now: Date = .now) -> GroupStore.Progress? {
        guard let plan = group.plan else { return nil }
        let all = days(for: group, content: content)
        let week = week(all, now: now)
        let weekChapters = week.days.flatMap(\.chapterIDs)
        let today = Calendar.current.startOfDay(for: now)
        let todays = all.first { $0.date == today }
        return GroupStore.Progress(
            weekStart: week.start,
            weekRead: weekChapters.filter(read.contains).count,
            weekTotal: weekChapters.count,
            doneToday: todays.map { $0.chapterIDs.allSatisfy(read.contains) } ?? false,
            chaptersRead: plan.chapterIDs.filter(read.contains).count,
            streak: streak
        )
    }
}

/// Keeps groups loaded and my progress published: on launch, on returning to the app, at
/// the start of a new day, and whenever I finish a chapter.
struct GroupSideEffects: ViewModifier {
    @Environment(ContentService.self) private var scripture
    @Environment(AccountService.self) private var account
    @Environment(\.scenePhase) private var scenePhase
    @Query private var progress: [ReadingProgress]
    @Query private var xpEvents: [XPEvent]

    func body(content: Content) -> some View {
        content
            .task(id: "\(account.isSignedIn)|\(account.iCloudAvailable == true)|\(scenePhase == .active)") {
                guard account.isSignedIn, account.iCloudAvailable == true, scenePhase == .active else { return }
                await GroupStore.shared.refresh()
                await GroupStore.shared.ensureSubscriptions()
            }
            .task(id: publishKey) { await publish() }
    }

    private var publishKey: String {
        let store = GroupStore.shared
        let read = progress.reduce(0) { $0 + ($1.completedAt == nil ? 0 : 1) }
        let day = Calendar.current.startOfDay(for: .now).timeIntervalSinceReferenceDate
        return "\(store.groups.map(\.id))|\(read)|\(day)|\(store.myUserID ?? "")|\(account.displayName ?? "")"
    }

    private func publish() async {
        let store = GroupStore.shared
        guard account.isSignedIn, !store.groups.isEmpty else { return }
        let read = PlanReading.readSet(progress)
        let streak = MasteryMath.streak(activityDates: xpEvents.map(\.createdAt), now: .now)
        for group in store.groups {
            guard let mine = GroupSchedule.progress(for: group, content: scripture, read: read, streak: streak) else { continue }
            await store.publish(mine, in: group, name: account.displayName ?? "Member", initials: account.initials ?? "")
        }
    }
}

// MARK: - Avatars

struct MemberAvatar: View {
    let name: String
    let initials: String
    var size: CGFloat = 32

    private static let palette: [Color] = [Color(hex: 0x5E5CE6), Color(hex: 0xE0244A), Color(hex: 0x24A148), Color(hex: 0xE68600), Color(hex: 0x0E8A8A), Color(hex: 0x8E44C9)]

    var body: some View {
        let seed = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        Text(initials.isEmpty ? String(name.prefix(1)).uppercased() : initials)
            .font(.system(size: size * 0.36, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Self.palette[seed % Self.palette.count], in: Circle())
            .accessibilityHidden(true)
    }
}

// MARK: - Today

/// Today's Study Groups section: each group with who has read today, or a way to start one.
struct GroupsSection: View {
    var defaultPlanID: String?
    var customPlan: ReadingPlan?

    @Environment(AccountService.self) private var account
    @State private var creating = false

    var body: some View {
        let store = GroupStore.shared
        if account.isSignedIn, AppConfig.cloudSyncEnabled {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Study Groups").font(.title2.bold())
                    Spacer()
                    if !store.groups.isEmpty {
                        Button("New Group", systemImage: "plus") { creating = true }
                            .labelStyle(.iconOnly)
                            .font(.headline)
                            .tint(Color.primary)
                    }
                }
                if store.groups.isEmpty {
                    Button { creating = true } label: {
                        HStack(spacing: 14) {
                            SymbolTile(systemName: "person.3.fill", size: 46)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Read with others").font(.headline)
                                Text("Start a group and invite family or friends").font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(.tint)
                        }
                        .padding(16)
                        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                } else {
                    VStack(spacing: 0) {
                        ForEach(store.groups) { group in
                            NavigationLink(value: GroupRoute(id: group.id)) {
                                GroupRow(group: group)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                            if group.id != store.groups.last?.id { Divider().padding(.leading, 74) }
                        }
                    }
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
                }
            }
            .sheet(isPresented: $creating) {
                CreateGroupSheet(defaultPlanID: defaultPlanID, customPlan: customPlan)
            }
        }
    }
}

private struct GroupRow: View {
    let group: GroupStore.StudyGroup

    var body: some View {
        let readToday = group.members.filter { $0.lastDoneDay.map(Calendar.current.isDateInToday) ?? false }.count
        HStack(spacing: 14) {
            SymbolTile(systemName: group.symbol, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name).font(.headline)
                Text(group.members.isEmpty ? (group.plan?.title ?? "") : "\(readToday) of \(group.members.count) read today")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: -8) {
                ForEach(group.members.prefix(4)) { member in
                    MemberAvatar(name: member.name, initials: member.initials, size: 28)
                        .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2))
                }
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Create and invite

struct CreateGroupSheet: View {
    var defaultPlanID: String?
    /// The person's own custom plan, offered alongside the built-in ones.
    var customPlan: ReadingPlan?

    @Environment(\.dismiss) private var dismiss
    @Environment(AccountService.self) private var account
    @AppStorage(SettingsKey.accent) private var accent: AccentOption = .blue
    @Query(sort: \PlanEnrollment.createdAt, order: .reverse) private var enrollments: [PlanEnrollment]
    @State private var name = ""
    @State private var symbol = "house.fill"
    @State private var planID = ReadingPlanCatalog.plans[0].id
    @State private var working = false
    @State private var errorMessage: String?
    @State private var createdID: String?

    private static let symbols = ["house.fill", "person.3.fill", "book.fill", "flame.fill", "leaf.fill", "star.fill", "heart.fill", "sun.max.fill"]

    var body: some View {
        NavigationStack {
            Group {
                if let createdID, let group = GroupStore.shared.group(createdID) {
                    invite(group)
                } else {
                    form
                }
            }
            .navigationTitle(createdID == nil ? "New Study Group" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(createdID == nil ? "Cancel" : "Done", systemImage: createdID == nil ? "xmark" : "checkmark", role: .close) { dismiss() }
                        .tint(Color.primary)
                }
                if createdID == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create", systemImage: "checkmark", role: .confirm) { Task { await create() } }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || working)
                    }
                }
            }
        }
        .tint(accent.color)
        .onAppear {
            if let defaultPlanID, defaultPlanID == ReadingPlan.customID ? customPlan != nil : ReadingPlanCatalog.plans.contains(where: { $0.id == defaultPlanID }) {
                planID = defaultPlanID
            }
        }
    }

    private var form: some View {
        Form {
            Section("Name") {
                TextField("Family Study", text: $name)
                    .submitLabel(.done)
            }
            Section("Icon") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                    ForEach(Self.symbols, id: \.self) { item in
                        Button { symbol = item } label: {
                            Image(systemName: item)
                                .font(.title3)
                                .frame(width: 52, height: 52)
                                .foregroundStyle(item == symbol ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
                                .background(item == symbol ? AnyShapeStyle(.tint) : AnyShapeStyle(.tint.opacity(0.14)), in: .rect(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item)
                        .accessibilityAddTraits(item == symbol ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                Picker("Plan", selection: $planID) {
                    if let customPlan {
                        Text(customPlan.title).tag(ReadingPlan.customID)
                    }
                    ForEach(ReadingPlanCatalog.plans) { plan in Text(plan.title).tag(plan.id) }
                }
            } footer: {
                Text("Everyone follows the same schedule, starting \(startDate == Calendar.current.startOfDay(for: .now) ? "today" : PlanFormat.shortDate(startDate)). Members see only your progress on this plan and what you choose to share.")
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
            if working {
                Section { HStack { ProgressView(); Text("Creating…").foregroundStyle(.secondary) } }
            }
        }
    }

    /// Match the creator's own plan dates when they're already following this plan.
    private var startDate: Date {
        PlanReading.active(enrollments).flatMap { $0.planID == planID ? $0.startDate : nil } ?? Calendar.current.startOfDay(for: .now)
    }

    private func invite(_ group: GroupStore.StudyGroup) -> some View {
        VStack(spacing: 18) {
            Spacer()
            SymbolTile(systemName: group.symbol, size: 84)
            VStack(spacing: 6) {
                Text("\(group.name) is ready").font(.title2.bold())
                Text("Send the invite link to the people you want to read with. Anyone with the link can join, and you can remove people later.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let url = group.shareURL {
                ShareLink(item: url, subject: Text("Join \(group.name) on Hearken"),
                          message: Text("Read \(group.plan?.title ?? "the scriptures") with me in Hearken.")) {
                    Label("Invite People", systemImage: "person.badge.plus")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            } else {
                ProgressView("Getting the invite link…")
            }
            Spacer()
            Spacer()
        }
        .padding(24)
    }

    private func create() async {
        working = true
        errorMessage = nil
        defer { working = false }
        do {
            guard let plan = planID == ReadingPlan.customID ? customPlan : ReadingPlanCatalog.plans.first(where: { $0.id == planID }) else { return }
            createdID = try await GroupStore.shared.create(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                symbol: symbol,
                plan: plan,
                startDate: startDate,
                ownerName: account.displayName ?? ""
            )
            _ = await PlanReminders.requestPermission()
        } catch {
            errorMessage = GroupStore.describe(error)
        }
    }
}

// MARK: - Join

struct JoinGroupSheet: View {
    let metadata: CKShare.Metadata

    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.accent) private var accent: AccentOption = .blue
    @State private var joining = false
    @State private var errorMessage: String?

    private var title: String { metadata.share[CKShare.SystemFieldKey.title] as? String ?? "Study Group" }
    private var owner: String {
        metadata.ownerIdentity.nameComponents.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) } ?? "Someone"
    }

    var body: some View {
        VStack(spacing: 16) {
            SymbolTile(systemName: "person.3.fill", size: 72)
                .padding(.top, 28)
            VStack(spacing: 4) {
                Text("\(owner) invited you to").font(.subheadline).foregroundStyle(.secondary)
                Text(title).font(.title.bold()).multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("WHAT THE GROUP SEES")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                seeRow("Your progress on the group's reading plan", symbol: "checkmark", tint: .green)
                Divider().padding(.leading, 48)
                seeRow("Highlights and reflections you choose to share", symbol: "checkmark", tint: .green)
                Divider().padding(.leading, 48)
                seeRow("Your other notes, highlights and bookmarks stay private", symbol: "xmark", tint: .secondary)
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))

            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }
            Spacer(minLength: 0)
            Button {
                Task { await join() }
            } label: {
                Group {
                    if joining { ProgressView().tint(.white) } else { Text("Join Group") }
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(joining)
            Button("Not Now") {
                GroupStore.shared.pendingInvite = nil
                dismiss()
            }
            .font(.headline)
            .tint(Color.primary)
        }
        .padding(20)
        .background(Color(.systemGroupedBackground))
        .tint(accent.color)
        .presentationDetents([.large])
    }

    private func seeRow(_ text: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.body.weight(.bold)).foregroundStyle(tint).frame(width: 20)
            Text(text).font(.subheadline)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func join() async {
        joining = true
        defer { joining = false }
        do {
            try await GroupStore.shared.accept(metadata)
            _ = await PlanReminders.requestPermission()
            dismiss()
        } catch {
            errorMessage = GroupStore.describe(error)
        }
    }
}

// MARK: - Group page

struct GroupDetailView: View {
    let groupID: String

    init(groupID: String) {
        self.groupID = groupID
        _notify = AppStorage(wrappedValue: true, "groups.notify.\(groupID)")
    }

    @AppStorage private var notify: Bool

    @Environment(ContentService.self) private var content
    @Environment(AccountService.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var reflection = ""
    @State private var sending = false
    @State private var confirmLeave = false
    @State private var showMembers = false
    @State private var errorMessage: String?
    @FocusState private var composing: Bool

    var body: some View {
        let store = GroupStore.shared
        if let group = store.group(groupID) {
            page(group)
        } else {
            ContentUnavailableView("Group Unavailable", systemImage: "person.3",
                                   description: Text(store.hasLoaded ? "You may have left this group, or it was deleted." : "Loading…"))
        }
    }

    private func page(_ group: GroupStore.StudyGroup) -> some View {
        let days = GroupSchedule.days(for: group, content: content)
        let today = GroupSchedule.current(days)
        let me = GroupStore.shared.myUserID

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(group)
                week(group, days: days, me: me)
                HStack(alignment: .firstTextBaseline) {
                    Text("Shared").font(.title2.bold())
                    Spacer()
                    Text("Only what members choose to share").font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
                if group.items.isEmpty {
                    Text("Nothing shared yet. Share a reflection below, or choose Share to Group on a highlight in the reader.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
                } else {
                    ForEach(group.items) { item in
                        GroupItemCard(item: item, group: group, me: me)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .refreshable { await GroupStore.shared.refresh() }
        .safeAreaInset(edge: .bottom) { composer(group, today: today) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let url = group.shareURL {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: url, subject: Text("Join \(group.name) on Hearken"),
                              message: Text("Read \(group.plan?.title ?? "the scriptures") with me in Hearken.")) {
                        Label("Invite", systemImage: "person.badge.plus")
                    }
                    .tint(Color.primary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Activity Notifications", systemImage: "bell", isOn: $notify)
                    if group.isOwner {
                        Button("Members", systemImage: "person.2") { showMembers = true }
                    }
                    Button(group.isOwner ? "Delete Group" : "Leave Group", systemImage: group.isOwner ? "trash" : "rectangle.portrait.and.arrow.right", role: .destructive) {
                        confirmLeave = true
                    }
                } label: {
                    Label("Group Options", systemImage: "ellipsis")
                }
                .tint(Color.primary)
            }
        }
        .confirmationDialog(group.isOwner ? "Delete \(group.name)?" : "Leave \(group.name)?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button(group.isOwner ? "Delete Group" : "Leave Group", role: .destructive) {
                Task {
                    do {
                        try await GroupStore.shared.leave(group)
                        dismiss()
                    } catch {
                        errorMessage = GroupStore.describe(error)
                    }
                }
            }
        } message: {
            Text(group.isOwner
                 ? "This removes the group and everything shared in it for every member."
                 : "You'll stop seeing the group, and members will no longer see your progress.")
        }
        .sheet(isPresented: $showMembers) { GroupMembersSheet(group: group) }
        .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func header(_ group: GroupStore.StudyGroup) -> some View {
        HStack(spacing: 14) {
            SymbolTile(systemName: group.symbol, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name).font(.title.bold())
                Text("\(group.members.count) \(group.members.count == 1 ? "member" : "members") · \(group.plan?.title ?? "Reading plan")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    private func week(_ group: GroupStore.StudyGroup, days: [PlanDay], me: String?) -> some View {
        let week = GroupSchedule.week(days)
        let readToday = group.members.filter { $0.lastDoneDay.map(Calendar.current.isDateInToday) ?? false }.count
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("THIS WEEK").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Text(week.days.isEmpty ? "No reading this week" : PlanFormat.range(week.days.flatMap(\.chapterIDs)))
                        .font(.scripture(size: 22, weight: .bold))
                }
                Spacer()
                Text("\(readToday) of \(group.members.count) read today")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 14) {
                ForEach(group.members) { member in
                    let current = member.weekStart.map { Calendar.current.isDate($0, inSameDayAs: week.start) } ?? false
                    let read = current ? member.weekRead : 0
                    let total = max(current ? member.weekTotal : week.days.flatMap(\.chapterIDs).count, 1)
                    let doneToday = member.lastDoneDay.map(Calendar.current.isDateInToday) ?? false
                    VStack(spacing: 6) {
                        ZStack(alignment: .bottomTrailing) {
                            ProgressRing(progress: Double(read) / Double(total), lineWidth: 4) {
                                MemberAvatar(name: member.name, initials: member.initials, size: 46)
                            }
                            .frame(width: 60, height: 60)
                            if doneToday {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .green)
                                    .background(Circle().fill(Color(.secondarySystemGroupedBackground)).padding(-2))
                            }
                        }
                        Text(member.userID == me ? "You" : member.name.components(separatedBy: " ").first ?? member.name)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                        Text("\(read) of \(total)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(member.userID == me ? "You" : member.name): \(read) of \(total) chapters this week\(doneToday ? ", read today" : "")")
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
    }

    private func composer(_ group: GroupStore.StudyGroup, today: PlanDay?) -> some View {
        let range = PlanFormat.range(today?.chapterIDs ?? [])
        return HStack(spacing: 8) {
            TextField(range.isEmpty ? "Share a reflection" : "Share a reflection on \(range)", text: $reflection, axis: .vertical)
                .lineLimit(1...4)
                .focused($composing)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            Button("Share", systemImage: "arrow.up") {
                Task { await send(group, today: today, range: range) }
            }
            .labelStyle(.iconOnly)
            .font(.headline)
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(.tint, in: Circle())
            .disabled(reflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
            .padding(.trailing, 6)
        }
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 26))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func send(_ group: GroupStore.StudyGroup, today: PlanDay?, range: String) async {
        let text = reflection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true
        defer { sending = false }
        do {
            try await GroupStore.shared.share(kind: .reflection, chapterID: today?.chapterIDs.first ?? "", startVerse: 0, endVerse: 0,
                                              text: range, note: text, to: group, authorName: account.displayName ?? "Member")
            reflection = ""
            composing = false
        } catch {
            errorMessage = GroupStore.describe(error)
        }
    }
}

private struct GroupItemCard: View {
    let item: GroupStore.SharedItem
    let group: GroupStore.StudyGroup
    let me: String?

    @Environment(ContentService.self) private var content

    var body: some View {
        let mine = item.authorID == me
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                MemberAvatar(name: item.authorName, initials: initials(item.authorName))
                (Text(mine ? "You" : item.authorName).fontWeight(.semibold) + Text(" \(action) · \(item.createdAt.formatted(.relative(presentation: .named)))").foregroundStyle(.secondary))
                    .font(.subheadline)
                    .lineLimit(2)
            }
            if item.kind == .highlight, !item.text.isEmpty {
                Text(item.text)
                    .font(.scripture(size: 17))
                    .padding(.horizontal, 2)
                    .background(Color.yellow.opacity(0.32), in: .rect(cornerRadius: 3))
            }
            if !item.note.isEmpty {
                Text(item.note).font(.body)
            }
            HStack(spacing: 8) {
                reaction(.heart, symbol: "heart", filledSymbol: "heart.fill", color: .pink)
                reaction(.insight, symbol: "lightbulb", filledSymbol: "lightbulb.fill", color: .orange)
                Spacer()
                if !item.chapterID.isEmpty {
                    NavigationLink {
                        ReaderView(chapterID: item.chapterID, verse: item.startVerse > 0 ? item.startVerse : nil)
                    } label: {
                        Label("Open", systemImage: "book")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .tint(Color.primary)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        .contextMenu {
            if mine {
                Button(role: .destructive) {
                    Task { await GroupStore.shared.delete(item, from: group) }
                } label: {
                    Label { Text("Delete") } icon: { Image.redTrash }
                }
            }
        }
        .tint(Color.primary)
    }

    private var reference: String {
        guard !item.chapterID.isEmpty else { return "" }
        guard item.startVerse > 0 else { return content.title(forChapter: item.chapterID) }
        let base = content.reference(chapterID: item.chapterID, verse: item.startVerse)
        return item.endVerse > item.startVerse ? "\(base)–\(item.endVerse)" : base
    }

    private var action: String {
        switch item.kind {
        case .highlight: "highlighted \(reference)"
        case .reflection: item.text.isEmpty ? "shared a reflection" : "on \(item.text)"
        }
    }

    private func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    private func reaction(_ kind: GroupStore.Reaction.Kind, symbol: String, filledSymbol: String, color: Color) -> some View {
        let all = group.reactions.filter { $0.itemID == item.id && $0.kind == kind }
        let mine = all.contains { $0.authorID == me }
        return Button {
            Task { await GroupStore.shared.toggle(kind, on: item, in: group) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: mine ? filledSymbol : symbol)
                    .foregroundStyle(mine ? color : .secondary)
                if !all.isEmpty { Text("\(all.count)").monospacedDigit() }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(mine ? AnyShapeStyle(color.opacity(0.14)) : AnyShapeStyle(.quaternary.opacity(0.6)), in: Capsule())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: mine)
        .accessibilityLabel(kind == .heart ? "Heart" : "Insight")
        .accessibilityValue("\(all.count)")
        .accessibilityAddTraits(mine ? .isSelected : [])
    }
}

// MARK: - Members (owner)

private struct GroupMembersSheet: View {
    let group: GroupStore.StudyGroup

    @Environment(\.dismiss) private var dismiss
    @State private var participants: [CKShare.Participant] = []
    @State private var loading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if loading {
                        ProgressView()
                    } else if participants.isEmpty {
                        Text("No one has joined yet. Use Invite to send the link.").foregroundStyle(.secondary)
                    }
                    ForEach(participants, id: \.self) { participant in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name(of: participant)).font(.body)
                            Text(participant.acceptanceStatus == .accepted ? "Member" : "Invited")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button("Remove", systemImage: "person.badge.minus", role: .destructive) {
                                Task { await remove(participant) }
                            }
                        }
                    }
                } footer: {
                    Text("Removing someone stops them seeing the group. Swipe a name to remove it.")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", role: .close) { dismiss() }
                        .tint(Color.primary)
                }
            }
            .task { await load() }
        }
    }

    private func name(of participant: CKShare.Participant) -> String {
        if let components = participant.userIdentity.nameComponents {
            let formatted = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
            if !formatted.isEmpty { return formatted }
        }
        return participant.userIdentity.lookupInfo?.emailAddress ?? "Someone with the link"
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            participants = try await GroupStore.shared.participants(of: group)
        } catch {
            errorMessage = GroupStore.describe(error)
        }
    }

    private func remove(_ participant: CKShare.Participant) async {
        do {
            try await GroupStore.shared.remove(participant, from: group)
            participants.removeAll { $0 == participant }
        } catch {
            errorMessage = GroupStore.describe(error)
        }
    }
}

// MARK: - Shared verses in the reader

private struct GroupVerseEntry: Identifiable {
    let group: GroupStore.StudyGroup
    let item: GroupStore.SharedItem
    var id: String { group.id + "|" + item.id }
}

/// What group members shared on a verse, opened from the marker beside it in the reader.
struct GroupVerseSheet: View {
    let chapterID: String
    let verse: Int
    let reference: String

    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.accent) private var accent: AccentOption = .blue

    var body: some View {
        let store = GroupStore.shared
        let entries = store.groups.flatMap { group in
            group.items
                .filter { $0.kind == .highlight && $0.chapterID == chapterID && (($0.startVerse)...max($0.startVerse, $0.endVerse)).contains(verse) }
                .map { GroupVerseEntry(group: group, item: $0) }
        }

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                MemberAvatar(name: entry.item.authorName, initials: "")
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.item.authorID == store.myUserID ? "You" : entry.item.authorName)
                                        .font(.subheadline.weight(.semibold))
                                    Text("\(entry.group.name) · \(entry.item.createdAt.formatted(.relative(presentation: .named)))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(entry.item.text)
                                .font(.scripture(size: 17))
                                .padding(.horizontal, 2)
                                .background(Color.yellow.opacity(0.32), in: .rect(cornerRadius: 3))
                            if !entry.item.note.isEmpty {
                                Text(entry.item.note)
                            }
                            NavigationLink(value: GroupRoute(id: entry.group.id)) {
                                Label("Open \(entry.group.name)", systemImage: "person.3")
                                    .font(.footnote.weight(.semibold))
                            }
                            .buttonStyle(.borderless)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(reference)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: GroupRoute.self) { route in
                GroupDetailView(groupID: route.id)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", role: .close) { dismiss() }
                        .tint(Color.primary)
                }
            }
        }
        .tint(accent.color)
    }
}
