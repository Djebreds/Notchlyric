import Testing
import Foundation
@testable import NotchLyricsCore

private func tempDir() -> URL {
    let u = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("notchlyrics-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

private let sampleDoc = LyricsDocument(trackID: "t1", providerID: "lrclib", lines: [
    LyricLine(start: 1, end: 2, words: [WordToken(text: "hi", start: 1, end: 2, isEstimated: true)])
])

@Test func returnsNilForUnknownTrack() async {
    let c = LyricsCache(directory: tempDir())
    #expect(await c.load(trackID: "nope") == nil)
}

@Test func roundTripsADocument() async {
    let c = LyricsCache(directory: tempDir())
    await c.store(trackID: "t1", document: sampleDoc)
    guard case .found(let d)? = await c.load(trackID: "t1") else {
        Issue.record("expected a cached document"); return
    }
    #expect(d == sampleDoc)
}

@Test func recordsNegativeResults() async {
    let c = LyricsCache(directory: tempDir())
    await c.store(trackID: "t2", document: nil)
    guard case .knownMissing? = await c.load(trackID: "t2") else {
        Issue.record("expected a negative cache hit"); return
    }
}

@Test func negativeEntriesExpire() async {
    let c = LyricsCache(directory: tempDir(), negativeTTL: -1)
    await c.store(trackID: "t3", document: nil)
    #expect(await c.load(trackID: "t3") == nil)
}

@Test func positiveEntriesDoNotExpire() async {
    let c = LyricsCache(directory: tempDir(), negativeTTL: -1)
    await c.store(trackID: "t4", document: sampleDoc)
    #expect(await c.load(trackID: "t4") != nil)
}

@Test func sanitizesTrackIDIntoASafeFilename() async {
    let dir = tempDir()
    let c = LyricsCache(directory: dir)
    await c.store(trackID: "spotify:track:3BJe/4B8z", document: sampleDoc)
    let files = try! FileManager.default.contentsOfDirectory(atPath: dir.path)
    #expect(files.count == 1)
    #expect(files[0].contains("/") == false)
    #expect(await c.load(trackID: "spotify:track:3BJe/4B8z") != nil)
}

@Test func survivesCorruptedFile() async {
    let dir = tempDir()
    let c = LyricsCache(directory: dir)
    await c.store(trackID: "t5", document: sampleDoc)
    let f = try! FileManager.default.contentsOfDirectory(atPath: dir.path)[0]
    try! Data("garbage".utf8).write(to: dir.appendingPathComponent(f))
    #expect(await c.load(trackID: "t5") == nil)
}

@Test func rejectsEntriesWrittenByAnOlderSchema() async {
    let dir = tempDir()
    let c = LyricsCache(directory: dir)
    await c.store(trackID: "t6", document: sampleDoc)
    #expect(await c.load(trackID: "t6") != nil)

    // Simulate an entry written before word timings changed.
    let file = dir.appendingPathComponent(try! FileManager.default.contentsOfDirectory(atPath: dir.path)[0])
    var raw = try! JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
    raw["version"] = LyricsCache.schemaVersion - 1
    try! JSONSerialization.data(withJSONObject: raw).write(to: file)

    #expect(await c.load(trackID: "t6") == nil)
}

@Test func treatsEntriesWithNoVersionAsStale() async {
    let dir = tempDir()
    let c = LyricsCache(directory: dir)
    await c.store(trackID: "t7", document: sampleDoc)
    let file = dir.appendingPathComponent(try! FileManager.default.contentsOfDirectory(atPath: dir.path)[0])
    var raw = try! JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
    raw.removeValue(forKey: "version")
    try! JSONSerialization.data(withJSONObject: raw).write(to: file)

    #expect(await c.load(trackID: "t7") == nil)
}
