import Testing
import Foundation
@testable import NotchLyricsCore

/// Shapes recorded from live music.163.com responses (spec §1.5).
private let searchHit = """
{"result":{"songs":[
  {"id":16593589,"name":"Summertime Sadness","duration":264773,
   "artists":[{"name":"Lana Del Rey"}]}]},"code":200}
"""

private let searchWrongDuration = """
{"result":{"songs":[
  {"id":26203201,"name":"Summertime Sadness (Asadinho Vocal Mix)","duration":514737,
   "artists":[{"name":"Lana Del Rey"}]}]},"code":200}
"""

private let searchEmpty = #"{"result":{"songs":[]},"code":200}"#

private let lyricHit = """
{"lrc":{"lyric":"[00:00.000] 作词 : Lana Del Rey\\n[00:17.320]Kiss me hard before you go\\n[00:21.389]Summertime sadness"},"code":200}
"""

private let lyricEmpty = #"{"lrc":{"lyric":""},"code":200}"#

@Test func fetchesAndParsesNetEaseLyrics() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "search/get", json: searchHit)
    await http.stub(urlContains: "song/lyric", json: lyricHit)
    let doc = try await NetEaseProvider(http: http).fetch(sampleQuery)
    #expect(doc?.providerID == "netease")
    #expect(doc?.lines.count == 2)              // credit line stripped
    #expect(doc?.lines[0].text == "Kiss me hard before you go")
}

@Test func rejectsCandidateOutsideDurationTolerance() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "search/get", json: searchWrongDuration)
    await http.stub(urlContains: "song/lyric", json: lyricHit)
    let doc = try await NetEaseProvider(http: http).fetch(sampleQuery)
    #expect(doc == nil)
}

@Test func returnsNilWhenSearchFindsNothing() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "search/get", json: searchEmpty)
    let doc = try await NetEaseProvider(http: http).fetch(sampleQuery)
    #expect(doc == nil)
}

@Test func returnsNilWhenLyricBodyIsEmpty() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "search/get", json: searchHit)
    await http.stub(urlContains: "song/lyric", json: lyricEmpty)
    let doc = try await NetEaseProvider(http: http).fetch(sampleQuery)
    #expect(doc == nil)
}

@Test func hitsBothSearchAndLyricEndpoints() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "search/get", json: searchHit)
    await http.stub(urlContains: "song/lyric", json: lyricHit)
    _ = try await NetEaseProvider(http: http).fetch(sampleQuery)
    let urls = await http.requestedURLs
    #expect(urls.contains { $0.contains("search/get") })
    #expect(urls.contains { $0.contains("song/lyric") })
}
