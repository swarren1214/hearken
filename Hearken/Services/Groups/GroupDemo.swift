import CloudKit
import Foundation
import OSLog

// MARK: - Screenshot mode

extension GroupStore {
    /// The family group, for the group screenshot.
    static let demoGroupID = "screenshots-family"
    private static let demoClubID = "screenshots-club"

    /// Demo groups for marketing screenshots (Debug, `-HearkenScreenshots`). Never the API.
    func loadDemo() {
        guard !hasLoaded || groups.isEmpty else { return }
        let content = ListenEngine.shared.scripture
        let calendar = Calendar.current
        let now = Date.now
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let me = ScreenshotMode.demoUserID
        demoSetUser(me)
        profile = (ScreenshotMode.demoName, "SJ")

        func verse(_ chapterID: String, _ number: Int) -> String {
            content.chapter(chapterID)?.verses.first { $0.number == number }?.text ?? ""
        }

        var family = StudyGroup(id: Self.demoGroupID, name: "Jensen Family", symbol: "house.fill", planID: "bofm-90",
                                startDate: calendar.date(byAdding: .day, value: -ScreenshotSeed.planStartDaysAgo, to: today) ?? today,
                                ownerID: me, ownerName: ScreenshotMode.demoName, role: .owner, inviteCode: "JNSN4FAM",
                                inviteURL: URL(string: "https://api.hearthapps.com/hearken/join/JNSN4FAM"))
        let days = GroupSchedule.days(for: family, content: content)
        let week = GroupSchedule.week(days)
        let weekStart = week.start
        let weekTotal = max(week.days.flatMap(\.chapterIDs).count, 1)
        let throughToday = week.days.filter { $0.date <= today }.flatMap(\.chapterIDs).count
        let beforeToday = week.days.filter { $0.date < today }.flatMap(\.chapterIDs).count
        let todayChapters = days.first { $0.date == today }?.chapterIDs ?? []

        func member(_ id: String, _ name: String, _ initials: String, role: Role = .member, read: Int, doneToday: Bool, chapters: Int, streak: Int) -> Member {
            Member(userID: id, name: name, initials: initials, role: role, weekStart: weekStart, weekRead: min(max(read, 0), weekTotal),
                   weekTotal: weekTotal, lastDoneDay: doneToday ? today : yesterday, chaptersRead: chapters, streak: streak)
        }
        family.members = [
            member("screenshots-david", "David Jensen", "DJ", role: .leader, read: throughToday, doneToday: true, chapters: 134, streak: 51),
            member("screenshots-lily", "Lily Jensen", "LJ", read: throughToday, doneToday: true, chapters: 131, streak: 23),
            member("screenshots-ben", "Ben Jensen", "BJ", read: beforeToday - 2, doneToday: false, chapters: 118, streak: 0),
        ]
        let latestReply = Comment(id: "screenshots-c1", targetType: .item, targetID: "screenshots-reflection", parentID: nil,
                                  authorID: "screenshots-david", authorName: "David Jensen",
                                  body: "Same. I've started praying before work meetings, even the boring ones.",
                                  createdAt: now.addingTimeInterval(-18 * 60))
        family.items = [
            SharedItem(id: "screenshots-reflection", kind: .reflection, chapterID: todayChapters.first ?? "bofm.alma.34", startVerse: 0, endVerse: 0,
                       text: PlanFormat.range(todayChapters.isEmpty ? ["bofm.alma.34"] : todayChapters),
                       note: "I love that Amulek tells us to pray over our crops and our flocks. Nothing is too ordinary to pray about.",
                       authorID: "screenshots-lily", authorName: "Lily Jensen", createdAt: now.addingTimeInterval(-25 * 60),
                       reactions: [Reaction(kind: .heart, userID: me), Reaction(kind: .heart, userID: "screenshots-david")],
                       commentCount: 3, latestComment: latestReply),
            SharedItem(id: "screenshots-highlight-1", kind: .highlight, chapterID: "bofm.alma.34", startVerse: 32, endVerse: 32,
                       text: verse("bofm.alma.34", 32), note: "This life is the time. Not someday.", reference: "Alma 34:32",
                       authorID: "screenshots-david", authorName: "David Jensen", createdAt: now.addingTimeInterval(-3 * 3600),
                       reactions: [Reaction(kind: .insight, userID: "screenshots-lily"), Reaction(kind: .heart, userID: me)]),
            SharedItem(id: "screenshots-highlight-2", kind: .highlight, chapterID: "bofm.alma.32", startVerse: 21, endVerse: 21,
                       text: verse("bofm.alma.32", 21), note: "", reference: "Alma 32:21",
                       authorID: me, authorName: ScreenshotMode.demoName, createdAt: yesterday.addingTimeInterval(20 * 3600),
                       reactions: [Reaction(kind: .heart, userID: "screenshots-lily")]),
        ]
        family.question = Question(
            id: "screenshots-question", text: "Alma compares the word to a seed. What's one seed you've planted this year, and how can you tell it's growing?",
            reference: "Alma 32:28–43", chapterID: "bofm.alma.32", authorID: "screenshots-david", authorName: "David Jensen",
            postAt: calendar.date(byAdding: .day, value: -2, to: now) ?? now, closesAt: calendar.date(byAdding: .day, value: 5, to: now) ?? now,
            hideAnswers: true, answerCount: 2, answeredUserIDs: ["screenshots-david", "screenshots-lily"], answersVisible: false,
            myAnswer: nil, answers: []
        )

        var club = StudyGroup(id: Self.demoClubID, name: "Maple Grove Book Club", symbol: "book.closed.fill", planID: "nt-180",
                              startDate: calendar.date(byAdding: .day, value: -30, to: today) ?? today,
                              ownerID: "screenshots-mark", ownerName: "Mark Reyes", role: .member)
        club.members = [
            member("screenshots-mark", "Mark Reyes", "MR", role: .owner, read: 5, doneToday: true, chapters: 41, streak: 30),
            member("screenshots-ana", "Ana Reyes", "AR", read: 5, doneToday: true, chapters: 40, streak: 12),
            member("screenshots-tom", "Tom Okafor", "TO", read: 4, doneToday: false, chapters: 36, streak: 0),
            member(me, ScreenshotMode.demoName, "SJ", read: 5, doneToday: true, chapters: 39, streak: 51),
            member("screenshots-grace", "Grace Lin", "GL", read: 3, doneToday: false, chapters: 33, streak: 0),
        ]

        demoSetGroups([family, club])
    }

