import Testing
import Foundation
@testable import NotchLyricsCore

private actor Counter {
    private(set) var ids: [String] = []
    func bump(_ id: String) { ids.append(id) }
}

private struct FakeProvider: LyricsProvider {
    let id: String
    let result: LyricsDocument?
    var shouldThrow = false
    let calls: Counter

    func fetch(_ track: TrackQuery) async throws -> LyricsDocument? {
        await calls.bump(id)
        if shouldThrow { throw StubError() }
        return result
    }
}

private func tempCache() -> LyricsCache {
    let u = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("nl-svc-\(UUID().uuidString)")
    return LyricsCache(directory: u)
}

private func serviceDoc(_ provider: String) -> LyricsDocument {
    LyricsDocument(trackID: sampleQuery.trackID, providerID: provider, lines: [
        LyricLine(start: 0, end: 1, words: [WordToken(text: "x", start: 0, end: 1, isEstimated: true)])
    ])
}

@Test func returnsFirstProviderResult() async {
    let c = Counter()
    let svc = LyricsService(
        providers: [FakeProvider(id: "a", result: serviceDoc("a"), calls: c),
                    FakeProvider(id: "b", result: serviceDoc("b"), calls: c)],
        cache: tempCache())
    let out = await svc.lyrics(for: sampleQuery)
    #expect(out?.providerID == "a")
    #expect(await c.ids == ["a"])
}

@Test func fallsThroughWhenFirstReturnsNil() async {
    let c = Counter()
    let svc = LyricsService(
        providers: [FakeProvider(id: "a", result: nil, calls: c),
                    FakeProvider(id: "b", result: serviceDoc("b"), calls: c)],
        cache: tempCache())
    #expect(await svc.lyrics(for: sampleQuery)?.providerID == "b")
    #expect(await c.ids == ["a", "b"])
}

@Test func aThrowingProviderDoesNotBlockTheChain() async {
    let c = Counter()
    let svc = LyricsService(
        providers: [FakeProvider(id: "a", result: nil, shouldThrow: true, calls: c),
                    FakeProvider(id: "b", result: serviceDoc("b"), calls: c)],
        cache: tempCache())
    #expect(await svc.lyrics(for: sampleQuery)?.providerID == "b")
}

@Test func returnsNilWhenEveryProviderMisses() async {
    let c = Counter()
    let svc = LyricsService(providers: [FakeProvider(id: "a", result: nil, calls: c)],
                            cache: tempCache())
    #expect(await svc.lyrics(for: sampleQuery) == nil)
}

@Test func secondLookupIsServedFromCache() async {
    let c = Counter()
    let svc = LyricsService(providers: [FakeProvider(id: "a", result: serviceDoc("a"), calls: c)],
                            cache: tempCache())
    _ = await svc.lyrics(for: sampleQuery)
    _ = await svc.lyrics(for: sampleQuery)
    #expect(await c.ids == ["a"])
}

@Test func negativeResultIsCachedToo() async {
    let c = Counter()
    let svc = LyricsService(providers: [FakeProvider(id: "a", result: nil, calls: c)],
                            cache: tempCache())
    _ = await svc.lyrics(for: sampleQuery)
    _ = await svc.lyrics(for: sampleQuery)
    #expect(await c.ids == ["a"])
}

@Test func emptyProviderListReturnsNil() async {
    #expect(await LyricsService(providers: [], cache: tempCache()).lyrics(for: sampleQuery) == nil)
}
