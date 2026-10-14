import CloudKit
import Foundation
import Observation
import OSLog
import UserNotifications

/// Study groups, stored with CloudKit sharing.
///
/// Each group is a custom record zone in its creator's private database, shared with a
/// zone-wide CKShare. Members see the zone in their shared database and read and write
/// there. Nothing goes through a server of our own, and nothing personal is shared except
/// each member's progress on the group's plan and the items they choose to share.
///
/// SwiftData can't sync shared data, so this talks to CloudKit directly. Personal data
/// (highlights, notes, plans) stays in SwiftData.
@MainActor
@Observable
final class GroupStore {
    static let shared = GroupStore()

    // MARK: Types

    struct StudyGroup: Identifiable, Hashable {
        let zoneID: CKRecordZone.ID
        let isOwner: Bool
        var name: String
        var symbol: String
        var planID: String
        var startDate: Date
        var ownerName: String
        /// Custom plans travel with the group, since members don't have them.
        var customTitle = ""
        var customChapterIDs: [String] = []
        var customDays = 0
        var shareURL: URL?
        var members: [Member] = []
        var items: [SharedItem] = []
        var reactions: [Reaction] = []

        var id: String { zoneID.zoneName + "|" + zoneID.ownerName }
        var plan: ReadingPlan? {
            if planID == ReadingPlan.customID {
                guard !customChapterIDs.isEmpty else { return nil }
                return ReadingPlan(id: ReadingPlan.customID, title: customTitle.isEmpty ? "Custom Plan" : customTitle,
                                   subtitle: PlanFormat.range(customChapterIDs), days: max(customDays, 1),
                                   coverHex: 0x5A5A63, chapterIDs: customChapterIDs)
            }
            return ReadingPlanCatalog.plans.first { $0.id == planID }
        }
    }

    /// One member's progress, written by that member only.
    struct Member: Identifiable, Hashable {
        let userID: String
        var name: String
        var initials: String
        /// Start of the week the counts below are for.
        var weekStart: Date?
        var weekRead: Int
        var weekTotal: Int
        /// The day this member last finished the group's assignment.
        var lastDoneDay: Date?
        var chaptersRead: Int
        var streak: Int
        var id: String { userID }
    }

    struct SharedItem: Identifiable, Hashable {
        enum Kind: String { case highlight, reflection }
        let id: String
        let kind: Kind
        let chapterID: String
        let startVerse: Int
        let endVerse: Int
        /// The scripture text (highlights).
        let text: String
        /// What the member wrote (reflections, or a thought on a highlight).
        let note: String
        let authorID: String
        let authorName: String
        let createdAt: Date
    }

    struct Reaction: Hashable {
        enum Kind: String, CaseIterable { case heart, insight }
        let recordName: String
        let itemID: String
        let kind: Kind
        let authorID: String
    }

    /// My progress, as the group page shows it and other members see it.
    struct Progress: Equatable {
        var weekStart: Date
        var weekRead: Int
        var weekTotal: Int
        var doneToday: Bool
        var chaptersRead: Int
        var streak: Int
    }

    // MARK: State

    private(set) var groups: [StudyGroup] = []
    private(set) var hasLoaded = false
    private(set) var isRefreshing = false
    private(set) var lastError: String?
    private(set) var myUserID: String?
    /// An invite the person tapped, waiting for them to choose Join.
    var pendingInvite: CKShare.Metadata?
    /// A group to open (after joining, or from a notification).
    var openGroupID: String?

    /// The reload in flight. Callers that ask for another while it runs wait for it, and it
    /// loads once more before finishing, so nobody's request is dropped.
    @ObservationIgnored private var refreshing: Task<Void, Never>?
    @ObservationIgnored private var wantsAnotherPass = false
    @ObservationIgnored private var notifyPending = false
    /// Groups created on this device that a reload hasn't found yet (CloudKit can take a
    /// moment). Kept in the list so a new group never disappears.
    @ObservationIgnored private var justCreated: [StudyGroup] = []

    private let container = CKContainer(identifier: AppConfig.cloudKitContainerID)
    private let log = Logger(subsystem: "com.stephenwarren.hearken", category: "groups")
    private static let zonePrefix = "group-"
    private enum RecordType {
        static let group = "StudyGroup"
        static let member = "GroupMember"
        static let item = "SharedItem"
        static let reaction = "Reaction"
    }

