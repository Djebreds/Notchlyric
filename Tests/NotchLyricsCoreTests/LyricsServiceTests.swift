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

// MARK: - a failure must not be remembered as "this track has no lyrics"

@Test func aCleanMissIsCachedSoItIsNotRefetched() async {
    let c = Counter()
    let cache = tempCache()
    let svc = LyricsService(providers: [FakeProvider(id: "a", result: nil, calls: c)], cache: cache)
    _ = await svc.lyrics(for: sampleQuery)
    guard case .knownMissing? = await cache.load(trackID: sampleQuery.trackID) else {
        Issue.record("a genuine miss should be remembered"); return
    }
}

@Test func aProviderErrorIsNotCachedAsAMiss() async {
    // a network blip must not blank the track until the TTL expires
    let c = Counter()
    let cache = tempCache()
    let svc = LyricsService(
        providers: [FakeProvider(id: "a", result: nil, shouldThrow: true, calls: c)], cache: cache)
    #expect(await svc.lyrics(for: sampleQuery) == nil)
    #expect(await cache.load(trackID: sampleQuery.trackID) == nil,
            "an errored lookup must stay retryable")
}

@Test func anErrorAlongsideACleanMissStillBlocksCaching() async {
    let c = Counter()
    let cache = tempCache()
    let svc = LyricsService(providers: [
        FakeProvider(id: "a", result: nil, calls: c),
        FakeProvider(id: "b", result: nil, shouldThrow: true, calls: c),
    ], cache: cache)
    _ = await svc.lyrics(for: sampleQuery)
    #expect(await cache.load(trackID: sampleQuery.trackID) == nil)
}

@Test func erroredLookupsAreRetriedOnTheNextPlay() async {
    let c = Counter()
    let cache = tempCache()
    let svc = LyricsService(
        providers: [FakeProvider(id: "a", result: nil, shouldThrow: true, calls: c)], cache: cache)
    _ = await svc.lyrics(for: sampleQuery)
    _ = await svc.lyrics(for: sampleQuery)
    #expect(await c.ids == ["a", "a"], "should try again rather than serve a cached miss")
}

@Test func negativeResultsExpireQuickly() {
    // community lyrics get contributed; a miss must not stick for days
    #expect(LyricsCache.defaultNegativeTTL <= 3600)
}
