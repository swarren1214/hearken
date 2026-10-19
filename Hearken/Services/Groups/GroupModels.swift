import Foundation

/// Study group data as the Hearth API sends it (`/v1/hearken/*`). Plain values: the views read
/// them from `GroupStore`, which owns every change.
extension GroupStore {
    nonisolated enum Role: String, Codable, Sendable {
        case owner, leader, member

        var title: String {
            switch self {
            case .owner: "Owner"
            case .leader: "Leader"
            case .member: "Member"
            }
        }
    }

    nonisolated struct StudyGroup: Identifiable, Hashable, Sendable, Decodable {
        let id: String
        var name: String
        var symbol: String
        var planID: String
        /// Custom plans travel with the group, since members don't have them.
        var customPlan: CustomPlan?
        var startDate: Date
        var ownerID: String
        var ownerName: String
        /// My role in this group.
        var role: Role
        var inviteCode: String
        var inviteURL: URL?
        var members: [Member]
        var items: [SharedItem]
        var question: Question?
        /// A question scheduled for later (owners and leaders only).
        var scheduledQuestion: Question?
        var notifications: NotifyPrefs

        var isOwner: Bool { role == .owner }
        /// Owners and leaders post the weekly question and can remove posts and members.
        var canModerate: Bool { role != .member }
        /// What to send people: the invite link.
        var shareURL: URL? { inviteURL }

        nonisolated enum CodingKeys: String, CodingKey {
            case id, name, symbol, planId, customPlan, startDate, ownerId, ownerName, role, inviteCode, inviteURL
            case members, items, question, scheduledQuestion, notifications
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(String.self, forKey: .id)
            name = try values.decode(String.self, forKey: .name)
            symbol = try values.decode(String.self, forKey: .symbol)
            planID = try values.decode(String.self, forKey: .planId)
            customPlan = try? values.decodeIfPresent(CustomPlan.self, forKey: .customPlan)
            startDate = try GroupCoding.day(values.decode(String.self, forKey: .startDate)) ?? .now
            ownerID = try values.decode(String.self, forKey: .ownerId)
            ownerName = try values.decodeIfPresent(String.self, forKey: .ownerName) ?? ""
            role = try values.decodeIfPresent(Role.self, forKey: .role) ?? .member
            inviteCode = try values.decodeIfPresent(String.self, forKey: .inviteCode) ?? ""
            inviteURL = try values.decodeIfPresent(String.self, forKey: .inviteURL).flatMap(URL.init(string:))
            members = try values.decodeIfPresent([Member].self, forKey: .members) ?? []
            items = try values.decodeIfPresent([SharedItem].self, forKey: .items) ?? []
            question = try values.decodeIfPresent(Question.self, forKey: .question)
            scheduledQuestion = try values.decodeIfPresent(Question.self, forKey: .scheduledQuestion)
            notifications = try values.decodeIfPresent(NotifyPrefs.self, forKey: .notifications) ?? NotifyPrefs()
        }

        init(id: String, name: String, symbol: String, planID: String, customPlan: CustomPlan? = nil, startDate: Date,
             ownerID: String, ownerName: String, role: Role, inviteCode: String = "", inviteURL: URL? = nil,
             members: [Member] = [], items: [SharedItem] = [], question: Question? = nil, scheduledQuestion: Question? = nil,
             notifications: NotifyPrefs = NotifyPrefs()) {
            self.id = id
            self.name = name
            self.symbol = symbol
            self.planID = planID
            self.customPlan = customPlan
            self.startDate = startDate
            self.ownerID = ownerID
            self.ownerName = ownerName
            self.role = role
            self.inviteCode = inviteCode
            self.inviteURL = inviteURL
            self.members = members
            self.items = items
            self.question = question
            self.scheduledQuestion = scheduledQuestion
            self.notifications = notifications
        }
    }

    nonisolated struct CustomPlan: Codable, Hashable, Sendable {
        var title: String
        var chapterIDs: [String]
        var days: Int
    }

