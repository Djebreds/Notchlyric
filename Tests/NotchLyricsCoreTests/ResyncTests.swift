import Testing
import Foundation
@testable import NotchLyricsCore

private let r0 = ContinuousClock.now

private func tempCache() -> LyricsCache {
    LyricsCache(directory: URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("nl-resync-\(UUID().uuidString)"))
}

private actor Hits {
    private(set) var n = 0
    func bump() { n += 1 }
}

private struct CountingProvider: LyricsProvider {
    let id = "counting"
    let hits: Hits
    func fetch(_ track: TrackQuery) async throws -> LyricsDocument? {
        await hits.bump()
        return LyricsDocument(trackID: track.trackID, providerID: id, lines: [
            LyricLine(start: 0, end: 1,
                      words: [WordToken(text: "x", start: 0, end: 1, isEstimated: true)])
        ])
    }
}

// MARK: - clock reset

@Test func resetClearsTheSample() {
    var c = PlaybackClock()
    c.ingest(position: 30, at: r0, isPlaying: true)
    #expect(c.hasSample)
    c.reset()
    #expect(c.hasSample == false)
    #expect(c.position(at: r0) == 0)
}

@Test func afterResetTheNextSampleAnchorsWithoutReportingASeek() {
    var c = PlaybackClock()
    c.ingest(position: 30, at: r0, isPlaying: true)
    c.reset()
    c.ingest(position: 90, at: r0.advanced(by: .seconds(1)), isPlaying: true)
    #expect(c.didSeek == false, "a fresh anchor is not a seek")
    #expect(abs(c.position(at: r0.advanced(by: .seconds(1))) - 90) < 0.01)
}

@Test func resetDiscardsAnInFlightCorrection() {
    var c = PlaybackClock()
    c.ingest(position: 10, at: r0, isPlaying: true)
    c.ingest(position: 11.1, at: r0.advanced(by: .seconds(1)), isPlaying: true)
    c.reset()
    c.ingest(position: 50, at: r0.advanced(by: .seconds(2)), isPlaying: true)
    #expect(abs(c.position(at: r0.advanced(by: .seconds(2))) - 50) < 0.01)
}

// MARK: - cache invalidation

@Test func removeDropsASingleEntry() async {
    let c = tempCache()
    let doc = LyricsDocument(trackID: "t1", providerID: "p", lines: [
        LyricLine(start: 0, end: 1, words: [WordToken(text: "x", start: 0, end: 1, isEstimated: true)])
    ])
    await c.store(trackID: "t1", document: doc)
    await c.store(trackID: "t2", document: doc)
    await c.remove(trackID: "t1")
    #expect(await c.load(trackID: "t1") == nil)
    #expect(await c.load(trackID: "t2") != nil, "other tracks must be untouched")
}

@Test func removingAnAbsentEntryIsHarmless() async {
    let c = tempCache()
    await c.remove(trackID: "nope")
    #expect(await c.load(trackID: "nope") == nil)
}

// MARK: - forced refetch

@Test func normalLookupUsesTheCache() async {
    let h = Hits()
    let svc = LyricsService(providers: [CountingProvider(hits: h)], cache: tempCache())
    _ = await svc.lyrics(for: sampleQuery)
    _ = await svc.lyrics(for: sampleQuery)
    #expect(await h.n == 1)
}

@Test func refreshBypassesTheCacheAndRefetches() async {
    let h = Hits()
    let svc = LyricsService(providers: [CountingProvider(hits: h)], cache: tempCache())
    _ = await svc.lyrics(for: sampleQuery)
    _ = await svc.lyrics(for: sampleQuery, refresh: true)
    #expect(await h.n == 2, "a re-sync must ask the providers again")
}

@Test func refreshReplacesAPreviouslyCachedMiss() async {
    let h = Hits()
    let cache = tempCache()
    await cache.store(trackID: sampleQuery.trackID, document: nil)   // remembered miss
    let svc = LyricsService(providers: [CountingProvider(hits: h)], cache: cache)
    #expect(await svc.lyrics(for: sampleQuery) == nil, "the miss is served from cache")
    let fresh = await svc.lyrics(for: sampleQuery, refresh: true)
    #expect(fresh != nil, "re-sync must get past a remembered miss")
    #expect(await h.n == 1)
}