    func group(_ id: String) -> StudyGroup? { groups.first { $0.id == id } }

    private func database(for group: StudyGroup) -> CKDatabase {
        group.isOwner ? container.privateCloudDatabase : container.sharedCloudDatabase
    }

    // MARK: Loading

    /// Reloads every group. `notify` (from a silent push) posts activity notifications for
    /// anything new from other members.
    func refresh(notify: Bool = false) async {
        // Screenshot mode (Debug): demo groups, never CloudKit.
        if ScreenshotMode.isOn {
            loadDemo()
            return
        }
        guard AppConfig.cloudSyncEnabled else { return }
        if notify { notifyPending = true }
        if let refreshing {
            wantsAnotherPass = true
            await refreshing.value
            return
        }
        let task = Task {
            repeat {
                wantsAnotherPass = false
                let shouldNotify = notifyPending
                notifyPending = false
                await loadAll(notify: shouldNotify)
            } while wantsAnotherPass
        }
        refreshing = task
        isRefreshing = true
        await task.value
        refreshing = nil
        isRefreshing = false
    }

    private func loadAll(notify: Bool) async {
        do {
            if myUserID == nil { myUserID = try await container.userRecordID().recordName }
            let owned = try await container.privateCloudDatabase.allRecordZones()
                .filter { $0.zoneID.zoneName.hasPrefix(Self.zonePrefix) }
            let joined = try await container.sharedCloudDatabase.allRecordZones()

            var loaded: [StudyGroup] = []
            for zone in owned {
                do {
                    if let group = try await load(zone.zoneID, from: container.privateCloudDatabase, isOwner: true) { loaded.append(group) }
                } catch {
                    log.error("load owned group failed: \(error.localizedDescription, privacy: .public)")
                    // A brief failure shouldn't make the group vanish: keep the last copy.
                    if let previous = groups.first(where: { $0.zoneID == zone.zoneID }) { loaded.append(previous) }
                }
            }
            for zone in joined {
                do {
                    if let group = try await load(zone.zoneID, from: container.sharedCloudDatabase, isOwner: false) { loaded.append(group) }
                } catch {
                    log.error("load joined group failed: \(error.localizedDescription, privacy: .public)")
                    if let previous = groups.first(where: { $0.zoneID == zone.zoneID }) { loaded.append(previous) }
                }
            }
            // Keep groups just created here until CloudKit returns them.
            justCreated.removeAll { created in loaded.contains { $0.zoneID == created.zoneID } }
            // (A brand-new zone can take a moment to show up in the zone list too.)
            loaded.append(contentsOf: justCreated)
            for index in loaded.indices where loaded[index].shareURL == nil {
                loaded[index].shareURL = groups.first { $0.zoneID == loaded[index].zoneID }?.shareURL
            }
            groups = loaded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            lastError = nil
            GroupActivityNotifier.process(groups, me: myUserID, notify: notify)
        } catch {
            log.error("refresh failed: \(error.localizedDescription, privacy: .public)")
            lastError = Self.describe(error)
        }
        hasLoaded = true
    }

    private func load(_ zoneID: CKRecordZone.ID, from database: CKDatabase, isOwner: Bool) async throws -> StudyGroup? {
        var records: [CKRecord] = []
        var token: CKServerChangeToken?
        var more = true
        while more {
            let changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)
            for (_, result) in changes.modificationResultsByID {
                if case .success(let modification) = result { records.append(modification.record) }
            }
            token = changes.changeToken
            more = changes.moreComing
        }

