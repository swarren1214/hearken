import CloudKit
import Foundation
import OSLog

/// Moves study groups from CloudKit sharing (Hearken 1.x) to the Hearth API, without anyone
/// inviting anyone again.
///
/// - **Owner's device:** uploads the group (members, posts, reactions) to
///   `POST /v1/hearken/groups/import`, then writes the new group's id and a migration token into
///   the old zone's `StudyGroup` record (`movedTo`, `moveToken`).
/// - **Member's device:** finds `movedTo` in the shared zone and claims its seat with
///   `POST /v1/hearken/groups/claim`, which also hands back its posts and reactions.
/// - A shared zone whose owner hasn't updated yet shows as "waiting" in the Study Groups section.
///
/// The old zones stay, so members on older versions keep working, until a later release removes
/// this code and deletes them. `movedTo` and `moveToken` are new fields: run a Debug build once
/// (`GroupStore.initializeSchemaIfNeeded`) and deploy the schema before releasing.
@MainActor
enum GroupMigration {
    private static let log = Logger(subsystem: "com.stephenwarren.hearken", category: "groups-migration")
    private static let container = CKContainer(identifier: AppConfig.cloudKitContainerID)
    private static let zonePrefix = "group-"
    /// Zones already moved or claimed from this device.
    private static let doneKey = "groups.migration.doneZones"
    /// Set once nothing is left in CloudKit, so later launches skip the lookup.
    private static let finishedKey = "groups.migration.finished.v1"
    /// Checked at most this often while waiting on an owner.
    private static let lastCheckKey = "groups.migration.lastCheck"

    /// Looks again (an old invite was just accepted).
    static func reset() {
        UserDefaults.standard.removeObject(forKey: finishedKey)
        UserDefaults.standard.removeObject(forKey: lastCheckKey)
    }