    /// One member's progress, written by that member only.
    nonisolated struct Member: Identifiable, Hashable, Sendable, Decodable {
        let userID: String
        var name: String
        var initials: String
        var role: Role
        /// Still on the iCloud version of Hearken: hasn't moved to the new study groups yet.
        var pending: Bool
        /// Start of the week the counts below are for.
        var weekStart: Date?
        var weekRead: Int
        var weekTotal: Int
        /// The day this member last finished the group's assignment.
        var lastDoneDay: Date?
        var chaptersRead: Int
        var streak: Int
        var id: String { userID }

        nonisolated private struct ProgressBody: Decodable {
            let weekStart: String?
            let weekRead: Int
            let weekTotal: Int
            let lastDoneDay: String?
            let chaptersRead: Int
            let streak: Int
        }

        nonisolated enum CodingKeys: String, CodingKey { case userId, name, initials, role, pending, progress }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            userID = try values.decode(String.self, forKey: .userId)
            name = try values.decode(String.self, forKey: .name)
            initials = try values.decodeIfPresent(String.self, forKey: .initials) ?? ""
            role = try values.decodeIfPresent(Role.self, forKey: .role) ?? .member
            pending = try values.decodeIfPresent(Bool.self, forKey: .pending) ?? false
            let progress = try values.decodeIfPresent(ProgressBody.self, forKey: .progress)
            weekStart = progress?.weekStart.flatMap(GroupCoding.day)
            weekRead = progress?.weekRead ?? 0
            weekTotal = progress?.weekTotal ?? 0
            lastDoneDay = progress?.lastDoneDay.flatMap(GroupCoding.day)
            chaptersRead = progress?.chaptersRead ?? 0
            streak = progress?.streak ?? 0
        }

        init(userID: String, name: String, initials: String, role: Role = .member, pending: Bool = false, weekStart: Date?,
             weekRead: Int, weekTotal: Int, lastDoneDay: Date?, chaptersRead: Int, streak: Int) {
            self.userID = userID
            self.name = name
            self.initials = initials
            self.role = role
            self.pending = pending
            self.weekStart = weekStart
            self.weekRead = weekRead
            self.weekTotal = weekTotal
            self.lastDoneDay = lastDoneDay
            self.chaptersRead = chaptersRead
            self.streak = streak
        }