    /// The demo thread under Lily's reflection.
    static func demoComments(target: String) -> [Comment] {
        let now = Date.now
        guard target == "screenshots-reflection" else { return [] }
        return [
            Comment(id: "screenshots-c1", targetType: .item, targetID: target, parentID: nil, authorID: "screenshots-david",
                    authorName: "David Jensen", body: "Same. I've started praying before work meetings, even the boring ones.",
                    createdAt: now.addingTimeInterval(-18 * 60), reactions: [Reaction(kind: .heart, userID: "screenshots-lily")]),
            Comment(id: "screenshots-c2", targetType: .item, targetID: target, parentID: "screenshots-c1", authorID: "screenshots-lily",
                    authorName: "Lily Jensen", body: "@David the boring ones need it most.", mentions: ["screenshots-david"],
                    createdAt: now.addingTimeInterval(-12 * 60),
                    reactions: [Reaction(kind: .heart, userID: ScreenshotMode.demoUserID), Reaction(kind: .heart, userID: "screenshots-david")]),
            Comment(id: "screenshots-c3", targetType: .item, targetID: target, parentID: nil, authorID: "screenshots-ben",
                    authorName: "Ben Jensen", body: "Verse 26 says to pour out our souls in our closets too. That one's harder for me.",
                    createdAt: now.addingTimeInterval(-4 * 60)),
        ]
    }