    static func isLegacyNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
        CKNotification(fromRemoteNotificationDictionary: userInfo)?.subscriptionID?.hasPrefix("groups-") ?? false
    }

    /// Moves and claims what it can. Returns the groups still waiting on their owner.
    static func run(store: GroupStore) async -> [GroupStore.WaitingGroup] {
        guard AppConfig.cloudSyncEnabled, !ScreenshotMode.isOn, !UserDefaults.standard.bool(forKey: finishedKey) else { return [] }
        if let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date, Date.now.timeIntervalSince(last) < 15 * 60 {
            return cachedWaiting
        }
        guard (try? await container.accountStatus()) == .available else { return [] }
        UserDefaults.standard.set(Date.now, forKey: lastCheckKey)
        do {
            let me = try await container.userRecordID().recordName
            var done = Set(UserDefaults.standard.stringArray(forKey: doneKey) ?? [])
            var waiting: [GroupStore.WaitingGroup] = []
            var remaining = 0

            let owned = try await container.privateCloudDatabase.allRecordZones().filter { $0.zoneID.zoneName.hasPrefix(zonePrefix) }
            for zone in owned where !done.contains(key(zone.zoneID)) {
                remaining += 1
                do {
                    let records = try await records(in: zone.zoneID, database: container.privateCloudDatabase)
                    try await moveOwned(zone.zoneID, records: records, me: me, store: store)
                    done.insert(key(zone.zoneID))
                    remaining -= 1
                } catch {
                    log.error("moving an owned group failed: \(String(describing: error), privacy: .public)")
                }
            }

            let joined = try await container.sharedCloudDatabase.allRecordZones()
            for zone in joined where !done.contains(key(zone.zoneID)) {
                remaining += 1
                do {
                    let records = try await records(in: zone.zoneID, database: container.sharedCloudDatabase)
                    guard let root = records.first(where: { $0.recordType == "StudyGroup" }) else { continue }
                    if let token = root["moveToken"] as? String, !token.isEmpty {
                        try await claim(token: token, me: me, store: store)
                        done.insert(key(zone.zoneID))
                        remaining -= 1
                    } else {
                        waiting.append(GroupStore.WaitingGroup(
                            id: key(zone.zoneID),
                            name: root["name"] as? String ?? "Study Group",
                            ownerName: root["ownerName"] as? String ?? ""
                        ))
                    }
                } catch {
                    log.error("claiming a group failed: \(String(describing: error), privacy: .public)")
                }
            }

            UserDefaults.standard.set(Array(done), forKey: doneKey)
            if remaining == 0 { UserDefaults.standard.set(true, forKey: finishedKey) }
            cachedWaiting = waiting
            return waiting
        } catch {
            log.error("migration check failed: \(String(describing: error), privacy: .public)")
            return cachedWaiting
        }
    }

    /// Without a Hearth account: just the iCloud groups this person is in, for the sign-in card.
    static func waitingGroups() async -> [GroupStore.WaitingGroup] {
        guard AppConfig.cloudSyncEnabled, !ScreenshotMode.isOn, !UserDefaults.standard.bool(forKey: finishedKey),
              (try? await container.accountStatus()) == .available else { return [] }
        var result: [GroupStore.WaitingGroup] = []
        for database in [container.privateCloudDatabase, container.sharedCloudDatabase] {
            guard let zones = try? await database.allRecordZones() else { continue }
            for zone in zones where database.databaseScope == .shared || zone.zoneID.zoneName.hasPrefix(zonePrefix) {
                guard let record = try? await database.record(for: CKRecord.ID(recordName: "group", zoneID: zone.zoneID)) else { continue }
                result.append(GroupStore.WaitingGroup(id: key(zone.zoneID), name: record["name"] as? String ?? "Study Group",
                                                      ownerName: record["ownerName"] as? String ?? ""))
            }
        }
        return result
    }

    private static var cachedWaiting: [GroupStore.WaitingGroup] = []

    private static func key(_ zoneID: CKRecordZone.ID) -> String { zoneID.zoneName + "|" + zoneID.ownerName }

    private static func records(in zoneID: CKRecordZone.ID, database: CKDatabase) async throws -> [CKRecord] {
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
        return records
    }

    // MARK: Owner

    private nonisolated struct ImportProgress: Encodable {
        let weekStart: String?
        let weekRead: Int
        let weekTotal: Int
        let lastDoneDay: String?
        let chaptersRead: Int
        let streak: Int

        nonisolated enum CodingKeys: String, CodingKey { case weekStart, weekRead, weekTotal, lastDoneDay, chaptersRead, streak }

        /// The server needs `weekStart` and `lastDoneDay` present, as null when unknown.
        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(weekStart, forKey: .weekStart)
            try values.encode(weekRead, forKey: .weekRead)
            try values.encode(weekTotal, forKey: .weekTotal)
            try values.encode(lastDoneDay, forKey: .lastDoneDay)
            try values.encode(chaptersRead, forKey: .chaptersRead)
            try values.encode(streak, forKey: .streak)
        }
    }

    private nonisolated struct ImportMember: Encodable {
        let legacyId: String
        let displayName: String
        let initials: String
        let progress: ImportProgress?
    }

    private nonisolated struct ImportItem: Encodable {
        let legacyId: String
        let legacyAuthorId: String
        let authorName: String
        let kind: String
        let chapterId: String
        let startVerse: Int
        let endVerse: Int
        let text: String
        let note: String
        let createdAt: Date
    }

    private nonisolated struct ImportReaction: Encodable {
        let legacyItemId: String
        let legacyUserId: String
        let kind: String
    }

    private nonisolated struct ImportBody: Encodable {
        let clientId: String
        let name: String
        let symbol: String
        let planId: String
        let customPlan: GroupStore.CustomPlan?
        let startDate: String
        let displayName: String
        let initials: String
        let ownerLegacyId: String
        let progress: ImportProgress?
        let members: [ImportMember]
        let items: [ImportItem]
        let reactions: [ImportReaction]
    }

    private nonisolated struct ImportReply: Decodable {
        let migrationToken: String
        let group: Group
        nonisolated struct Group: Decodable { let id: String }
    }

    private static func moveOwned(_ zoneID: CKRecordZone.ID, records: [CKRecord], me: String, store: GroupStore) async throws {
        guard let root = records.first(where: { $0.recordType == "StudyGroup" }) else { return }
        if let token = root["moveToken"] as? String, !token.isEmpty { return }
        func clip(_ text: String, _ limit: Int) -> String { String(text.prefix(limit)) }
        func name(_ value: Any?) -> String { GroupStore.clean(value as? String ?? "") }
        func progress(_ record: CKRecord) -> ImportProgress {
            ImportProgress(
                weekStart: (record["weekStart"] as? Date).map(GroupCoding.dayString),
                weekRead: max(record["weekRead"] as? Int ?? 0, 0), weekTotal: max(record["weekTotal"] as? Int ?? 0, 0),
                lastDoneDay: (record["lastDoneDay"] as? Date).map(GroupCoding.dayString),
                chaptersRead: max(record["chaptersRead"] as? Int ?? 0, 0), streak: max(record["streak"] as? Int ?? 0, 0)
            )
        }
        let memberRecords = records.filter { $0.recordType == "GroupMember" }
        let mine = memberRecords.first { ($0["userID"] as? String) == me }
        let planID = root["planID"] as? String ?? ""
        let chapterIDs = root["chapterIDs"] as? [String] ?? []
        let body = ImportBody(
            clientId: zoneID.zoneName,
            name: clip(name(root["name"]), 60),
            symbol: root["symbol"] as? String ?? "person.3.fill",
            planId: planID.isEmpty ? "custom" : planID,
            customPlan: planID == ReadingPlan.customID
                ? GroupStore.CustomPlan(title: root["planTitle"] as? String ?? "Custom Plan", chapterIDs: chapterIDs, days: max(root["days"] as? Int ?? 1, 1))
                : nil,
            startDate: GroupCoding.dayString(root["startDate"] as? Date ?? .now),
            displayName: GroupStore.clean(store.profile.name),
            initials: store.profile.initials.isEmpty ? GroupStore.initials(store.profile.name) : String(store.profile.initials.prefix(3)),
            ownerLegacyId: me,
            progress: mine.map(progress),
            members: memberRecords.compactMap { record in
                guard let id = record["userID"] as? String, id != me else { return nil }
                let initials = (record["initials"] as? String).flatMap { $0.isEmpty ? nil : String($0.prefix(3)) }
                return ImportMember(legacyId: id, displayName: name(record["name"]),
                                    initials: initials ?? GroupStore.initials(name(record["name"])), progress: progress(record))
            },
            items: records.filter { $0.recordType == "SharedItem" }.compactMap { record in
                let kind = record["kind"] as? String ?? "reflection"
                let text = clip(record["text"] as? String ?? "", 4000)
                let note = clip(record["note"] as? String ?? "", 2000)
                // The API only takes something to show: a highlight's text, or a reflection's note.
                if kind == "highlight" ? text.isEmpty : note.isEmpty { return nil }
                return ImportItem(legacyId: record.recordID.recordName, legacyAuthorId: record["authorID"] as? String ?? me,
                                  authorName: name(record["authorName"]), kind: kind == "highlight" ? "highlight" : "reflection",
                                  chapterId: clip(record["chapterID"] as? String ?? "", 64),
                                  startVerse: min(max(record["startVerse"] as? Int ?? 0, 0), 1000),
                                  endVerse: min(max(record["endVerse"] as? Int ?? 0, 0), 1000),
                                  text: text, note: note, createdAt: record["createdAt"] as? Date ?? record.creationDate ?? .now)
            }.suffix(500).map { $0 },
            reactions: records.filter { $0.recordType == "Reaction" }.compactMap { record in
                guard let item = record["itemID"] as? String, let author = record["authorID"] as? String,
                      let kind = record["kind"] as? String, ["heart", "insight"].contains(kind) else { return nil }
                return ImportReaction(legacyItemId: item, legacyUserId: author, kind: kind)
            }.suffix(2000).map { $0 }
        )
        let data = try await HearthAPI.shared.data("POST", "/v1/hearken/groups/import", body: GroupCoding.encoder.encode(body))
        let reply = try GroupCoding.decoder.decode(ImportReply.self, from: data)
        root["movedTo"] = reply.group.id
        root["moveToken"] = reply.migrationToken
        // modifyRecords reports a failed record in its results rather than throwing.
        let saved = try await container.privateCloudDatabase.modifyRecords(saving: [root], deleting: [], savePolicy: .changedKeys)
        if case .failure(let error)? = saved.saveResults[root.recordID] { throw error }
        log.info("moved an owned group to the Hearth API")
    }

    // MARK: Member

    private nonisolated struct ClaimBody: Encodable {
        let migrationToken: String
        let legacyUserId: String
        let displayName: String
        let initials: String
    }

    private static func claim(token: String, me: String, store: GroupStore) async throws {
        let body = ClaimBody(migrationToken: token, legacyUserId: me, displayName: GroupStore.clean(store.profile.name),
                             initials: store.profile.initials.isEmpty ? GroupStore.initials(store.profile.name) : String(store.profile.initials.prefix(3)))
        do {
            _ = try await HearthAPI.shared.data("POST", "/v1/hearken/groups/claim", body: GroupCoding.encoder.encode(body))
            log.info("claimed a moved group")
        } catch let error as HearthAPI.APIError where error.status == 404 {
            // The group was deleted after it moved: nothing to claim.
        }
    }
}