        var doneToday: Bool { lastDoneDay.map(Calendar.current.isDateInToday) ?? false }
        var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }
    }

    nonisolated struct Reaction: Hashable, Sendable, Decodable {
        nonisolated enum Kind: String, CaseIterable, Codable, Sendable { case heart, insight }
        let kind: Kind
        let userID: String

        nonisolated enum CodingKeys: String, CodingKey { case kind, userId }

        init(kind: Kind, userID: String) {
            self.kind = kind
            self.userID = userID
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            kind = try values.decode(Kind.self, forKey: .kind)
            userID = try values.decode(String.self, forKey: .userId)
        }
    }

    nonisolated enum TargetType: String, Codable, Sendable { case item, comment, answer }

    nonisolated struct SharedItem: Identifiable, Hashable, Sendable, Decodable {
        nonisolated enum Kind: String, Codable, Sendable { case highlight, reflection }
        let id: String
        let kind: Kind
        let chapterID: String
        let startVerse: Int
        let endVerse: Int
        /// The scripture text (highlights), or the chapter range a reflection is on.
        let text: String
        /// What the member wrote (reflections, or a thought on a highlight).
        let note: String
        let reference: String
        let authorID: String
        let authorName: String
        let createdAt: Date
        var reactions: [Reaction]
        var commentCount: Int
        var latestComment: Comment?

        nonisolated enum CodingKeys: String, CodingKey {
            case id, kind, chapterId, startVerse, endVerse, text, note, reference, authorId, authorName, createdAt
            case reactions, commentCount, latestComment
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(String.self, forKey: .id)
            kind = try values.decode(Kind.self, forKey: .kind)
            chapterID = try values.decodeIfPresent(String.self, forKey: .chapterId) ?? ""
            startVerse = try values.decodeIfPresent(Int.self, forKey: .startVerse) ?? 0
            endVerse = try values.decodeIfPresent(Int.self, forKey: .endVerse) ?? 0
            text = try values.decodeIfPresent(String.self, forKey: .text) ?? ""
            note = try values.decodeIfPresent(String.self, forKey: .note) ?? ""
            reference = try values.decodeIfPresent(String.self, forKey: .reference) ?? ""
            authorID = try values.decode(String.self, forKey: .authorId)
            authorName = try values.decode(String.self, forKey: .authorName)
            createdAt = try values.decode(Date.self, forKey: .createdAt)
            reactions = try values.decodeIfPresent([Reaction].self, forKey: .reactions) ?? []
            commentCount = try values.decodeIfPresent(Int.self, forKey: .commentCount) ?? 0
            latestComment = try values.decodeIfPresent(Comment.self, forKey: .latestComment)
        }

        init(id: String, kind: Kind, chapterID: String, startVerse: Int, endVerse: Int, text: String, note: String,
             reference: String = "", authorID: String, authorName: String, createdAt: Date, reactions: [Reaction] = [],
             commentCount: Int = 0, latestComment: Comment? = nil) {
            self.id = id
            self.kind = kind
            self.chapterID = chapterID
            self.startVerse = startVerse
            self.endVerse = endVerse
            self.text = text
            self.note = note
            self.reference = reference
            self.authorID = authorID
            self.authorName = authorName
            self.createdAt = createdAt
            self.reactions = reactions
            self.commentCount = commentCount
            self.latestComment = latestComment
        }
    }

    /// A reply on a shared item or an answer. Replies go two levels deep: `parentID` is always
    /// a top-level reply.
    nonisolated struct Comment: Identifiable, Hashable, Sendable, Decodable {
        let id: String
        let targetType: TargetType
        let targetID: String
        let parentID: String?
        let authorID: String
        let authorName: String
        let body: String
        let mentions: [String]
        let mentionsEveryone: Bool
        let createdAt: Date
        var reactions: [Reaction]

        nonisolated enum CodingKeys: String, CodingKey {
            case id, targetType, targetId, parentId, authorId, authorName, body, mentions, mentionsEveryone, createdAt, reactions
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(String.self, forKey: .id)
            targetType = try values.decode(TargetType.self, forKey: .targetType)
            targetID = try values.decode(String.self, forKey: .targetId)
            parentID = try values.decodeIfPresent(String.self, forKey: .parentId)
            authorID = try values.decode(String.self, forKey: .authorId)
            authorName = try values.decode(String.self, forKey: .authorName)
            body = try values.decode(String.self, forKey: .body)
            mentions = try values.decodeIfPresent([String].self, forKey: .mentions) ?? []
            mentionsEveryone = try values.decodeIfPresent(Bool.self, forKey: .mentionsEveryone) ?? false
            createdAt = try values.decode(Date.self, forKey: .createdAt)
            reactions = try values.decodeIfPresent([Reaction].self, forKey: .reactions) ?? []
        }

        init(id: String, targetType: TargetType, targetID: String, parentID: String?, authorID: String, authorName: String,
             body: String, mentions: [String] = [], mentionsEveryone: Bool = false, createdAt: Date, reactions: [Reaction] = []) {
            self.id = id
            self.targetType = targetType
            self.targetID = targetID
            self.parentID = parentID
            self.authorID = authorID
            self.authorName = authorName
            self.body = body
            self.mentions = mentions
            self.mentionsEveryone = mentionsEveryone
            self.createdAt = createdAt
            self.reactions = reactions
        }
    }

    nonisolated struct Answer: Identifiable, Hashable, Sendable, Decodable {
        let id: String
        let questionID: String
        let userID: String
        let authorName: String
        let body: String
        let createdAt: Date
        var reactions: [Reaction]
        var commentCount: Int

        nonisolated enum CodingKeys: String, CodingKey { case id, questionId, userId, authorName, body, createdAt, reactions, commentCount }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(String.self, forKey: .id)
            questionID = try values.decode(String.self, forKey: .questionId)
            userID = try values.decode(String.self, forKey: .userId)
            authorName = try values.decode(String.self, forKey: .authorName)
            body = try values.decode(String.self, forKey: .body)
            createdAt = try values.decode(Date.self, forKey: .createdAt)
            reactions = try values.decodeIfPresent([Reaction].self, forKey: .reactions) ?? []
            commentCount = try values.decodeIfPresent(Int.self, forKey: .commentCount) ?? 0
        }

        init(id: String, questionID: String, userID: String, authorName: String, body: String, createdAt: Date,
             reactions: [Reaction] = [], commentCount: Int = 0) {
            self.id = id
            self.questionID = questionID
            self.userID = userID
            self.authorName = authorName
            self.body = body
            self.createdAt = createdAt
            self.reactions = reactions
            self.commentCount = commentCount
        }
    }

    /// The weekly question. Answers stay hidden until you answer (when `hideAnswers`), or until
    /// the question closes.
    nonisolated struct Question: Identifiable, Hashable, Sendable, Decodable {
        let id: String
        var text: String
        var reference: String
        var chapterID: String
        let authorID: String
        let authorName: String
        let postAt: Date
        let closesAt: Date
        var hideAnswers: Bool
        var isPosted: Bool
        var isClosed: Bool
        var answerCount: Int
        var answeredUserIDs: [String]
        var answersVisible: Bool
        var myAnswer: Answer?
        var answers: [Answer]

        nonisolated enum CodingKeys: String, CodingKey {
            case id, text, reference, chapterId, authorId, authorName, postAt, closesAt, hideAnswers, isPosted, isClosed
            case answerCount, answeredUserIds, answersVisible, myAnswer, answers
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(String.self, forKey: .id)
            text = try values.decode(String.self, forKey: .text)
            reference = try values.decodeIfPresent(String.self, forKey: .reference) ?? ""
            chapterID = try values.decodeIfPresent(String.self, forKey: .chapterId) ?? ""
            authorID = try values.decode(String.self, forKey: .authorId)
            authorName = try values.decode(String.self, forKey: .authorName)
            postAt = try values.decode(Date.self, forKey: .postAt)
            closesAt = try values.decode(Date.self, forKey: .closesAt)
            hideAnswers = try values.decodeIfPresent(Bool.self, forKey: .hideAnswers) ?? true
            isPosted = try values.decodeIfPresent(Bool.self, forKey: .isPosted) ?? true
            isClosed = try values.decodeIfPresent(Bool.self, forKey: .isClosed) ?? false
            answerCount = try values.decodeIfPresent(Int.self, forKey: .answerCount) ?? 0
            answeredUserIDs = try values.decodeIfPresent([String].self, forKey: .answeredUserIds) ?? []
            answersVisible = try values.decodeIfPresent(Bool.self, forKey: .answersVisible) ?? false
            myAnswer = try values.decodeIfPresent(Answer.self, forKey: .myAnswer)
            answers = try values.decodeIfPresent([Answer].self, forKey: .answers) ?? []
        }

        init(id: String, text: String, reference: String, chapterID: String, authorID: String, authorName: String,
             postAt: Date, closesAt: Date, hideAnswers: Bool, isPosted: Bool = true, isClosed: Bool = false,
             answerCount: Int, answeredUserIDs: [String], answersVisible: Bool, myAnswer: Answer?, answers: [Answer]) {
            self.id = id
            self.text = text
            self.reference = reference
            self.chapterID = chapterID
            self.authorID = authorID
            self.authorName = authorName
            self.postAt = postAt
            self.closesAt = closesAt
            self.hideAnswers = hideAnswers
            self.isPosted = isPosted
            self.isClosed = isClosed
            self.answerCount = answerCount
            self.answeredUserIDs = answeredUserIDs
            self.answersVisible = answersVisible
            self.myAnswer = myAnswer
            self.answers = answers
        }
    }

    /// What one group sends this person notifications about.
    nonisolated struct NotifyPrefs: Codable, Hashable, Sendable {
        var replies = true
        var mentions = true
        var allReplies = false
        var question = true
        var activity = true
    }

    /// What an invite code joins, shown before joining.
    nonisolated struct InvitePreview: Hashable, Sendable, Decodable {
        let groupId: String
        let name: String
        let symbol: String
        let planId: String
        let ownerName: String
        let memberCount: Int
        let isMember: Bool
    }

    /// My progress, as the group page shows it and other members see it.
    nonisolated struct Progress: Equatable, Sendable {
        var weekStart: Date
        var weekRead: Int
        var weekTotal: Int
        var doneToday: Bool
        var chaptersRead: Int
        var streak: Int
    }
}

/// JSON and date handling for the Hearth API.
nonisolated enum GroupCoding {
    nonisolated(unsafe) static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            guard let date = timestamp(value) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a timestamp: \(value)"))
            }
            return date
        }
        return decoder
    }()

    nonisolated(unsafe) static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(.iso8601))
        }
        return encoder
    }()

    /// RFC 3339, with or without fractional seconds.
    static func timestamp(_ value: String) -> Date? {
        if let date = try? Date(value, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return date }
        return try? Date(value, strategy: .iso8601)
    }

    /// A calendar day ("2026-10-19") as the start of that day here.
    static func day(_ value: String) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// The calendar day a date falls on here, as "2026-10-19".
    static func dayString(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }
}
