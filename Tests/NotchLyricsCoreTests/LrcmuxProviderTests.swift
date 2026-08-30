import Testing
import Foundation
@testable import NotchLyricsCore

// Shapes recorded from api.lrcmux.dev. Lyric text is placeholder.
private let wordLevel = """
{"track":{},"meta":{"source":{"id":"kugou","name":"KuGou"},"level":"word"},
 "lines":[
  {"text":"alpha beta","start":15615,"end":18015,
   "words":[{"text":"alpha","start":15615,"end":16800},{"text":"beta","start":16800,"end":18015}]},
  {"text":"gamma","start":20000,"end":21500,
   "words":[{"text":"gamma","start":20000,"end":21500}]}]}
"""

private let lineLevel = """
{"track":{},"meta":{"source":{"id":"netease","name":"NetEase"},"level":"line"},
 "lines":[
  {"text":"alpha beta gamma","start":10000,"end":14000,"words":[]},
  {"text":"delta epsilon","start":14000,"end":18000,"words":[]}]}
"""

private let cjkOnLatinTrack = """
{"track":{},"meta":{"source":{"id":"kugou","name":"KuGou"},"level":"line"},
 "lines":[{"text":"今天天气很好啊朋友","start":1000,"end":4000,"words":[]}]}
"""

@Test func lrcmuxUsesRealWordTimings() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "lrcmux", json: wordLevel)
    let doc = try await LrcmuxProvider(http: http).fetch(sampleQuery)
    #expect(doc?.providerID == "lrcmux")
    #expect(doc?.lines.count == 2)
    let w = doc!.lines[0].words
    #expect(w.count == 2)
    // measured, not inferred — this is the point of the provider
    let noneEstimated = w.allSatisfy { $0.isEstimated == false }
    #expect(noneEstimated)
    #expect(abs(w[0].start - 15.615) < 0.001)
    #expect(abs(w[1].end - 18.015) < 0.001)
}

@Test func lrcmuxConvertsMillisecondsToSeconds() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "lrcmux", json: wordLevel)
    let doc = try await LrcmuxProvider(http: http).fetch(sampleQuery)
    #expect(abs(doc!.lines[0].start - 15.615) < 0.001)
    #expect(abs(doc!.lines[1].end - 21.5) < 0.001)
}

@Test func lrcmuxEstimatesWhenOnlyLineTimingsAreOffered() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "lrcmux", json: lineLevel)
    let doc = try await LrcmuxProvider(http: http).fetch(sampleQuery)
    let w = doc!.lines[0].words
    #expect(w.count == 3, "the line should still be split into words")
    let allEstimated = w.allSatisfy { $0.isEstimated }
    #expect(allEstimated, "no measured timings were provided")
    for (a, b) in zip(w, w.dropFirst()) { #expect(a.start <= b.start) }
}

@Test func lrcmuxTreatsNotFoundAsAMiss() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "lrcmux",
                    json: #"{"title":"Not Found","status":404,"detail":"no lyrics found"}"#,
                    status: 404)
    let doc = try await LrcmuxProvider(http: http).fetch(sampleQuery)
    #expect(doc == nil)
}

@Test func lrcmuxRejectsCJKLyricsOnALatinTrack() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "lrcmux", json: cjkOnLatinTrack)
    let doc = try await LrcmuxProvider(http: http).fetch(sampleQuery)
    #expect(doc == nil)
}

@Test func lrcmuxSendsTheExpectedQuery() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "lrcmux", json: wordLevel)
    _ = try await LrcmuxProvider(http: http).fetch(sampleQuery)
    let url = await http.requestedURLs.first ?? ""
    #expect(url.contains("/get?"))
    #expect(url.contains("duration=265"))
    #expect(url.contains("title="))
    #expect(url.contains("artist="))
}

@Test func lrcmuxReturnsNilWhenThereAreNoLines() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "lrcmux", json: #"{"track":{},"meta":{},"lines":[]}"#)
    let doc = try await LrcmuxProvider(http: http).fetch(sampleQuery)
    #expect(doc == nil)
}
