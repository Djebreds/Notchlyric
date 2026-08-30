import Testing
import Foundation
@testable import NotchLyricsCore

// Shapes recorded from live kugou endpoints. Lyric bodies are placeholder text.
private let kugouSearch = """
{"data":{"info":[
 {"hash":"87f091a8","songname":"Summertime Sadness","singername":"Lana Del Rey","duration":265},
 {"hash":"deadbeef","songname":"Summertime Sadness (Remix)","singername":"Lana Del Rey","duration":266}]}}
"""

private let kugouSearchWrongArtist = """
{"data":{"info":[
 {"hash":"aaaa","songname":"Summertime Sadness","singername":"Someone Else","duration":265}]}}
"""

private let kugouCandidates = """
{"candidates":[{"id":"12345","accesskey":"ABCDEF","song":"Summertime Sadness","duration":265000}]}
"""

private let kugouDownload = #"{"content":"WzAwOjE3LjM4XSBhbHBoYSBiZXRhClswMDoyMS42MV0gZ2FtbWEgZGVsdGEK","fmt":"lrc"}"#

private let kugouNoCandidates = #"{"candidates":[]}"#

@Test func kugouFetchesAndParsesSyncedLyrics() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "mobileservice", json: kugouSearch)
    await http.stub(urlContains: "krcs", json: kugouCandidates)
    await http.stub(urlContains: "lyrics.kugou", json: kugouDownload)
    let doc = try await KugouProvider(http: http).fetch(sampleQuery)
    #expect(doc?.providerID == "kugou")
    #expect(doc?.lines.count == 2)
}

@Test func kugouRejectsAVariantRecording() async throws {
    let http = StubHTTP()
    // only the remix is offered, and the query did not ask for a remix
    await http.stub(urlContains: "mobileservice", json: """
    {"data":{"info":[{"hash":"x","songname":"Summertime Sadness (Remix)","singername":"Lana Del Rey","duration":265}]}}
    """)
    await http.stub(urlContains: "krcs", json: kugouCandidates)
    await http.stub(urlContains: "lyrics.kugou", json: kugouDownload)
    let doc = try await KugouProvider(http: http).fetch(sampleQuery)
    #expect(doc == nil)
}

@Test func kugouRejectsAMismatchedArtist() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "mobileservice", json: kugouSearchWrongArtist)
    await http.stub(urlContains: "krcs", json: kugouCandidates)
    await http.stub(urlContains: "lyrics.kugou", json: kugouDownload)
    #expect(try await KugouProvider(http: http).fetch(sampleQuery) == nil)
}

@Test func kugouRejectsAMismatchedDuration() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "mobileservice", json: """
    {"data":{"info":[{"hash":"x","songname":"Summertime Sadness","singername":"Lana Del Rey","duration":400}]}}
    """)
    await http.stub(urlContains: "krcs", json: kugouCandidates)
    await http.stub(urlContains: "lyrics.kugou", json: kugouDownload)
    #expect(try await KugouProvider(http: http).fetch(sampleQuery) == nil)
}

@Test func kugouReturnsNilWhenNoLyricCandidates() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "mobileservice", json: kugouSearch)
    await http.stub(urlContains: "krcs", json: kugouNoCandidates)
    #expect(try await KugouProvider(http: http).fetch(sampleQuery) == nil)
}

@Test func kugouReturnsNilOnUndecodableContent() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "mobileservice", json: kugouSearch)
    await http.stub(urlContains: "krcs", json: kugouCandidates)
    await http.stub(urlContains: "lyrics.kugou", json: #"{"content":"!!!not base64!!!"}"#)
    #expect(try await KugouProvider(http: http).fetch(sampleQuery) == nil)
}

@Test func kugouSendsDurationInMilliseconds() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "mobileservice", json: kugouSearch)
    await http.stub(urlContains: "krcs", json: kugouCandidates)
    await http.stub(urlContains: "lyrics.kugou", json: kugouDownload)
    _ = try await KugouProvider(http: http).fetch(sampleQuery)
    let urls = await http.requestedURLs
    #expect(urls.contains { $0.contains("krcs") && $0.contains("duration=265000") })
}