        guard let root = records.first(where: { $0.recordType == RecordType.group }) else { return nil }
        var group = StudyGroup(
            zoneID: zoneID,
            isOwner: isOwner,
            name: root["name"] as? String ?? "Study Group",
            symbol: root["symbol"] as? String ?? "person.3",
            planID: root["planID"] as? String ?? "",
            startDate: root["startDate"] as? Date ?? .now,
            ownerName: root["ownerName"] as? String ?? "",
            customTitle: root["planTitle"] as? String ?? "",
            customChapterIDs: root["chapterIDs"] as? [String] ?? [],
            customDays: root["days"] as? Int ?? 0
        )
        for record in records {
            if let share = record as? CKShare {
                group.shareURL = share.url
                continue
            }
            switch record.recordType {
            case RecordType.member:
                group.members.append(Member(
                    userID: record["userID"] as? String ?? record.recordID.recordName,
                    name: record["name"] as? String ?? "Member",
                    initials: record["initials"] as? String ?? "",
                    weekStart: record["weekStart"] as? Date,
                    weekRead: record["weekRead"] as? Int ?? 0,
                    weekTotal: record["weekTotal"] as? Int ?? 0,
                    lastDoneDay: record["lastDoneDay"] as? Date,
                    chaptersRead: record["chaptersRead"] as? Int ?? 0,
                    streak: record["streak"] as? Int ?? 0
                ))
            case RecordType.item:
                group.items.append(SharedItem(
                    id: record.recordID.recordName,
                    kind: SharedItem.Kind(rawValue: record["kind"] as? String ?? "") ?? .reflection,
                    chapterID: record["chapterID"] as? String ?? "",
                    startVerse: record["startVerse"] as? Int ?? 0,
                    endVerse: record["endVerse"] as? Int ?? 0,
                    text: record["text"] as? String ?? "",
                    note: record["note"] as? String ?? "",
                    authorID: record["authorID"] as? String ?? "",
                    authorName: record["authorName"] as? String ?? "Member",
                    createdAt: record["createdAt"] as? Date ?? record.creationDate ?? .now
                ))
            case RecordType.reaction:
                if let kind = Reaction.Kind(rawValue: record["kind"] as? String ?? "") {
                    group.reactions.append(Reaction(
                        recordName: record.recordID.recordName,
                        itemID: record["itemID"] as? String ?? "",
                        kind: kind,
                        authorID: record["authorID"] as? String ?? ""
                    ))
                }
            default:
                break
            }
        }
        group.items.sort { $0.createdAt > $1.createdAt }
        group.members.sort { ($0.userID == myUserID ? 0 : 1, $0.name) < ($1.userID == myUserID ? 0 : 1, $1.name) }
        return group
    }

    // MARK: Creating and joining

    /// Creates a group and its share. Returns the new group's ID. The group is in `groups` when
    /// this returns; a reload then fills in anything CloudKit adds.
    func create(name: String, symbol: String, plan: ReadingPlan, startDate: Date, ownerName: String) async throws -> String {
        let database = container.privateCloudDatabase
        if myUserID == nil { myUserID = try await container.userRecordID().recordName }
        let zone = CKRecordZone(zoneName: Self.zonePrefix + UUID().uuidString)
        _ = try await database.save(zone)

        let start = Calendar.current.startOfDay(for: startDate)
        let root = CKRecord(recordType: RecordType.group, recordID: CKRecord.ID(recordName: "group", zoneID: zone.zoneID))
        root["name"] = name
        root["symbol"] = symbol
        root["planID"] = plan.id
        if plan.isCustom {
            root["planTitle"] = plan.title
            root["chapterIDs"] = plan.chapterIDs
            root["days"] = plan.days
        }
        root["startDate"] = start
        root["ownerName"] = ownerName

        let share = CKShare(recordZoneID: zone.zoneID)
        share[CKShare.SystemFieldKey.title] = name
        // Anyone with the invite link can join; the owner can remove people.
        share.publicPermission = .readWrite

        // modifyRecords reports a failed record in its results rather than throwing, so check
        // each one. Atomic: the group and its share save together or not at all.
        let saved: (saveResults: [CKRecord.ID: Result<CKRecord, Error>], deleteResults: [CKRecord.ID: Result<Void, Error>])
        do {
            saved = try await database.modifyRecords(saving: [root, share], deleting: [], savePolicy: .allKeys, atomically: true)
        } catch {
            await discard(zone.zoneID)
            throw error
        }
        for id in [root.recordID, share.recordID] {
            if case .failure(let error)? = saved.saveResults[id] {
                log.error("create failed for \(id.recordName, privacy: .public): \(String(describing: error), privacy: .public)")
                await discard(zone.zoneID)
                throw error
            }
        }

        var shareURL: URL?
        if case .success(let record)? = saved.saveResults[share.recordID] { shareURL = (record as? CKShare)?.url }
        if shareURL == nil {
            shareURL = (try? await database.record(for: share.recordID) as? CKShare)?.url
        }

        var group = StudyGroup(zoneID: zone.zoneID, isOwner: true, name: name, symbol: symbol, planID: plan.id, startDate: start, ownerName: ownerName)
        if plan.isCustom {
            group.customTitle = plan.title
            group.customChapterIDs = plan.chapterIDs
            group.customDays = plan.days
        }
        group.shareURL = shareURL
        justCreated.append(group)
        groups.removeAll { $0.zoneID == zone.zoneID }
        groups.append(group)
        groups.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        hasLoaded = true

        Task { await refresh() }
        return group.id
    }

    /// Removes a zone left half-made by a failed create.
    private func discard(_ zoneID: CKRecordZone.ID) async {
        _ = try? await container.privateCloudDatabase.deleteRecordZone(withID: zoneID)
    }

    /// Joins from an invite the person tapped (after they chose Join).
    func accept(_ metadata: CKShare.Metadata) async throws {
        _ = try await container.accept(metadata)
        pendingInvite = nil
        await refresh()
        let zoneID = metadata.share.recordID.zoneID
        openGroupID = groups.first { $0.zoneID.zoneName == zoneID.zoneName && $0.zoneID.ownerName == zoneID.ownerName }?.id
    }

    /// Delete Account: deletes the groups I created and leaves the ones I joined.
    func leaveAll() async {
        if !hasLoaded { await refresh() }
        for group in groups {
            do { try await leave(group) } catch {
                log.error("leave failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        UserDefaults.standard.removeObject(forKey: "groups.subscriptions.v1")
    }

    /// Activity notifications for one group (on by default).
    func notificationsEnabled(for groupID: String) -> Bool {
        UserDefaults.standard.object(forKey: "groups.notify.\(groupID)") as? Bool ?? true
    }

    /// Owner: deletes the group for everyone. Member: leaves it.
    func leave(_ group: StudyGroup) async throws {
        _ = try await database(for: group).deleteRecordZone(withID: group.zoneID)
        groups.removeAll { $0.id == group.id }
        justCreated.removeAll { $0.id == group.id }
    }

    // MARK: Members

    /// Writes my progress if it changed since what the group last saw.
    func publish(_ progress: Progress, in group: StudyGroup, name: String, initials: String) async {
        guard let me = myUserID else { return }
        if let current = group.members.first(where: { $0.userID == me }),
           current.name == name, current.weekStart == progress.weekStart, current.weekRead == progress.weekRead,
           current.weekTotal == progress.weekTotal, current.chaptersRead == progress.chaptersRead,
           current.streak == progress.streak,
           (current.lastDoneDay.map { Calendar.current.isDateInToday($0) } ?? false) == progress.doneToday {
            return
        }
        let record = CKRecord(recordType: RecordType.member, recordID: CKRecord.ID(recordName: "member-\(me)", zoneID: group.zoneID))
        record["userID"] = me
        record["name"] = name
        record["initials"] = initials
        record["weekStart"] = progress.weekStart
        record["weekRead"] = progress.weekRead
        record["weekTotal"] = progress.weekTotal
        record["chaptersRead"] = progress.chaptersRead
        record["streak"] = progress.streak
        let previousDone = group.members.first { $0.userID == me }?.lastDoneDay
        let lastDone = progress.doneToday ? Calendar.current.startOfDay(for: .now) : previousDone
        record["lastDoneDay"] = lastDone
        // Screenshot mode (Debug): show my real progress in the demo group without saving it.
        if ScreenshotMode.isOn {
            update(group.id) { group in
                let member = Member(userID: me, name: name, initials: initials, weekStart: progress.weekStart,
                                    weekRead: progress.weekRead, weekTotal: progress.weekTotal, lastDoneDay: lastDone,
                                    chaptersRead: progress.chaptersRead, streak: progress.streak)
                if let index = group.members.firstIndex(where: { $0.userID == me }) {
                    group.members[index] = member
                } else {
                    group.members.insert(member, at: 0)
                }
            }
            return
        }
        do {
            _ = try await database(for: group).modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            update(group.id) { group in
                let member = Member(userID: me, name: name, initials: initials, weekStart: progress.weekStart,
                                    weekRead: progress.weekRead, weekTotal: progress.weekTotal, lastDoneDay: lastDone,
                                    chaptersRead: progress.chaptersRead, streak: progress.streak)
                if let index = group.members.firstIndex(where: { $0.userID == me }) {
                    group.members[index] = member
                } else {
                    group.members.insert(member, at: 0)
                }
            }
        } catch {
            log.error("publish failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Owner: the people the group is shared with (for removing someone).
    func participants(of group: StudyGroup) async throws -> [CKShare.Participant] {
        guard group.isOwner else { return [] }
        let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: group.zoneID)
        guard let share = try await container.privateCloudDatabase.record(for: id) as? CKShare else { return [] }
        return share.participants.filter { $0.role != .owner }
    }

    /// Owner: removes someone from the group.
    func remove(_ participant: CKShare.Participant, from group: StudyGroup) async throws {
        let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: group.zoneID)
        guard let share = try await container.privateCloudDatabase.record(for: id) as? CKShare else { return }
        share.removeParticipant(participant)
        _ = try await container.privateCloudDatabase.modifyRecords(saving: [share], deleting: [])
        if let userID = participant.userIdentity.userRecordID?.recordName {
            let memberID = CKRecord.ID(recordName: "member-\(userID)", zoneID: group.zoneID)
            _ = try? await container.privateCloudDatabase.modifyRecords(saving: [], deleting: [memberID])
            update(group.id) { $0.members.removeAll { $0.userID == userID } }
        }
    }

    // MARK: Shared items and reactions

    func share(kind: SharedItem.Kind, chapterID: String, startVerse: Int, endVerse: Int, text: String, note: String,
               to group: StudyGroup, authorName: String) async throws {
        guard let me = myUserID else { return }
        let record = CKRecord(recordType: RecordType.item, recordID: CKRecord.ID(recordName: "item-\(UUID().uuidString)", zoneID: group.zoneID))
        let now = Date.now
        record["kind"] = kind.rawValue
        record["chapterID"] = chapterID
        record["startVerse"] = startVerse
        record["endVerse"] = endVerse
        record["text"] = text
        record["note"] = note
        record["authorID"] = me
        record["authorName"] = authorName
        record["createdAt"] = now
        _ = try await database(for: group).modifyRecords(saving: [record], deleting: [])
        update(group.id) { group in
            group.items.insert(SharedItem(id: record.recordID.recordName, kind: kind, chapterID: chapterID, startVerse: startVerse,
                                          endVerse: endVerse, text: text, note: note, authorID: me, authorName: authorName, createdAt: now), at: 0)
        }
    }

    func delete(_ item: SharedItem, from group: StudyGroup) async {
        let id = CKRecord.ID(recordName: item.id, zoneID: group.zoneID)
        let reactionIDs = group.reactions.filter { $0.itemID == item.id }.map { CKRecord.ID(recordName: $0.recordName, zoneID: group.zoneID) }
        do {
            _ = try await database(for: group).modifyRecords(saving: [], deleting: [id] + (group.isOwner ? reactionIDs : []))
            update(group.id) { group in
                group.items.removeAll { $0.id == item.id }
                group.reactions.removeAll { $0.itemID == item.id }
            }
        } catch {
            log.error("delete failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func toggle(_ kind: Reaction.Kind, on item: SharedItem, in group: StudyGroup) async {
        guard let me = myUserID else { return }
        let recordName = "reaction-\(item.id)-\(me)-\(kind.rawValue)"
        let id = CKRecord.ID(recordName: recordName, zoneID: group.zoneID)
        let exists = group.reactions.contains { $0.recordName == recordName }
        // Update the screen first; put it back if CloudKit refuses.
        update(group.id) { group in
            if exists { group.reactions.removeAll { $0.recordName == recordName } }
            else { group.reactions.append(Reaction(recordName: recordName, itemID: item.id, kind: kind, authorID: me)) }
        }
        do {
            if exists {
                _ = try await database(for: group).modifyRecords(saving: [], deleting: [id])
            } else {
                let record = CKRecord(recordType: RecordType.reaction, recordID: id)
                record["itemID"] = item.id
                record["kind"] = kind.rawValue
                record["authorID"] = me
                _ = try await database(for: group).modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            }
        } catch {
            log.error("reaction failed: \(error.localizedDescription, privacy: .public)")
            await refresh()
        }
    }

    // MARK: Development schema

    #if DEBUG
    /// Bump when a group record gains a field, so the next debug run pushes it.
    private static let schemaVersion = 1

    /// Debug builds only. Saves one record of each group type, every field filled in, to a
    /// throwaway zone in the development database, then deletes the zone. CloudKit only learns
    /// a record type or field when a record first uses it, and production refuses new ones, so
    /// this readies the whole group schema for Deploy Schema Changes without making a real group.
    func initializeSchemaIfNeeded() async {
        let key = "cloudkit.groupSchemaInitialized"
        guard UserDefaults.standard.integer(forKey: key) < Self.schemaVersion else { return }
        let database = container.privateCloudDatabase
        let zone = CKRecordZone(zoneName: "schema-setup-\(UUID().uuidString)")
        func record(_ type: String) -> CKRecord {
            CKRecord(recordType: type, recordID: CKRecord.ID(recordName: type, zoneID: zone.zoneID))
        }
        let group = record(RecordType.group)
        group["name"] = "Schema setup"
        group["symbol"] = "person.3"
        group["planID"] = "schema"
        group["planTitle"] = "Schema setup"
        group["chapterIDs"] = ["schema"]
        group["days"] = 1
        group["startDate"] = Date.now
        group["ownerName"] = "Schema"
        let member = record(RecordType.member)
        member["userID"] = "schema"
        member["name"] = "Schema"
        member["initials"] = "S"
        member["weekStart"] = Date.now
        member["weekRead"] = 0
        member["weekTotal"] = 0
        member["chaptersRead"] = 0
        member["streak"] = 0
        member["lastDoneDay"] = Date.now
        let item = record(RecordType.item)
        item["kind"] = "highlight"
        item["chapterID"] = "schema"
        item["startVerse"] = 1
        item["endVerse"] = 1
        item["text"] = "Schema"
        item["note"] = "Schema"
        item["authorID"] = "schema"
        item["authorName"] = "Schema"
        item["createdAt"] = Date.now
        let reaction = record(RecordType.reaction)
        reaction["itemID"] = "schema"
        reaction["kind"] = "heart"
        reaction["authorID"] = "schema"
        do {
            _ = try await database.modifyRecordZones(saving: [zone], deleting: [])
            _ = try await database.modifyRecords(saving: [group, member, item, reaction], deleting: [], savePolicy: .allKeys)
            UserDefaults.standard.set(Self.schemaVersion, forKey: key)
            log.info("Group schema initialized (version \(Self.schemaVersion))")
        } catch {
            // Usually: not signed in to iCloud on this device. It tries again next launch.
            log.error("Group schema: \(error.localizedDescription, privacy: .public)")
        }
        _ = try? await database.deleteRecordZone(withID: zone.zoneID)
    }
    #endif

    // MARK: Live updates

    /// Silent pushes when anything in the private or shared database changes.
    func ensureSubscriptions() async {
        let key = "groups.subscriptions.v1"
        guard !ScreenshotMode.isOn, AppConfig.cloudSyncEnabled, !UserDefaults.standard.bool(forKey: key) else { return }
        do {
            for (database, id) in [(container.privateCloudDatabase, "groups-private"), (container.sharedCloudDatabase, "groups-shared")] {
                let subscription = CKDatabaseSubscription(subscriptionID: id)
                let info = CKSubscription.NotificationInfo()
                info.shouldSendContentAvailable = true
                subscription.notificationInfo = info
                _ = try await database.save(subscription)
            }
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            log.error("subscriptions failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func isGroupNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
        CKNotification(fromRemoteNotificationDictionary: userInfo)?.subscriptionID?.hasPrefix("groups-") ?? false
    }

    // MARK: Helpers

    private func update(_ id: String, _ change: (inout StudyGroup) -> Void) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        change(&groups[index])
    }

    /// A plain message for people; the CloudKit detail goes to the log.
    static func describe(_ error: Error, action: String = "load") -> String {
        Logger(subsystem: "com.stephenwarren.hearken", category: "groups")
            .error("\(action, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        if let error = error as? CKError {
            switch error.code {
            case .notAuthenticated: return "Sign in to iCloud in Settings to use study groups."
            case .networkUnavailable, .networkFailure: return "You're offline. Try again when you're back online."
            case .quotaExceeded: return "The group owner's iCloud storage is full."
            case .serviceUnavailable, .requestRateLimited, .zoneBusy:
                return "iCloud is busy right now. Try again in a moment."
            case .permissionFailure: return "iCloud didn't allow that. Check that iCloud Drive is on for Hearken in Settings."
            case .serverRejectedRequest, .invalidArguments, .badContainer:
                // Typically: the record types aren't deployed to the production schema yet.
                return "Study groups aren't available in this version yet. Try again after the next update."
            default:
                return "Study groups couldn't \(action) right now. Try again in a moment."
            }
        }
        return "Study groups couldn't \(action) right now. Try again in a moment."
    }
}

// MARK: - Activity notifications

/// "Ana finished today's reading" and "Marcus shared a reflection", posted on this phone when
/// a silent push brings group changes. Best effort: iOS may delay or drop silent pushes, so
/// some activity arrives late or only when the app next opens.
@MainActor
enum GroupActivityNotifier {
    private struct Event {
        let id: String
        let title: String
        let body: String
    }

    static func process(_ groups: [GroupStore.StudyGroup], me: String?, notify: Bool) {
        let defaults = UserDefaults.standard
        let today = Date.now.formatted(.iso8601.year().month().day())
        for group in groups {
            let key = "groups.seen.\(group.id)"
            let previous = defaults.stringArray(forKey: key)
            let seen = Set(previous ?? [])
            var events: [Event] = []

            for member in group.members where member.userID != me {
                guard let done = member.lastDoneDay, Calendar.current.isDateInToday(done) else { continue }
                events.append(Event(id: "done|\(member.userID)|\(today)",
                                    title: "\(firstName(member.name)) finished today's reading",
                                    body: group.name))
            }
            for item in group.items where item.authorID != me {
                let what = item.kind == .highlight ? "a highlight" : "a reflection"
                let detail = item.note.isEmpty ? item.text : item.note
                events.append(Event(id: "item|\(item.id)",
                                    title: "\(firstName(item.authorName)) shared \(what)",
                                    body: "\(group.name): \(detail.prefix(140))"))
            }

            let fresh = events.filter { !seen.contains($0.id) }
            // A group seen for the first time (just joined, or a new install) posts nothing.
            if previous != nil, notify, GroupStore.shared.notificationsEnabled(for: group.id) {
                for event in fresh.prefix(3) { post(event, groupID: group.id) }
            }
            // Remember only what still exists, so the list never grows.
            defaults.set(events.map(\.id), forKey: key)
        }
    }

    private static func post(_ event: Event, groupID: String) {
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.body
        content.sound = .default
        content.threadIdentifier = "group.\(groupID)"
        content.userInfo = ["groupID": groupID]
        let request = UNNotificationRequest(identifier: "hearken.group.\(event.id)", content: content, trigger: nil)
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }

    private static func firstName(_ name: String) -> String {
        name.split(separator: " ").first.map(String.init) ?? name
    }
}

// MARK: - Screenshot mode

extension GroupStore {
    private static let demoFamilyZone = CKRecordZone.ID(zoneName: "group-screenshots-family", ownerName: CKCurrentUserDefaultName)
    private static let demoClubZone = CKRecordZone.ID(zoneName: "group-screenshots-club", ownerName: "_screenshots-owner")

    /// The family group, for the group screenshot.
    static var demoGroupID: String { demoFamilyZone.zoneName + "|" + demoFamilyZone.ownerName }

    /// Two demo groups: a family reading the same plan as the demo reader (whose own row comes
    /// from their real progress, through `publish`), and a ward book club they joined.
    fileprivate func loadDemo() {
        guard !hasLoaded else { return }
        let content = ListenEngine.shared.scripture
        let calendar = Calendar.current
        let now = Date.now
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        myUserID = ScreenshotMode.demoUserID

        func verse(_ chapterID: String, _ number: Int) -> String {
            content.chapter(chapterID)?.verses.first { $0.number == number }?.text ?? ""
        }

        var family = StudyGroup(zoneID: Self.demoFamilyZone, isOwner: true, name: "Jensen Family", symbol: "house.fill",
                                planID: "bofm-90",
                                startDate: calendar.date(byAdding: .day, value: -ScreenshotSeed.planStartDaysAgo, to: today) ?? today,
                                ownerName: ScreenshotMode.demoName)
        let days = GroupSchedule.days(for: family, content: content)
        let week = GroupSchedule.week(days)
        let weekStart = week.start
        let weekTotal = max(week.days.flatMap(\.chapterIDs).count, 1)
        let throughToday = week.days.filter { $0.date <= today }.flatMap(\.chapterIDs).count
        let beforeToday = week.days.filter { $0.date < today }.flatMap(\.chapterIDs).count
        let todayChapters = days.first { $0.date == today }?.chapterIDs ?? []

        func member(_ id: String, _ name: String, _ initials: String, read: Int, doneToday: Bool, chapters: Int, streak: Int) -> Member {
            Member(userID: id, name: name, initials: initials, weekStart: weekStart, weekRead: min(max(read, 0), weekTotal),
                   weekTotal: weekTotal, lastDoneDay: doneToday ? today : yesterday, chaptersRead: chapters, streak: streak)
        }
        family.members = [
            member("screenshots-david", "David Jensen", "DJ", read: throughToday, doneToday: true, chapters: 134, streak: 51),
            member("screenshots-lily", "Lily Jensen", "LJ", read: throughToday, doneToday: true, chapters: 131, streak: 23),
            member("screenshots-ben", "Ben Jensen", "BJ", read: beforeToday - 2, doneToday: false, chapters: 118, streak: 0),
        ]
        family.items = [
            SharedItem(id: "screenshots-reflection", kind: .reflection, chapterID: todayChapters.first ?? "", startVerse: 0, endVerse: 0,
                       text: PlanFormat.range(todayChapters),
                       note: "I love that Amulek tells us to pray over our crops and our flocks. Nothing is too ordinary to pray about.",
                       authorID: "screenshots-lily", authorName: "Lily Jensen", createdAt: now.addingTimeInterval(-25 * 60)),
            SharedItem(id: "screenshots-highlight-1", kind: .highlight, chapterID: "bofm.alma.34", startVerse: 32, endVerse: 32,
                       text: verse("bofm.alma.34", 32), note: "This life is the time. Not someday.",
                       authorID: "screenshots-david", authorName: "David Jensen", createdAt: now.addingTimeInterval(-3 * 3600)),
            SharedItem(id: "screenshots-highlight-2", kind: .highlight, chapterID: "bofm.alma.32", startVerse: 21, endVerse: 21,
                       text: verse("bofm.alma.32", 21), note: "",
                       authorID: ScreenshotMode.demoUserID, authorName: ScreenshotMode.demoName,
                       createdAt: yesterday.addingTimeInterval(20 * 3600)),
        ]
        family.reactions = [
            Reaction(recordName: "screenshots-r1", itemID: "screenshots-reflection", kind: .heart, authorID: ScreenshotMode.demoUserID),
            Reaction(recordName: "screenshots-r2", itemID: "screenshots-reflection", kind: .heart, authorID: "screenshots-david"),
            Reaction(recordName: "screenshots-r3", itemID: "screenshots-highlight-1", kind: .insight, authorID: "screenshots-lily"),
            Reaction(recordName: "screenshots-r4", itemID: "screenshots-highlight-1", kind: .heart, authorID: ScreenshotMode.demoUserID),
            Reaction(recordName: "screenshots-r5", itemID: "screenshots-highlight-2", kind: .heart, authorID: "screenshots-lily"),
        ]

        var club = StudyGroup(zoneID: Self.demoClubZone, isOwner: false, name: "Maple Grove Book Club", symbol: "book.closed.fill",
                              planID: "nt-180", startDate: calendar.date(byAdding: .day, value: -30, to: today) ?? today,
                              ownerName: "Mark Reyes")
        club.members = [
            member("screenshots-mark", "Mark Reyes", "MR", read: 5, doneToday: true, chapters: 41, streak: 30),
            member("screenshots-ana", "Ana Reyes", "AR", read: 5, doneToday: true, chapters: 40, streak: 12),
            member("screenshots-tom", "Tom Okafor", "TO", read: 4, doneToday: false, chapters: 36, streak: 0),
            member(ScreenshotMode.demoUserID, ScreenshotMode.demoName, "SJ", read: 5, doneToday: true, chapters: 39, streak: 51),
            member("screenshots-grace", "Grace Lin", "GL", read: 3, doneToday: false, chapters: 33, streak: 0),
        ]

        groups = [family, club]
        hasLoaded = true
    }
}