    /// Answering in screenshot mode reveals the demo answers.
    func revealDemoAnswers(_ text: String, groupID: String) {
        guard var group = group(groupID), var question = group.question else { return }
        let now = Date.now
        let mine = Answer(id: "screenshots-a-me", questionID: question.id, userID: ScreenshotMode.demoUserID,
                          authorName: ScreenshotMode.demoName, body: text, createdAt: now)
        question.answers = [
            mine,
            Answer(id: "screenshots-a-david", questionID: question.id, userID: "screenshots-david", authorName: "David Jensen",
                   body: "Saying no to my phone for the first hour of the day. I notice I'm less short with everyone by dinner.",
                   createdAt: now.addingTimeInterval(-2 * 86_400), reactions: [Reaction(kind: .heart, userID: "screenshots-lily")], commentCount: 1),
            Answer(id: "screenshots-a-lily", questionID: question.id, userID: "screenshots-lily", authorName: "Lily Jensen",
                   body: "Writing one thing I'm grateful for each night. Some nights it takes a minute to think of one, and that's the good part.",
                   createdAt: now.addingTimeInterval(-86_400)),
        ]
        question.myAnswer = mine
        question.answersVisible = true
        question.answerCount = 3
        question.answeredUserIDs.append(ScreenshotMode.demoUserID)
        group.question = question
        demoSetGroups(groups.map { $0.id == groupID ? group : $0 })
    }
}

// MARK: - CloudKit schema (Debug)

extension GroupStore {
    #if DEBUG
    /// Bump when a CloudKit group record gains a field, so the next debug run pushes it.
    /// 2: `movedTo` and `moveToken` on StudyGroup (the move to the Hearth API).
    private static let schemaVersion = 2

    /// Debug builds only. Saves one record of each old CloudKit group type, every field filled
    /// in, to a throwaway zone in the development database, then deletes the zone. CloudKit only
    /// learns a field when a record first uses it, and production refuses new ones, so this
    /// readies the schema for Deploy Schema Changes. Kept until every group has moved.
    func initializeSchemaIfNeeded() async {
        let key = "cloudkit.groupSchemaInitialized"
        guard UserDefaults.standard.integer(forKey: key) < Self.schemaVersion else { return }
        let container = CKContainer(identifier: AppConfig.cloudKitContainerID)
        let database = container.privateCloudDatabase
        let zone = CKRecordZone(zoneName: "schema-setup-\(UUID().uuidString)")
        func record(_ type: String) -> CKRecord {
            CKRecord(recordType: type, recordID: CKRecord.ID(recordName: type, zoneID: zone.zoneID))
        }
        let group = record("StudyGroup")
        group["name"] = "Schema setup"
        group["symbol"] = "person.3"
        group["planID"] = "schema"
        group["planTitle"] = "Schema setup"
        group["chapterIDs"] = ["schema"]
        group["days"] = 1
        group["startDate"] = Date.now
        group["ownerName"] = "Schema"
        group["movedTo"] = "schema"
        group["moveToken"] = "schema"
        let member = record("GroupMember")
        member["userID"] = "schema"
        member["name"] = "Schema"
        member["initials"] = "S"
        member["weekStart"] = Date.now
        member["weekRead"] = 0
        member["weekTotal"] = 0
        member["chaptersRead"] = 0
        member["streak"] = 0
        member["lastDoneDay"] = Date.now
        let item = record("SharedItem")
        item["kind"] = "highlight"
        item["chapterID"] = "schema"
        item["startVerse"] = 1
        item["endVerse"] = 1
        item["text"] = "Schema"
        item["note"] = "Schema"
        item["authorID"] = "schema"
        item["authorName"] = "Schema"
        item["createdAt"] = Date.now
        let reaction = record("Reaction")
        reaction["itemID"] = "schema"
        reaction["kind"] = "heart"
        reaction["authorID"] = "schema"
        let log = Logger(subsystem: "com.stephenwarren.hearken", category: "groups")
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
}
