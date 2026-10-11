import Testing
@testable import Hearken

@MainActor
struct ContentServiceTests {
    @Test func searchFindsVerses() async {
        let content = ContentService()
        let hits = await content.search("faith is not to have a perfect knowledge", limit: 5)
        #expect(hits.contains { $0.chapterID == "bofm.alma.32" && $0.verse.number == 21 })
    }

    @Test func shortQueriesFindNothing() async {
        let content = ContentService()
        #expect(await content.search("a").isEmpty)
    }

    @Test func preloadLoadsEveryVolume() async {
        let content = ContentService()
        await content.preloadVolumes()
        #expect(content.chapter("ot.gen.1") != nil)
        #expect(content.chapter("pgp.moses.1") != nil)
        #expect(content.title(forChapter: "bofm.alma.32") == "Alma 32")
    }

    @Test func planWordCountsArePrecomputed() {
        let content = ContentService()
        #expect(PlanEngine.shared.words(in: "bofm.alma.32", content: content) == 1830)
    }
}
