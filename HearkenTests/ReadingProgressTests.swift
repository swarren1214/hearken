import Foundation
import SwiftData
import Testing
@testable import Hearken

@MainActor
struct ReadingProgressTests {
    private func container() throws -> ModelContainer {
        let schema = Schema([ReadingProgress.self, XPEvent.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @Test func togglingReadStatusPreservesPositionAndAwardsXPOnlyOnce() throws {
        let container = try container()
        let context = ModelContext(container)
        let progress = ReadingProgress(chapterID: "bofm.alma.32", lastVerse: 27)
        context.insert(progress)
        let mastery = MasteryService()
        let first = Date(timeIntervalSince1970: 1_000)
        let second = Date(timeIntervalSince1970: 2_000)
        let third = Date(timeIntervalSince1970: 3_000)

        mastery.setChapterRead(true, progress: progress, in: context, now: first)
        #expect(progress.completedAt == first)
        #expect(progress.updatedAt == first)
        #expect(progress.hasEarnedReadXP)
        #expect(MasterySnapshot(reviews: [], progress: [progress]).completedChapters.contains(progress.chapterID))

        mastery.setChapterRead(true, progress: progress, in: context, now: second)
        #expect(progress.completedAt == first)
        mastery.setChapterRead(false, progress: progress, in: context, now: second)
        #expect(progress.completedAt == nil)
        #expect(progress.updatedAt == second)
        #expect(progress.lastVerse == 27)
        #expect(!MasterySnapshot(reviews: [], progress: [progress]).completedChapters.contains(progress.chapterID))

        try context.save()
        let reloadedContext = ModelContext(container)
        let reloaded = try #require(reloadedContext.fetch(FetchDescriptor<ReadingProgress>()).first)
        #expect(reloaded.completedAt == nil)
        #expect(reloaded.hasEarnedReadXP)
        #expect(reloaded.lastVerse == 27)
        mastery.setChapterRead(true, progress: reloaded, in: reloadedContext, now: third)
        try reloadedContext.save()
        #expect(reloaded.completedAt == third)
        let events = try reloadedContext.fetch(FetchDescriptor<XPEvent>())
        #expect(events.count == 1)
        #expect(events.first?.amount == MasteryConfig.standard.chapterReadXP)
        #expect(events.first?.reason == "chapter")
        #expect(events.first?.createdAt == first)
    }

    @Test func previouslyCompletedChaptersDoNotEarnDuplicateXP() throws {
        let container = try container()
        let context = ModelContext(container)
        let progress = ReadingProgress(chapterID: "ot.ps.23", lastVerse: 6)
        progress.completedAt = Date(timeIntervalSince1970: 1_000)
        context.insert(progress)
        context.insert(XPEvent(amount: MasteryConfig.standard.chapterReadXP, reason: "chapter"))
        let mastery = MasteryService()

        mastery.setChapterRead(false, progress: progress, in: context)
        #expect(progress.hasEarnedReadXP)
        #expect(progress.completedAt == nil)
        mastery.setChapterRead(true, progress: progress, in: context)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<XPEvent>()).count == 1)
    }

    @Test func leavingAnUnreadChapterUnreadDoesNotAwardXP() throws {
        let container = try container()
        let context = ModelContext(container)
        let progress = ReadingProgress(chapterID: "ot.ps.23")
        context.insert(progress)
        let updatedAt = progress.updatedAt

        MasteryService().setChapterRead(false, progress: progress, in: context)
        #expect(progress.completedAt == nil)
        #expect(progress.updatedAt == updatedAt)
        #expect(!progress.hasEarnedReadXP)
        #expect(try context.fetch(FetchDescriptor<XPEvent>()).isEmpty)
    }
}
