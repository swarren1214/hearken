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
        guard AppConfig.cloudSyncEnabled, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            if myUserID == nil { myUserID = try await container.userRecordID().recordName }
            let owned = try await container.privateCloudDatabase.allRecordZones()
                .filter { $0.zoneID.zoneName.hasPrefix(Self.zonePrefix) }
            let joined = try await container.sharedCloudDatabase.allRecordZones()

            var loaded: [StudyGroup] = []
            for zone in owned {
                if let group = try? await load(zone.zoneID, from: container.privateCloudDatabase, isOwner: true) { loaded.append(group) }
            }
            for zone in joined {
                if let group = try? await load(zone.zoneID, from: container.sharedCloudDatabase, isOwner: false) { loaded.append(group) }
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

    /// Creates a group and its share. Returns the new group's ID.
    func create(name: String, symbol: String, plan: ReadingPlan, startDate: Date, ownerName: String) async throws -> String {
        let database = container.privateCloudDatabase
        let zone = CKRecordZone(zoneName: Self.zonePrefix + UUID().uuidString)
        _ = try await database.save(zone)

        let root = CKRecord(recordType: RecordType.group, recordID: CKRecord.ID(recordName: "group", zoneID: zone.zoneID))
        root["name"] = name
        root["symbol"] = symbol
        root["planID"] = plan.id
        if plan.isCustom {
            root["planTitle"] = plan.title
            root["chapterIDs"] = plan.chapterIDs
            root["days"] = plan.days
        }
        root["startDate"] = Calendar.current.startOfDay(for: startDate)
        root["ownerName"] = ownerName

        let share = CKShare(recordZoneID: zone.zoneID)
        share[CKShare.SystemFieldKey.title] = name
        // Anyone with the invite link can join; the owner can remove people.
        share.publicPermission = .readWrite

        let saved = try await database.modifyRecords(saving: [root, share], deleting: [])
        var shareURL: URL?
        if case .success(let record)? = saved.saveResults[share.recordID] { shareURL = (record as? CKShare)?.url }
        await refresh()
        if let index = groups.firstIndex(where: { $0.zoneID == zone.zoneID }), groups[index].shareURL == nil {
            groups[index].shareURL = shareURL
        }
        return groups.first { $0.zoneID == zone.zoneID }?.id ?? ""
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

    // MARK: Live updates

    /// Silent pushes when anything in the private or shared database changes.
    func ensureSubscriptions() async {
        let key = "groups.subscriptions.v1"
        guard AppConfig.cloudSyncEnabled, !UserDefaults.standard.bool(forKey: key) else { return }
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

    static func describe(_ error: Error) -> String {
        if let error = error as? CKError {
            switch error.code {
            case .notAuthenticated: return "Sign in to iCloud in Settings to use study groups."
            case .networkUnavailable, .networkFailure: return "You're offline. Groups will update when you're back online."
            case .quotaExceeded: return "The group owner's iCloud storage is full."
            default: break
            }
        }
        return "Study groups couldn't load right now."
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
