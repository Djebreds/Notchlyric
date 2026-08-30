import Testing
import Foundation
@testable import NotchLyricsCore

/// Shape recorded from a live lrclib.net response (spec §1.5).
private let lrclibHit = """
{"id":15939,"trackName":"Summertime Sadness","artistName":"Lana Del Rey",
 "albumName":"Born To Die","duration":265.0,"instrumental":false,
 "plainLyrics":"Kiss me hard before you go",
 "syncedLyrics":"[00:17.38] Kiss me hard before you go\\n[00:21.61] Summertime sadness"}
"""

private let lrclibMiss = """
{"statusCode":404,"error":"Not Found","message":"Failed to find specified track"}
"""

private let lrclibInstrumental = """
{"id":1,"trackName":"X","artistName":"Y","albumName":"Z","duration":265.0,
 "instrumental":true,"plainLyrics":null,"syncedLyrics":null}
"""

private let lrclibPlainOnly = """
{"id":2,"trackName":"X","artistName":"Y","albumName":"Z","duration":265.0,
 "instrumental":false,"plainLyrics":"just words","syncedLyrics":null}
"""

@Test func parsesSyncedLyricsIntoDocument() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "lrclib.net", json: lrclibHit)
    let doc = try await LRCLIBProvider(http: http).fetch(sampleQuery)
    #expect(doc?.providerID == "lrclib")
    #expect(doc?.lines.count == 2)
    #expect(doc?.lines[0].text == "Kiss me hard before you go")
    #expect(doc?.trackID == sampleQuery.trackID)
}

@Test func wordTimingsAreFilledIn() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "lrclib.net", json: lrclibHit)
    let doc = try await LRCLIBProvider(http: http).fetch(sampleQuery)
    let words = doc!.lines[0].words
    #expect(words.count == 6)
    #expect(words[0].start == doc!.lines[0].start)
    #expect(words[0].end > words[0].start)
    let allEstimated = words.allSatisfy { $0.isEstimated }
    #expect(allEstimated)
}

@Test func sendsDurationInSecondsNotMilliseconds() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "lrclib.net", json: lrclibHit)
    _ = try await LRCLIBProvider(http: http).fetch(sampleQuery)
    let url = await http.requestedURLs.first!
    #expect(url.contains("duration=265"))
    #expect(url.contains("duration=265427") == false)
}

@Test func returnsNilOn404() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "lrclib.net", json: lrclibMiss, status: 404)
    let doc = try await LRCLIBProvider(http: http).fetch(sampleQuery)
    #expect(doc == nil)
}

@Test func returnsNilForInstrumental() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "lrclib.net", json: lrclibInstrumental)
    let doc = try await LRCLIBProvider(http: http).fetch(sampleQuery)
    #expect(doc == nil)
}

@Test func returnsNilWhenOnlyPlainLyricsExist() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "lrclib.net", json: lrclibPlainOnly)
    let doc = try await LRCLIBProvider(http: http).fetch(sampleQuery)
    #expect(doc == nil)
}

@Test func propagatesTransportErrors() async {
    let http = StubHTTP()
    await http.failEverything()
    await #expect(throws: StubError.self) {
        try await LRCLIBProvider(http: http).fetch(sampleQuery)
    }
}

// MARK: - album mismatch: the synced entry often sits under a different album

private let lrclibPlainSingle = """
{"id":9,"trackName":"T","artistName":"A","albumName":"T","duration":265.0,
 "instrumental":false,"plainLyrics":"words","syncedLyrics":null}
"""

private let lrclibSyncedAlbum = """
{"id":10,"trackName":"T","artistName":"A","albumName":"Studio Album","duration":265.0,
 "instrumental":false,"plainLyrics":"words",
 "syncedLyrics":"[00:17.38] alpha beta\\n[00:21.61] gamma delta"}
"""

@Test func retriesWithoutAlbumWhenTheExactMatchHasNoTimestamps() async throws {
    let http = StubHTTP()
    // keys must differ in length so the most-specific match is unambiguous
    await http.stub(urlContains: "album_name=Born", json: lrclibPlainSingle)  // first attempt
    await http.stub(urlContains: "lrclib", json: lrclibSyncedAlbum)           // retry
    let doc = try await LRCLIBProvider(http: http).fetch(sampleQuery)
    #expect(doc != nil, "the synced entry under a different album should be found")
    #expect(doc?.lines.count == 2)
    let urls = await http.requestedURLs
    #expect(urls.count == 2)
    guard urls.count == 2 else { return }
    #expect(urls[0].contains("album_name"))
    #expect(urls[1].contains("album_name") == false)
    #expect(urls[1].contains("duration=265"), "duration must still constrain the retry")
}

@Test func doesNotRetryWhenTheFirstAttemptAlreadyHasTimestamps() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "lrclib.net", json: lrclibHit)
    _ = try await LRCLIBProvider(http: http).fetch(sampleQuery)
    #expect(await http.requestedURLs.count == 1, "no wasted second request")
}

@Test func returnsNilWhenNeitherAttemptHasTimestamps() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "lrclib", json: lrclibPlainSingle)
    let doc = try await LRCLIBProvider(http: http).fetch(sampleQuery)
    #expect(doc == nil)
}
