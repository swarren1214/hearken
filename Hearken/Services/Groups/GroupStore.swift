import Foundation
import Observation
import OSLog

/// Study groups, kept by the Hearth API (`/v1/hearken/*`, see hearth-api's README).
///
/// A group follows one reading plan from one start date. Members see each other's weekly
/// progress, share highlights and reflections, reply in threads, react, and answer a weekly
/// question. Nothing personal goes to the server except what a member shares to a group and
/// their progress on the group's plan; highlights, notes and plans stay in their own iCloud.
///
/// Groups need a Hearth account (Sign in with Apple, `HearthAPI`). The last list loaded is kept
/// on disk so groups show at once and offline, and writes made offline wait in `GroupOutbox`.
@MainActor
@Observable
final class GroupStore {
    static let shared = GroupStore()

    // MARK: State

    private(set) var groups: [StudyGroup] = []
    private(set) var hasLoaded = false
    private(set) var isRefreshing = false
    private(set) var lastError: String?
    /// My Hearth account id.
    private(set) var myUserID: String?
    /// No Hearth session: the Study Groups section asks the person to sign in.
    private(set) var needsAccount = false
    /// iCloud groups I'm in whose owner hasn't moved them to the new study groups yet.
    private(set) var waitingGroups: [WaitingGroup] = []
    /// An invite code from a link or the Join sheet, waiting for the person to choose Join.
    var pendingInviteCode: String?
    /// A group to open (after joining, or from a notification).
    var openGroupID: String?
    /// A thread to open on top of its group (from a notification).
    var openThread: ThreadRoute?
    /// A group's weekly question to open (from a notification).
    var openQuestionGroupID: String?

    /// My name and initials as groups show them; kept current by `GroupSideEffects`.
    @ObservationIgnored var profile = (name: "Member", initials: "")

