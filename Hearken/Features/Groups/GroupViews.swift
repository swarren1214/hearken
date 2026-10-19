import AuthenticationServices
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

extension GroupStore.StudyGroup {
    /// The group's plan. Custom plans travel with the group, since members don't have them.
    @MainActor var plan: ReadingPlan? {
        if planID == ReadingPlan.customID {
            guard let customPlan, !customPlan.chapterIDs.isEmpty else { return nil }
            return ReadingPlan(id: ReadingPlan.customID, title: customPlan.title.isEmpty ? "Custom Plan" : customPlan.title,
                               subtitle: PlanFormat.range(customPlan.chapterIDs), days: max(customPlan.days, 1),
                               coverHex: 0x5A5A63, chapterIDs: customPlan.chapterIDs)
        }
        return ReadingPlanCatalog.plans.first { $0.id == planID }
    }

    /// The weekly question waiting for my answer.
    func questionWaiting(for me: String?) -> Bool {
        guard let question, question.isPosted, !question.isClosed else { return false }
        return question.myAnswer == nil && !(me.map(question.answeredUserIDs.contains) ?? false)
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
            .task(id: "\(account.isSignedIn)|\(scenePhase == .active)") {
                guard scenePhase == .active else { return }
                GroupStore.shared.profile = (account.displayName ?? "Member", account.initials ?? "")
                await HearthConnection.shared.update()
                await GroupStore.shared.refresh()
                await GroupStore.shared.didConnect()
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
        store.profile = (account.displayName ?? "Member", account.initials ?? "")
        guard !store.groups.isEmpty else { return }
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

// MARK: - Signing in

/// Sign in with Apple for the Hearth account study groups need. Also records the Apple sign-in
/// in Hearken when there isn't one yet.
struct HearthSignInButton: View {
    var label: SignInWithAppleButton.Label = .continue

    @Environment(AccountService.self) private var account
    @Environment(\.colorScheme) private var colorScheme
    @State private var nonce: String?

    var body: some View {
        let connection = HearthConnection.shared
        VStack(spacing: 8) {
            SignInWithAppleButton(label) { request in
                request.requestedScopes = [.fullName, .email]
                nonce = HearthAPI.prepareAppleRequest(request)
            } onCompletion: { result in
                guard case .success(let authorization) = result,
                      let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
                if !account.isSignedIn { try? account.completeSignIn(result) }
                Task { await connection.connect(credential: credential, nonce: nonce) }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 48)
            .disabled(connection.isConnecting)
            .overlay { if connection.isConnecting { ProgressView() } }
            if let message = connection.errorMessage {
                Text(message).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Today

/// Today's Study Groups section: each group with who has read today, or a way to start or join one.
struct GroupsSection: View {
    var defaultPlanID: String?
    var customPlan: ReadingPlan?

    @State private var creating = false
    @State private var joining = false

    var body: some View {
        let store = GroupStore.shared
        let connection = HearthConnection.shared
        if connection.hasChecked || !store.groups.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Study Groups").font(.title2.bold())
                    Spacer()
                    if !store.needsAccount, !store.groups.isEmpty {
                        Menu {
                            Button("New Group", menuIcon: "plus") { creating = true }
                            Button("Join with Code", menuIcon: "ticket") { joining = true }
                        } label: {
                            Label("Add Group", systemImage: "plus")
                                .labelStyle(.iconOnly)
                                .font(.headline)
                        }
                        .tint(Color.primary)
                    }
                }
                if store.needsAccount {
                    signInCard(waiting: store.waitingGroups)
                } else if store.groups.isEmpty, store.waitingGroups.isEmpty {
                    emptyCard
                } else {
                    VStack(spacing: 0) {
                        ForEach(store.groups) { group in
                            NavigationLink(value: GroupRoute(id: group.id)) {
                                GroupRow(group: group, me: store.myUserID)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                            if group.id != store.groups.last?.id || !store.waitingGroups.isEmpty { Divider().padding(.leading, 74) }
                        }
                        ForEach(store.waitingGroups) { waiting in
                            WaitingGroupRow(group: waiting)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            if waiting.id != store.waitingGroups.last?.id { Divider().padding(.leading, 74) }
                        }
                    }
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
                }
            }
            .sheet(isPresented: $creating) {
                CreateGroupSheet(defaultPlanID: defaultPlanID, customPlan: customPlan)
            }
            .sheet(isPresented: $joining) {
                JoinGroupSheet(code: nil)
            }
        }
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                SymbolTile(systemName: "person.3.fill", size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Read with others").font(.headline)
                    Text("Start a group and invite family or friends").font(.footnote).foregroundStyle(.secondary)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { startButton; joinButton }
                VStack(spacing: 10) { startButton; joinButton }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
    }

    private var startButton: some View {
        Button { creating = true } label: {
            Label("Start a Group", systemImage: "plus").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
    }

    private var joinButton: some View {
        Button { joining = true } label: {
            Label("Join with Code", systemImage: "ticket").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .tint(Color.primary)
    }

    private func signInCard(waiting: [GroupStore.WaitingGroup]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                SymbolTile(systemName: "person.3.fill", size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(waiting.isEmpty ? "Read with others" : "Your study groups have moved").font(.headline)
                    Text(waiting.isEmpty
                         ? "Study groups use your Hearth account. Sign in with Apple to start or join one."
                         : "\(ListFormatter.localizedString(byJoining: waiting.map(\.name))) now use Hearth accounts. Sign in with Apple to keep reading together.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HearthSignInButton()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
    }
}

private struct GroupRow: View {
    let group: GroupStore.StudyGroup
    let me: String?

    var body: some View {
        let readToday = group.members.filter(\.doneToday).count
        HStack(spacing: 14) {
            SymbolTile(systemName: group.symbol, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name).font(.headline)
                if group.questionWaiting(for: me) {
                    Label("This week's question is waiting", systemImage: "questionmark.bubble.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tint)
                } else {
                    Text(group.members.count <= 1 ? (group.plan?.title ?? "") : "\(readToday) of \(group.members.count) read today")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
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

private struct WaitingGroupRow: View {
    let group: GroupStore.WaitingGroup

    var body: some View {
        HStack(spacing: 14) {
            SymbolTile(systemName: "hourglass", size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name).font(.headline)
                Text(group.ownerName.isEmpty
                     ? "Moves here when the group's owner updates Hearken"
                     : "Moves here when \(group.ownerName.split(separator: " ").first.map(String.init) ?? group.ownerName) updates Hearken")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
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
                    GroupInviteView(group: group)
                } else {
                    form
                }
            }
            .navigationTitle(createdID == nil ? "New Study Group" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if createdID == nil {
                    ToolbarItem(placement: .cancellationAction) { SheetCancelButton { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        SheetDoneButton("Create") { Task { await create() } }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || working)
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) { SheetDoneButton { dismiss() } }
                }
            }
        }
        .tint(Accent.color)
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 12)], spacing: 12) {
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
                CheckPicker(
                    "Plan", selection: $planID,
                    options: (customPlan.map { [CheckPickerOption(value: ReadingPlan.customID, title: $0.title)] } ?? [])
                        + ReadingPlanCatalog.plans.map { CheckPickerOption(value: $0.id, title: $0.title) }
                )
            } footer: {
                Text("Everyone follows the same schedule, starting \(startDate == Calendar.current.startOfDay(for: .now) ? "today" : PlanFormat.shortDate(startDate)). Members see your progress on this plan and what you choose to share, kept on Hearth's servers so the group can see it.")
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

    private func create() async {
        working = true
        errorMessage = nil
        defer { working = false }
        do {
            guard let plan = planID == ReadingPlan.customID ? customPlan : ReadingPlanCatalog.plans.first(where: { $0.id == planID }) else {
                errorMessage = "Choose a reading plan for the group."
                return
            }
            let id = try await GroupStore.shared.create(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                symbol: symbol,
                plan: plan,
                startDate: startDate,
                ownerName: account.displayName ?? ""
            )
            withAnimation(.snappy) { createdID = id }
            _ = await PlanReminders.requestPermission()
        } catch {
            errorMessage = GroupStore.describe(error, action: "create the group")
        }
    }
}

/// The invite: a link to send, and the code for people who'd rather type it.
struct GroupInviteView: View {
    let group: GroupStore.StudyGroup

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                SymbolTile(systemName: group.symbol, size: 84)
                    .padding(.top, 24)
                VStack(spacing: 6) {
                    Text("\(group.name) is ready").font(.title2.bold()).multilineTextAlignment(.center)
                    Text("Send the invite link to the people you want to read with, or give them the code. You can remove people later.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                InviteCodeView(code: group.inviteCode)
                if let url = group.inviteURL {
                    ShareLink(item: url, subject: Text("Join \(group.name) on Hearken"),
                              message: Text("Read \(group.plan?.title ?? "the scriptures") with me in Hearken. Open the link, or enter code \(group.inviteCode) under Study Groups › Join with Code.")) {
                        Label("Invite People", systemImage: "person.badge.plus")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                }
            }
            .padding(24)
        }
    }
}

/// An invite code in large, spaced letters, copied on tap.
struct InviteCodeView: View {
    let code: String
    @State private var copied = 0

    var body: some View {
        Button {
            UIPasteboard.general.string = code
            copied += 1
        } label: {
            VStack(spacing: 4) {
                Text(spaced(code))
                    .font(.system(.title, design: .monospaced, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(copied > 0 ? "Copied" : "Invite code · tap to copy")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: copied)
        .accessibilityLabel("Invite code \(code.map(String.init).joined(separator: " "))")
        .accessibilityHint("Copies the code")
    }

    private func spaced(_ code: String) -> String {
        code.count == 8 ? "\(code.prefix(4)) \(code.suffix(4))" : code
    }
}

// MARK: - Join

/// Joining: what the invite is for and what the group will see, then Join. Opened from an
/// invite link, or from Join with Code (`code` nil asks for one).
struct JoinGroupSheet: View {
    let code: String?

    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @State private var preview: GroupStore.InvitePreview?
    @State private var looking = false
    @State private var joining = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if HearthConnection.shared.hasChecked && !HearthConnection.shared.isConnected {
                        signIn
                    } else if let preview {
                        details(preview)
                    } else if code == nil {
                        entry
                    } else {
                        ProgressView().padding(.top, 60)
                    }
                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(preview == nil ? "Join a Group" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetCancelButton {
                        GroupStore.shared.pendingInviteCode = nil
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let preview, HearthConnection.shared.isConnected {
                    joinButton(preview).padding(20)
                }
            }
        }
        .tint(Accent.color)
        .task(id: "\(code ?? "")|\(HearthConnection.shared.isConnected)") {
            if let code, HearthConnection.shared.isConnected { await look(up: code) }
        }
    }

    private var signIn: some View {
        VStack(spacing: 16) {
            SymbolTile(systemName: "person.3.fill", size: 72).padding(.top, 20)
            Text("Sign in to join").font(.title2.bold())
            Text("Study groups use your Hearth account, so the group knows it's you. Sign in with Apple to continue.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HearthSignInButton()
        }
    }

    private var entry: some View {
        VStack(spacing: 16) {
            SymbolTile(systemName: "ticket.fill", size: 72).padding(.top, 20)
            Text("Enter the 8-letter code from your invite, or paste the invite link.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            TextField("ABCD 2345", text: $typed)
                .font(.system(.title2, design: .monospaced, weight: .semibold))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(.vertical, 14)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
                .submitLabel(.go)
                .onSubmit { Task { await lookUpTyped() } }
                .accessibilityLabel("Invite code")
            Button {
                Task { await lookUpTyped() }
            } label: {
                Group { if looking { ProgressView().tint(.white) } else { Text("Continue") } }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(GroupStore.inviteCode(from: typed) == nil || looking)
        }
    }

    private func details(_ preview: GroupStore.InvitePreview) -> some View {
        VStack(spacing: 16) {
            SymbolTile(systemName: preview.symbol, size: 72)
                .padding(.top, 12)
            VStack(spacing: 4) {
                Text(preview.ownerName.isEmpty ? "You're invited to" : "\(preview.ownerName) invited you to")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(preview.name).font(.title.bold()).multilineTextAlignment(.center)
                Text("\(preview.memberCount) \(preview.memberCount == 1 ? "member" : "members") · \(ReadingPlanCatalog.plans.first { $0.id == preview.planId }?.title ?? "Reading plan")")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("WHAT THE GROUP SEES")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                seeRow("Your name and progress on the group's reading plan", symbol: "checkmark", tint: .green)
                Divider().padding(.leading, 48)
                seeRow("Highlights, reflections, replies and answers you choose to share", symbol: "checkmark", tint: .green)
                Divider().padding(.leading, 48)
                seeRow("Your other notes, highlights and bookmarks stay private", symbol: "xmark", tint: .secondary)
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
            Text("What you share is kept on Hearth's servers so the group can see it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func joinButton(_ preview: GroupStore.InvitePreview) -> some View {
        Button {
            Task { await join(preview) }
        } label: {
            Group {
                if joining { ProgressView().tint(.white) } else { Text(preview.isMember ? "Open Group" : "Join Group") }
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(joining)
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

    private func lookUpTyped() async {
        guard let code = GroupStore.inviteCode(from: typed) else { return }
        await look(up: code)
    }

    private func look(up code: String) async {
        looking = true
        defer { looking = false }
        do {
            preview = try await GroupStore.shared.preview(code: code)
            errorMessage = nil
        } catch {
            errorMessage = GroupStore.describe(error)
        }
    }

    private func join(_ preview: GroupStore.InvitePreview) async {
        guard let code = code ?? GroupStore.inviteCode(from: typed) else { return }
        joining = true
        defer { joining = false }
        do {
            if preview.isMember {
                GroupStore.shared.openGroupID = preview.groupId
                GroupStore.shared.pendingInviteCode = nil
            } else {
                try await GroupStore.shared.join(code: code)
                _ = await PlanReminders.requestPermission()
            }
            dismiss()
        } catch {
            errorMessage = GroupStore.describe(error)
        }
    }
}

// MARK: - Group page

struct GroupDetailView: View {
    let groupID: String

    @Environment(ContentService.self) private var content
    @Environment(AccountService.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var reflection = ""
    @State private var sending = false
    @State private var confirmLeave = false
    @State private var confirmDelete = false
    @State private var showMembers = false
    @State private var showNotifications = false
    @State private var asking = false
    @State private var answering: GroupStore.Question?
    @State private var showQuestion = false
    @State private var showEarlier = false
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
                questionArea(group, days: days)
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
        .refreshable { await GroupStore.shared.reload(group.id) }
        .safeAreaInset(edge: .bottom) { composer(group, today: today) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let url = group.inviteURL {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: url, subject: Text("Join \(group.name) on Hearken"),
                              message: Text("Read \(group.plan?.title ?? "the scriptures") with me in Hearken. Open the link, or enter code \(group.inviteCode) under Study Groups › Join with Code.")) {
                        Label("Invite", systemImage: "person.badge.plus")
                    }
                    .tint(Color.primary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                CheckMenu(menuItems(group)) {
                    Label("Group Options", systemImage: "ellipsis")
                }
                .tint(Color.primary)
            }
        }
        .navigationDestination(isPresented: $showQuestion) {
            QuestionDetailView(groupID: group.id)
        }
        .navigationDestination(isPresented: $showEarlier) {
            EarlierQuestionsView(groupID: group.id)
        }
        .alert("Leave \(group.name)?", isPresented: $confirmLeave) {
            Button("Leave Group", role: .destructive) { Task { await leave(group, deleting: false) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(group.isOwner
                 ? "The group stays for everyone else, and a leader (or whoever has been in it longest) becomes its owner. Members will no longer see your progress."
                 : "You'll stop seeing the group, and members will no longer see your progress.")
        }
        .alert("Delete \(group.name)?", isPresented: $confirmDelete) {
            Button("Delete Group", role: .destructive) { Task { await leave(group, deleting: true) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the group and everything shared in it for every member.")
        }
        .sheet(isPresented: $showMembers) { GroupMembersSheet(groupID: group.id) }
        .sheet(isPresented: $showNotifications) { GroupNotificationSheet(groupID: group.id) }
        .sheet(isPresented: $asking) { AskQuestionSheet(groupID: group.id) }
        .sheet(item: $answering) { question in
            AnswerSheet(groupID: group.id, question: question) { showQuestion = true }
        }
        .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: GroupStore.shared.openQuestionGroupID, initial: true) { _, id in
            guard id == group.id else { return }
            GroupStore.shared.openQuestionGroupID = nil
            showQuestion = true
        }
    }

    private func menuItems(_ group: GroupStore.StudyGroup) -> [CheckMenuItem] {
        var items: [CheckMenuItem] = [
            .button("Notifications", systemImage: "bell") { showNotifications = true },
            .button("Members", systemImage: "person.2") { showMembers = true },
        ]
        if group.canModerate {
            items.append(.button(group.question?.isClosed == false ? "New Weekly Question" : "Ask Weekly Question", systemImage: "questionmark.bubble") { asking = true })
        }
        items.append(.button("Earlier Questions", systemImage: "clock.arrow.circlepath") { showEarlier = true })
        items.append(.button("Leave Group", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { confirmLeave = true })
        if group.isOwner {
            items.append(.button("Delete Group", systemImage: "trash", role: .destructive) { confirmDelete = true })
        }
        return items
    }

    private func header(_ group: GroupStore.StudyGroup) -> some View {
        AdaptiveStack(spacing: 14) {
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

    @ViewBuilder
    private func questionArea(_ group: GroupStore.StudyGroup, days: [PlanDay]) -> some View {
        if let question = group.question, question.isPosted, !question.isClosed {
            QuestionCard(group: group, question: question) {
                answering = question
            } onOpen: {
                showQuestion = true
            }
        } else if group.canModerate, group.scheduledQuestion == nil {
            AskQuestionPrompt { asking = true }
        }
        if let scheduled = group.scheduledQuestion {
            ScheduledQuestionCard(group: group, question: scheduled)
        }
    }

    private func week(_ group: GroupStore.StudyGroup, days: [PlanDay], me: String?) -> some View {
        let week = GroupSchedule.week(days)
        let readToday = group.members.filter(\.doneToday).count
        return VStack(alignment: .leading, spacing: 14) {
            AdaptiveStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("THIS WEEK").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Text(week.days.isEmpty ? "No reading this week" : PlanFormat.range(week.days.flatMap(\.chapterIDs)))
                        .font(.scripture(size: 22, weight: .bold))
                }
                Spacer(minLength: 8)
                Text("\(readToday) of \(group.members.count) read today")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 14) {
                ForEach(group.members) { member in
                    let current = member.weekStart.map { Calendar.current.isDate($0, inSameDayAs: week.start) } ?? false
                    let read = current ? member.weekRead : 0
                    let total = max(current ? member.weekTotal : week.days.flatMap(\.chapterIDs).count, 1)
                    VStack(spacing: 6) {
                        ZStack(alignment: .bottomTrailing) {
                            ProgressRing(progress: Double(read) / Double(total), lineWidth: 4) {
                                MemberAvatar(name: member.name, initials: member.initials, size: 46)
                            }
                            .frame(width: 60, height: 60)
                            .opacity(member.pending ? 0.5 : 1)
                            if member.doneToday {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .green)
                                    .background(Circle().fill(Color(.secondarySystemGroupedBackground)).padding(-2))
                            }
                        }
                        Text(member.userID == me ? "You" : member.firstName)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                        Text(member.pending ? "Updating" : "\(read) of \(total)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(member.userID == me ? "You" : member.name): \(read) of \(total) chapters this week\(member.doneToday ? ", read today" : "")")
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
                                              text: range, note: text, reference: range, to: group, authorName: account.displayName ?? "Member")
            reflection = ""
            composing = false
        } catch {
            errorMessage = GroupStore.describe(error, action: "share that")
        }
    }

    private func leave(_ group: GroupStore.StudyGroup, deleting: Bool) async {
        do {
            if deleting { try await GroupStore.shared.leave(group) } else { try await GroupStore.shared.leaveKeepingGroup(group) }
            dismiss()
        } catch {
            errorMessage = GroupStore.describe(error, action: deleting ? "delete the group" : "leave the group")
        }
    }
}

// MARK: - Shared posts

struct GroupItemCard: View {
    let item: GroupStore.SharedItem
    let group: GroupStore.StudyGroup
    let me: String?
    /// The thread shows the post without its reply preview.
    var showsReplies = true

    @Environment(ContentService.self) private var content

    var body: some View {
        let mine = item.authorID == me
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                MemberAvatar(name: item.authorName, initials: groupInitials(item.authorName))
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
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { reactions; replyChip; Spacer(minLength: 0); openLink }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) { reactions; replyChip }
                    openLink
                }
            }
            if showsReplies, let latest = item.latestComment {
                Divider().padding(.vertical, 2)
                NavigationLink(value: ThreadRoute(groupID: group.id, target: .item, targetID: item.id)) {
                    HStack(alignment: .top, spacing: 10) {
                        MemberAvatar(name: latest.authorName, initials: groupInitials(latest.authorName), size: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            (Text(latest.authorID == me ? "You" : groupFirstName(latest.authorName)).fontWeight(.semibold) + Text(" ") + Text(latest.body))
                                .font(.subheadline)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                            Text(item.commentCount == 1 ? "View reply" : "View all \(item.commentCount) replies")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tint)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        .contextMenu {
            if mine || group.canModerate {
                Button(role: .destructive) {
                    Task { await GroupStore.shared.delete(item, from: group) }
                } label: {
                    Label { Text("Delete") } icon: { Image.redTrash }
                }
            }
        }
        .tint(Color.primary)
    }

    private var reactions: some View {
        HStack(spacing: 8) {
            ReactionChip(kind: .heart, reactions: item.reactions, me: me) {
                Task { await GroupStore.shared.toggle(.heart, on: item, in: group) }
            }
            ReactionChip(kind: .insight, reactions: item.reactions, me: me) {
                Task { await GroupStore.shared.toggle(.insight, on: item, in: group) }
            }
        }
    }

    @ViewBuilder
    private var replyChip: some View {
        if showsReplies {
            NavigationLink(value: ThreadRoute(groupID: group.id, target: .item, targetID: item.id)) {
                HStack(spacing: 5) {
                    Image(systemName: "bubble.left")
                    Text(item.commentCount > 0 ? "\(item.commentCount)" : "Reply").monospacedDigit()
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(item.commentCount > 0 ? AnyShapeStyle(Accent.color) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 10)
                .frame(minHeight: 30)
                .background(item.commentCount > 0 ? AnyShapeStyle(Accent.color.opacity(0.12)) : AnyShapeStyle(.quaternary.opacity(0.6)), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.commentCount == 0 ? "Reply" : "\(item.commentCount) replies")
        }
    }

    @ViewBuilder
    private var openLink: some View {
        if !item.chapterID.isEmpty {
            NavigationLink {
                ReaderView(chapterID: item.chapterID, verse: item.startVerse > 0 ? item.startVerse : nil)
            } label: {
                Label("Open", systemImage: "book")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.borderless)
        }
    }

    private var reference: String {
        if !item.reference.isEmpty { return item.reference }
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
}

/// A heart or insight button with its count, filled when it's mine.
struct ReactionChip: View {
    let kind: GroupStore.Reaction.Kind
    let reactions: [GroupStore.Reaction]
    let me: String?
    var compact = false
    let action: () -> Void

    var body: some View {
        let all = reactions.filter { $0.kind == kind }
        let mine = all.contains { $0.userID == me }
        let color: Color = kind == .heart ? .pink : .orange
        let symbol = kind == .heart ? "heart" : "lightbulb"
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: mine ? symbol + ".fill" : symbol)
                    .foregroundStyle(mine ? color : .secondary)
                if !all.isEmpty { Text("\(all.count)").monospacedDigit() }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, compact ? 4 : 10)
            .frame(minHeight: compact ? 28 : 30)
            .background(compact ? AnyShapeStyle(.clear) : (mine ? AnyShapeStyle(color.opacity(0.14)) : AnyShapeStyle(.quaternary.opacity(0.6))), in: Capsule())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: mine)
        .accessibilityLabel(kind == .heart ? "Heart" : "Insight")
        .accessibilityValue("\(all.count)")
        .accessibilityAddTraits(mine ? .isSelected : [])
    }
}

func groupInitials(_ name: String) -> String {
    name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
}

func groupFirstName(_ name: String) -> String {
    name.split(separator: " ").first.map(String.init) ?? name
}

// MARK: - Members

private struct GroupMembersSheet: View {
    let groupID: String

    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var confirmReset = false
    @State private var removing: GroupStore.Member?

    var body: some View {
        let store = GroupStore.shared
        NavigationStack {
            List {
                if let group = store.group(groupID) {
                    Section {
                        ForEach(group.members) { member in
                            row(member, in: group, me: store.myUserID)
                        }
                    } footer: {
                        Text(group.canModerate
                             ? "Swipe a name to remove someone. Removing someone stops them seeing the group."
                             : "The owner and leaders can remove people.")
                    }
                    Section {
                        InviteCodeView(code: group.inviteCode)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                        if let url = group.inviteURL {
                            ShareLink(item: url, subject: Text("Join \(group.name) on Hearken"),
                                      message: Text("Open the link, or enter code \(group.inviteCode) under Study Groups › Join with Code.")) {
                                Label { Text("Send Invite Link") } icon: { Image.menuIcon("square.and.arrow.up") }
                            }
                            .tint(Color.primary)
                        }
                        if group.canModerate {
                            Button {
                                confirmReset = true
                            } label: {
                                Label { Text("Reset Invite Code") } icon: { Image.menuIcon("arrow.clockwise") }
                            }
                            .tint(Color.primary)
                        }
                    } header: {
                        Text("Invite")
                    } footer: {
                        Text("Anyone with the code or link can join. Resetting makes old invites stop working.")
                    }
                    if let errorMessage {
                        Section { Text(errorMessage).foregroundStyle(.red) }
                    }
                }
            }
            .refreshable { await store.reload(groupID) }
            .navigationTitle("Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { SheetDoneButton { dismiss() } }
            }
            .alert("Reset the invite code?", isPresented: $confirmReset) {
                Button("Reset", role: .destructive) { Task { await resetInvite() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Links and codes you've already sent will stop working.")
            }
            .alert("Remove \(removing?.name ?? "")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
                Button("Remove", role: .destructive) {
                    if let member = removing { Task { await remove(member) } }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("They'll stop seeing the group. What they shared stays.")
            }
        }
        .tint(Accent.color)
    }

    @ViewBuilder
    private func row(_ member: GroupStore.Member, in group: GroupStore.StudyGroup, me: String?) -> some View {
        let canRemove = member.userID != me && member.role != .owner && (group.isOwner || (group.canModerate && member.role == .member))
        HStack(spacing: 12) {
            MemberAvatar(name: member.name, initials: member.initials, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.userID == me ? "\(member.name) (You)" : member.name)
                Text(member.pending ? "Still on the iCloud version" : member.role.title)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if group.isOwner, member.userID != me, !member.pending {
                Menu {
                    if member.role == .leader {
                        Button("Make Member", menuIcon: "person") { Task { await setRole(.member, member) } }
                    } else {
                        Button("Make Leader", menuIcon: "star") { Task { await setRole(.leader, member) } }
                    }
                    Button("Make Owner", menuIcon: "crown") { Task { await setRole(.owner, member) } }
                } label: {
                    Label("Role", systemImage: "ellipsis.circle").labelStyle(.iconOnly)
                }
                .tint(Color.primary)
            }
        }
        .accessibilityElement(children: .combine)
        .swipeActions {
            if canRemove {
                Button("Remove", systemImage: "person.badge.minus", role: .destructive) { removing = member }
            }
        }
    }

    private func setRole(_ role: GroupStore.Role, _ member: GroupStore.Member) async {
        guard let group = GroupStore.shared.group(groupID) else { return }
        do { try await GroupStore.shared.setRole(role, for: member, in: group) } catch { errorMessage = GroupStore.describe(error, action: "change that") }
    }

    private func remove(_ member: GroupStore.Member) async {
        guard let group = GroupStore.shared.group(groupID) else { return }
        do { try await GroupStore.shared.remove(member, from: group) } catch { errorMessage = GroupStore.describe(error, action: "remove them") }
        removing = nil
    }

    private func resetInvite() async {
        guard let group = GroupStore.shared.group(groupID) else { return }
        do { try await GroupStore.shared.resetInvite(for: group) } catch { errorMessage = GroupStore.describe(error, action: "reset the code") }
    }
}

// MARK: - Notifications

private struct GroupNotificationSheet: View {
    let groupID: String

    @Environment(\.dismiss) private var dismiss
    @State private var prefs = GroupStore.NotifyPrefs()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Replies to what I share", isOn: $prefs.replies)
                    Toggle("Mentions", isOn: $prefs.mentions)
                    Toggle("Every reply in the group", isOn: $prefs.allReplies)
                    Toggle("Weekly question", isOn: $prefs.question)
                    Toggle("Daily reading activity", isOn: $prefs.activity)
                } footer: {
                    Text("Choose what \(GroupStore.shared.group(groupID)?.name ?? "this group") sends you. Your other groups keep their own settings.")
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { SheetDoneButton { dismiss() } }
            }
        }
        .tint(Accent.color)
        .onAppear { prefs = GroupStore.shared.group(groupID)?.notifications ?? GroupStore.NotifyPrefs() }
        .onChange(of: prefs) { _, value in
            guard let group = GroupStore.shared.group(groupID), group.notifications != value else { return }
            Task { await GroupStore.shared.setNotifications(value, for: group) }
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
                                MemberAvatar(name: entry.item.authorName, initials: groupInitials(entry.item.authorName))
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
                            HStack(spacing: 16) {
                                NavigationLink(value: ThreadRoute(groupID: entry.group.id, target: .item, targetID: entry.item.id)) {
                                    Label(entry.item.commentCount == 0 ? "Reply" : "\(entry.item.commentCount) \(entry.item.commentCount == 1 ? "Reply" : "Replies")",
                                          systemImage: "bubble.left")
                                        .font(.footnote.weight(.semibold))
                                }
                                NavigationLink(value: GroupRoute(id: entry.group.id)) {
                                    Label("Open \(entry.group.name)", systemImage: "person.3")
                                        .font(.footnote.weight(.semibold))
                                }
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
            .navigationDestination(for: ThreadRoute.self) { route in
                GroupThreadView(route: route)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { SheetDoneButton { dismiss() } }
            }
        }
        .tint(Accent.color)
    }
}