    nonisolated struct WaitingGroup: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let ownerName: String
    }

    @ObservationIgnored private var refreshing: Task<Void, Never>?
    @ObservationIgnored private var wantsAnotherPass = false
    @ObservationIgnored private let outbox = GroupOutbox()
    private let log = Logger(subsystem: "com.stephenwarren.hearken", category: "groups")

    init() {
        loadCache()
    }

    func group(_ id: String) -> StudyGroup? { groups.first { $0.id == id } }

    // MARK: Loading

    /// Reloads every group. Safe to call often: calls while a reload runs wait for it, and it
    /// loads once more before finishing, so nobody's request is dropped.
    func refresh() async {
        // Screenshot mode (Debug): demo groups, never the API.
        if ScreenshotMode.isOn {
            loadDemo()
            return
        }
        if let refreshing {
            wantsAnotherPass = true
            await refreshing.value
            return
        }
        let task = Task {
            repeat {
                wantsAnotherPass = false
                await loadAll()
            } while wantsAnotherPass
        }
        refreshing = task
        isRefreshing = true
        await task.value
        refreshing = nil
        isRefreshing = false
    }

    private func loadAll() async {
        let api = HearthAPI.shared
        await api.followSharedSession()
        guard let me = await api.userID else {
            needsAccount = true
            hasLoaded = true
            // Still look for iCloud groups, so the sign-in card can say they're waiting.
            waitingGroups = await GroupMigration.waitingGroups()
            return
        }
        if me != myUserID, myUserID != nil {
            // Someone else signed in: nothing from the last person's groups stays on screen.
            groups = []
            outbox.clear()
        }
        myUserID = me
        needsAccount = false
        do {
            await outbox.flush()
            // Groups that were in iCloud move to the server the first time each member's
            // device gets here (see GroupMigration).
            waitingGroups = await GroupMigration.run(store: self)
            let data = try await api.data("GET", "/v1/hearken/groups")
            let list = try GroupCoding.decoder.decode(GroupList.self, from: data)
            groups = Self.sorted(list.items)
            saveCache(data, userID: me)
            lastError = nil
        } catch HearthAPI.ClientError.notConnected {
            needsAccount = true
        } catch {
            log.error("refresh failed: \(String(describing: error), privacy: .public)")
            lastError = Self.describe(error)
        }
        hasLoaded = true
    }

    private nonisolated struct GroupList: Decodable {
        let items: [StudyGroup]
    }

    private static func sorted(_ groups: [StudyGroup]) -> [StudyGroup] {
        groups.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Reloads one group, after a change made elsewhere (a notification, a thread).
    func reload(_ groupID: String) async {
        guard !ScreenshotMode.isOn else { return }
        do {
            let data = try await HearthAPI.shared.data("GET", "/v1/hearken/groups/\(groupID)")
            let group = try GroupCoding.decoder.decode(StudyGroup.self, from: data)
            replace(group)
        } catch let error as HearthAPI.APIError where error.status == 404 {
            groups.removeAll { $0.id == groupID }
        } catch {
            log.error("reload failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func replace(_ group: StudyGroup) {
        if let index = groups.firstIndex(where: { $0.id == group.id }) {
            groups[index] = group
        } else {
            groups = Self.sorted(groups + [group])
        }
    }

    // MARK: Cache

    private static var cacheURL: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "study-groups.json")
    }
    private static let cacheUserKey = "groups.cache.userID"

    private func loadCache() {
        guard !ScreenshotMode.isOn, let url = Self.cacheURL, let data = try? Data(contentsOf: url),
              let list = try? GroupCoding.decoder.decode(GroupList.self, from: data) else { return }
        groups = Self.sorted(list.items)
        myUserID = UserDefaults.standard.string(forKey: Self.cacheUserKey)
    }

    private func saveCache(_ data: Data, userID: String) {
        guard let url = Self.cacheURL else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        UserDefaults.standard.set(userID, forKey: Self.cacheUserKey)
    }

    private func clearCache() {
        if let url = Self.cacheURL { try? FileManager.default.removeItem(at: url) }
        UserDefaults.standard.removeObject(forKey: Self.cacheUserKey)
    }

    // MARK: Requests

    /// Sends a request and decodes the reply.
    private func send<Reply: Decodable>(_ method: String, _ path: String, body: (any Encodable)? = nil, as: Reply.Type) async throws -> Reply {
        let data = try await HearthAPI.shared.data(method, path, body: body.map { try GroupCoding.encoder.encode($0) })
        return try GroupCoding.decoder.decode(Reply.self, from: data)
    }

    private func send(_ method: String, _ path: String, body: (any Encodable)? = nil) async throws {
        _ = try await HearthAPI.shared.data(method, path, body: body.map { try GroupCoding.encoder.encode($0) })
    }

    /// For writes that are safe to repeat: sends now, or queues it when offline.
    /// Returns false when it was queued.
    @discardableResult
    private func sendOrQueue(_ method: String, _ path: String, body: (any Encodable)? = nil) async throws -> Bool {
        let encoded = try body.map { try GroupCoding.encoder.encode($0) }
        do {
            _ = try await HearthAPI.shared.data(method, path, body: encoded)
            return true
        } catch where GroupOutbox.isOffline(error) {
            outbox.add(method: method, path: path, body: encoded)
            return false
        }
    }

    // MARK: Creating and joining

    private nonisolated struct CreateBody: Encodable {
        let clientId: String
        let name: String
        let symbol: String
        let planId: String
        let customPlan: CustomPlan?
        let startDate: String
        let displayName: String
        let initials: String
    }

    /// Creates a group and returns its id. The group is in `groups` when this returns.
    func create(name: String, symbol: String, plan: ReadingPlan, startDate: Date, ownerName: String) async throws -> String {
        let body = CreateBody(
            clientId: UUID().uuidString, name: name, symbol: symbol, planId: plan.id,
            customPlan: plan.isCustom ? CustomPlan(title: plan.title, chapterIDs: plan.chapterIDs, days: plan.days) : nil,
            startDate: GroupCoding.dayString(startDate), displayName: Self.clean(ownerName),
            initials: Self.cleanInitials(profile.initials, name: ownerName)
        )
        let group = try await send("POST", "/v1/hearken/groups", body: body, as: StudyGroup.self)
        replace(group)
        return group.id
    }

    func preview(code: String) async throws -> InvitePreview {
        try await send("GET", "/v1/hearken/invites/\(Self.normalized(code))", as: InvitePreview.self)
    }

    private nonisolated struct NameBody: Encodable {
        let displayName: String
        let initials: String
    }

    /// Joins with an invite code and opens the group.
    func join(code: String) async throws {
        let group = try await send("POST", "/v1/hearken/invites/\(Self.normalized(code))/join",
                                   body: NameBody(displayName: Self.clean(profile.name), initials: myInitials), as: StudyGroup.self)
        replace(group)
        pendingInviteCode = nil
        openGroupID = group.id
    }

    /// An invite code from anything the person might paste or open: the code itself, or an
    /// invite link (`https://api.hearthapps.com/hearken/join/ABCD2345`, `hearken://join/ABCD2345`).
    static func inviteCode(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = URL(string: trimmed).map(\.lastPathComponent).flatMap { $0.isEmpty || $0 == "/" ? nil : $0 } ?? trimmed
        let code = normalized(candidate)
        return code.count == 8 && code.allSatisfy({ "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".contains($0) }) ? code : nil
    }

    private static func normalized(_ code: String) -> String {
        code.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Owner: deletes the group for everyone. Anyone else: leaves it.
    func leave(_ group: StudyGroup) async throws {
        if group.isOwner {
            try await send("DELETE", "/v1/hearken/groups/\(group.id)")
        } else {
            try await leaveKeepingGroup(group)
        }
        groups.removeAll { $0.id == group.id }
    }

    /// Leaves without deleting. An owner who leaves hands the group to a leader, or to the
    /// person who has been in it longest.
    func leaveKeepingGroup(_ group: StudyGroup) async throws {
        guard let me = myUserID else { throw HearthAPI.ClientError.notConnected }
        try await send("DELETE", "/v1/hearken/groups/\(group.id)/members/\(me)")
        groups.removeAll { $0.id == group.id }
    }

    /// Owner or leader: removes someone.
    func remove(_ member: Member, from group: StudyGroup) async throws {
        let id = member.userID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? member.userID
        try await send("DELETE", "/v1/hearken/groups/\(group.id)/members/\(id)")
        update(group.id) { $0.members.removeAll { $0.userID == member.userID } }
    }

    private nonisolated struct RoleBody: Encodable { let role: Role }

    /// Owner: makes someone a leader or member, or hands them the group.
    func setRole(_ role: Role, for member: Member, in group: StudyGroup) async throws {
        let updated = try await send("PUT", "/v1/hearken/groups/\(group.id)/members/\(member.userID)/role",
                                     body: RoleBody(role: role), as: StudyGroup.self)
        replace(updated)
    }

    private nonisolated struct InviteReply: Decodable {
        let inviteCode: String
        let inviteURL: String
    }

    /// Owner or leader: replaces the invite code, so old links stop working.
    func resetInvite(for group: StudyGroup) async throws {
        let reply = try await send("POST", "/v1/hearken/groups/\(group.id)/invite-code", as: InviteReply.self)
        update(group.id) {
            $0.inviteCode = reply.inviteCode
            $0.inviteURL = URL(string: reply.inviteURL)
        }
    }

    // MARK: Progress

    private nonisolated struct ProgressBody: Encodable {
        let weekStart: String?
        let weekRead: Int
        let weekTotal: Int
        let lastDoneDay: String?
        let chaptersRead: Int
        let streak: Int
        let displayName: String
        let initials: String

        nonisolated enum CodingKeys: String, CodingKey {
            case weekStart, weekRead, weekTotal, lastDoneDay, chaptersRead, streak, displayName, initials
        }

        /// The server needs `weekStart` and `lastDoneDay` present, as null when unknown.
        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(weekStart, forKey: .weekStart)
            try values.encode(weekRead, forKey: .weekRead)
            try values.encode(weekTotal, forKey: .weekTotal)
            try values.encode(lastDoneDay, forKey: .lastDoneDay)
            try values.encode(chaptersRead, forKey: .chaptersRead)
            try values.encode(streak, forKey: .streak)
            try values.encode(displayName, forKey: .displayName)
            try values.encode(initials, forKey: .initials)
        }
    }

    /// Sends my progress if it changed since what the group last saw.
    func publish(_ progress: Progress, in group: StudyGroup, name: String, initials: String) async {
        guard let me = myUserID else { return }
        let current = group.members.first { $0.userID == me }
        let lastDone = progress.doneToday ? Calendar.current.startOfDay(for: .now) : current?.lastDoneDay
        if let current, current.name == name, current.initials == initials, current.weekStart == progress.weekStart,
           current.weekRead == progress.weekRead, current.weekTotal == progress.weekTotal,
           current.chaptersRead == progress.chaptersRead, current.streak == progress.streak, current.lastDoneDay == lastDone {
            return
        }
        let member = Member(userID: me, name: name, initials: initials, role: current?.role ?? group.role,
                            weekStart: progress.weekStart, weekRead: progress.weekRead, weekTotal: progress.weekTotal,
                            lastDoneDay: lastDone, chaptersRead: progress.chaptersRead, streak: progress.streak)
        update(group.id) { group in
            if let index = group.members.firstIndex(where: { $0.userID == me }) { group.members[index] = member }
            else { group.members.insert(member, at: 0) }
        }
        // Screenshot mode (Debug): show my real progress in the demo group without sending it.
        guard !ScreenshotMode.isOn else { return }
        let body = ProgressBody(
            weekStart: GroupCoding.dayString(progress.weekStart), weekRead: progress.weekRead, weekTotal: progress.weekTotal,
            lastDoneDay: lastDone.map(GroupCoding.dayString), chaptersRead: progress.chaptersRead, streak: progress.streak,
            displayName: Self.clean(name), initials: Self.cleanInitials(initials, name: name)
        )
        do {
            try await sendOrQueue("PUT", "/v1/hearken/groups/\(group.id)/progress", body: body)
        } catch {
            log.error("publish failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Shared items

    private nonisolated struct ItemBody: Encodable {
        let clientId: String
        let kind: SharedItem.Kind
        let chapterId: String
        let startVerse: Int
        let endVerse: Int
        let text: String
        let note: String
        let reference: String
        let authorName: String
    }

    func share(kind: SharedItem.Kind, chapterID: String, startVerse: Int, endVerse: Int, text: String, note: String,
               reference: String = "", to group: StudyGroup, authorName: String) async throws {
        // The server's limits: 4,000 characters of verse text, 2,000 of note, 80 of reference.
        let text = String(text.prefix(4000)), note = String(note.prefix(2000)), reference = String(reference.prefix(80))
        let body = ItemBody(clientId: UUID().uuidString, kind: kind, chapterId: String(chapterID.prefix(64)), startVerse: startVerse,
                            endVerse: endVerse, text: text, note: note, reference: reference, authorName: Self.clean(authorName))
        do {
            let item = try await send("POST", "/v1/hearken/groups/\(group.id)/items", body: body, as: SharedItem.self)
            update(group.id) { $0.items.insert(item, at: 0) }
        } catch where GroupOutbox.isOffline(error) {
            // Offline: show it now; it's sent (once, by its clientId) when the connection is back.
            outbox.add(method: "POST", path: "/v1/hearken/groups/\(group.id)/items", body: try GroupCoding.encoder.encode(body))
            let pending = SharedItem(id: body.clientId, kind: kind, chapterID: chapterID, startVerse: startVerse, endVerse: endVerse,
                                     text: text, note: note, reference: reference, authorID: myUserID ?? "", authorName: authorName,
                                     createdAt: .now)
            update(group.id) { $0.items.insert(pending, at: 0) }
        }
    }

    func delete(_ item: SharedItem, from group: StudyGroup) async {
        do {
            try await send("DELETE", "/v1/hearken/groups/\(group.id)/items/\(item.id)")
            update(group.id) { $0.items.removeAll { $0.id == item.id } }
        } catch {
            lastError = Self.describe(error, action: "delete that")
        }
    }

    // MARK: Reactions

    /// Adds or removes my reaction on a post, reply or answer. Posts and answers update here at
    /// once; a thread updates its own copy.
    func setReaction(_ kind: Reaction.Kind, on: Bool, target: TargetType, id targetID: String, in groupID: String) async {
        guard let me = myUserID else { return }
        let change: ([Reaction]) -> [Reaction] = { reactions in
            var result = reactions.filter { !($0.userID == me && $0.kind == kind) }
            if on { result.append(Reaction(kind: kind, userID: me)) }
            return result
        }
        update(groupID) { group in
            if target == .item, let index = group.items.firstIndex(where: { $0.id == targetID }) {
                group.items[index].reactions = change(group.items[index].reactions)
            }
            if target == .answer, var question = group.question, let index = question.answers.firstIndex(where: { $0.id == targetID }) {
                question.answers[index].reactions = change(question.answers[index].reactions)
                group.question = question
            }
        }
        guard !ScreenshotMode.isOn else { return }
        do {
            try await sendOrQueue(on ? "PUT" : "DELETE", "/v1/hearken/groups/\(groupID)/reactions/\(target.rawValue)/\(targetID)/\(kind.rawValue)")
        } catch {
            log.error("reaction failed: \(String(describing: error), privacy: .public)")
            await reload(groupID)
        }
    }

    func toggle(_ kind: Reaction.Kind, on item: SharedItem, in group: StudyGroup) async {
        let mine = item.reactions.contains { $0.userID == myUserID && $0.kind == kind }
        await setReaction(kind, on: !mine, target: .item, id: item.id, in: group.id)
    }

    // MARK: Discussion

    private nonisolated struct CommentList: Decodable { let items: [Comment] }

    func comments(on target: TargetType, id targetID: String, in groupID: String) async throws -> [Comment] {
        if ScreenshotMode.isOn { return Self.demoComments(target: targetID) }
        return try await send("GET", "/v1/hearken/groups/\(groupID)/comments?targetType=\(target.rawValue)&targetId=\(targetID)",
                              as: CommentList.self).items
    }

    private nonisolated struct CommentBody: Encodable {
        let clientId: String
        let targetType: TargetType
        let targetId: String
        let parentId: String?
        let body: String
        let mentions: [String]
        let mentionsEveryone: Bool
        let authorName: String
    }

    /// Replies to a post or answer (`parentID`: the reply being answered).
    func reply(_ text: String, on target: TargetType, id targetID: String, parentID: String?, mentions: [String],
               mentionsEveryone: Bool, in groupID: String) async throws -> Comment {
        let body = CommentBody(clientId: UUID().uuidString, targetType: target, targetId: targetID, parentId: parentID,
                               body: text, mentions: mentions, mentionsEveryone: mentionsEveryone, authorName: Self.clean(profile.name))
        let comment: Comment
        if ScreenshotMode.isOn {
            comment = Comment(id: body.clientId, targetType: target, targetID: targetID, parentID: parentID, authorID: myUserID ?? "",
                              authorName: profile.name, body: text, mentions: mentions, createdAt: .now)
        } else {
            comment = try await send("POST", "/v1/hearken/groups/\(groupID)/comments", body: body, as: Comment.self)
        }
        update(groupID) { group in
            if target == .item, let index = group.items.firstIndex(where: { $0.id == targetID }) {
                group.items[index].commentCount += 1
                group.items[index].latestComment = comment
            }
            if target == .answer, var question = group.question, let index = question.answers.firstIndex(where: { $0.id == targetID }) {
                question.answers[index].commentCount += 1
                group.question = question
            }
        }
        return comment
    }

    func deleteComment(_ comment: Comment, in groupID: String) async throws {
        if !ScreenshotMode.isOn {
            try await send("DELETE", "/v1/hearken/groups/\(groupID)/comments/\(comment.id)")
        }
        await reload(groupID)
    }

    // MARK: Weekly question

    private nonisolated struct QuestionBody: Encodable {
        let clientId: String
        let text: String
        let reference: String
        let chapterId: String
        let postAt: Date?
        let hideAnswers: Bool
        let authorName: String
    }

    /// Owner or leader: posts the weekly question now, or at `postAt`.
    func ask(_ text: String, reference: String, chapterID: String, postAt: Date?, hideAnswers: Bool, in group: StudyGroup) async throws {
        let body = QuestionBody(clientId: UUID().uuidString, text: text, reference: reference, chapterId: chapterID, postAt: postAt,
                                hideAnswers: hideAnswers, authorName: Self.clean(profile.name))
        let question = try await send("POST", "/v1/hearken/groups/\(group.id)/questions", body: body, as: Question.self)
        update(group.id) {
            // A question posted now replaces any scheduled one (the server deletes it too).
            if question.isPosted {
                $0.question = question
                $0.scheduledQuestion = nil
            } else {
                $0.scheduledQuestion = question
            }
        }
    }

    func deleteQuestion(_ question: Question, in group: StudyGroup) async throws {
        try await send("DELETE", "/v1/hearken/groups/\(group.id)/questions/\(question.id)")
        update(group.id) {
            if $0.question?.id == question.id { $0.question = nil }
            if $0.scheduledQuestion?.id == question.id { $0.scheduledQuestion = nil }
        }
    }

    private nonisolated struct AnswerBody: Encodable {
        let body: String
        let authorName: String
    }

    /// Posts (or edits) my answer. The group's question then shows everyone's answers.
    func answer(_ text: String, to question: Question, in group: StudyGroup) async throws {
        if ScreenshotMode.isOn {
            revealDemoAnswers(text, groupID: group.id)
            return
        }
        let updated = try await send("PUT", "/v1/hearken/groups/\(group.id)/questions/\(question.id)/answer",
                                     body: AnswerBody(body: text, authorName: Self.clean(profile.name)), as: Question.self)
        update(group.id) { if $0.question?.id == updated.id { $0.question = updated } }
    }

    private nonisolated struct QuestionList: Decodable { let items: [Question] }

    /// Every question the group has had, newest first.
    func questions(in group: StudyGroup) async throws -> [Question] {
        if ScreenshotMode.isOn { return group.question.map { [$0] } ?? [] }
        return try await send("GET", "/v1/hearken/groups/\(group.id)/questions", as: QuestionList.self).items
    }

    // MARK: Notifications

    func setNotifications(_ prefs: NotifyPrefs, for group: StudyGroup) async {
        update(group.id) { $0.notifications = prefs }
        guard !ScreenshotMode.isOn else { return }
        do {
            try await sendOrQueue("PUT", "/v1/hearken/groups/\(group.id)/notifications", body: prefs)
        } catch {
            lastError = Self.describe(error, action: "save that")
        }
    }

    private nonisolated struct PushBody: Encodable {
        let token: String
        let environment: String
        let enabled: Bool
    }

    private static let pushTokenKey = "groups.pushToken"

    /// This device's APNs token, from the app delegate. Sent whenever it changes or someone signs in.
    func updatePushToken(_ token: Data) async {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: Self.pushTokenKey)
        await sendPushToken()
    }

    private func sendPushToken() async {
        guard !ScreenshotMode.isOn, myUserID != nil, let hex = UserDefaults.standard.string(forKey: Self.pushTokenKey) else { return }
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        do {
            try await sendOrQueue("PUT", "/v1/hearken/push-tokens", body: PushBody(token: hex, environment: environment, enabled: true))
        } catch {
            log.error("push token failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Signing out: this device stops getting the account's group notifications. Sent directly
    /// (not queued), while the session still exists.
    func disablePushToken() async {
        guard !ScreenshotMode.isOn, let hex = UserDefaults.standard.string(forKey: Self.pushTokenKey) else { return }
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        try? await send("PUT", "/v1/hearken/push-tokens", body: PushBody(token: hex, environment: environment, enabled: false))
    }

    /// A study group push arrived: refresh, so the screen matches what it said.
    static func isGroupNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
        userInfo["hearken"] != nil || GroupMigration.isLegacyNotification(userInfo)
    }

    /// Where a tapped study group notification goes (its `hearken` payload).
    func open(groupID: String, kind: String?, targetType: String?, targetID: String?) {
        // The thread is set first: opening the group pushes it on top.
        switch kind {
        case "comment":
            if let type = targetType.flatMap(TargetType.init(rawValue:)), let targetID {
                openThread = ThreadRoute(groupID: groupID, target: type, targetID: targetID)
            }
        case "question", "answer":
            openQuestionGroupID = groupID
        default:
            break
        }
        openGroupID = groupID
        Task { await reload(groupID) }
    }

    // MARK: Account

    /// Signed in: sends the push token. Called when the Hearth session appears.
    func didConnect() async {
        await sendPushToken()
    }

    /// Delete Account: hands owned groups on and removes everything I wrote, then forgets the
    /// groups on this device.
    func deleteMyData() async {
        if !ScreenshotMode.isOn {
            do {
                try await send("DELETE", "/v1/hearken/me")
            } catch {
                log.error("delete my data failed: \(String(describing: error), privacy: .public)")
            }
        }
        forget()
    }

    /// Signed out: nothing from this person's groups stays on the device.
    func forget() {
        groups = []
        myUserID = nil
        outbox.clear()
        clearCache()
    }

    /// Kept for Settings › Delete Account.
    func leaveAll() async {
        await deleteMyData()
    }

    // MARK: Screenshot mode

    /// GroupDemo.swift only (screenshot mode).
    func demoSetUser(_ id: String) { myUserID = id }

    /// GroupDemo.swift only (screenshot mode).
    func demoSetGroups(_ demo: [StudyGroup]) {
        groups = demo
        needsAccount = false
        hasLoaded = true
    }

    // MARK: Helpers

    private func update(_ id: String, _ change: (inout StudyGroup) -> Void) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        change(&groups[index])
    }

    private var myInitials: String { Self.cleanInitials(profile.initials, name: profile.name) }

    static func clean(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Member" : String(trimmed.prefix(60))
    }

    static func initials(_ name: String) -> String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        return letters.isEmpty ? "M" : letters
    }

    private static func cleanInitials(_ initials: String, name: String) -> String {
        let trimmed = initials.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.initials(name) : String(trimmed.prefix(3))
    }

    /// A plain message for people; the detail goes to the log.
    static func describe(_ error: Error, action: String = "load") -> String {
        Logger(subsystem: "com.stephenwarren.hearken", category: "groups")
            .error("\(action, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        if let error = error as? HearthAPI.APIError {
            // The API's messages are written for people, except for outages.
            return error.status >= 500 ? "Study groups are having trouble right now. Try again in a moment." : error.message
        }
        if let error = error as? HearthAPI.ClientError {
            return error.errorDescription ?? "Sign in with Apple to use study groups."
        }
        if GroupOutbox.isOffline(error) {
            return "You're offline. Try again when you're back online."
        }
        return "Study groups couldn't \(action) right now. Try again in a moment."
    }
}

/// A thread opened over its group: replies on a post or an answer.
struct ThreadRoute: Hashable, Identifiable {
    let groupID: String
    let target: GroupStore.TargetType
    let targetID: String
    var id: String { "\(groupID)|\(target.rawValue)|\(targetID)" }
}

// MARK: - Offline writes

/// Writes made while offline, sent in order when the connection is back. Only writes that are
/// safe to send twice are queued: progress, reactions, settings, and posts with a client id.
@MainActor
final class GroupOutbox {
    private nonisolated struct Pending: Codable {
        let method: String
        let path: String
        let body: Data?
    }

    private static let key = "groups.outbox.v1"
    private var pending: [Pending]
    private var flushing = false

    init() {
        pending = (UserDefaults.standard.data(forKey: Self.key)).flatMap { try? JSONDecoder().decode([Pending].self, from: $0) } ?? []
    }

    func add(method: String, path: String, body: Data?) {
        // A newer progress or setting replaces an older one for the same thing.
        if method == "PUT" { pending.removeAll { $0.method == "PUT" && $0.path == path } }
        pending.append(Pending(method: method, path: path, body: body))
        if pending.count > 200 { pending.removeFirst(pending.count - 200) }
        save()
    }

    func flush() async {
        guard !flushing, !pending.isEmpty else { return }
        flushing = true
        defer { flushing = false }
        while let next = pending.first {
            do {
                _ = try await HearthAPI.shared.data(next.method, next.path, body: next.body)
            } catch where Self.isOffline(error) {
                return
            } catch let error as HearthAPI.APIError where error.status >= 500 || error.status == 429 {
                return
            } catch is HearthAPI.ClientError {
                // Signed out, or the sign-in service had trouble: try again later.
                return
            } catch {
                // Refused for good (the group is gone, or it's no longer allowed): drop it.
            }
            pending.removeFirst()
            save()
        }
    }

    func clear() {
        pending = []
        save()
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(pending), forKey: Self.key)
    }

    nonisolated static func isOffline(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost,
                .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff].contains(error.code)
    }
}
