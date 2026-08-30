import Testing
import Foundation
@testable import NotchLyricsCore

private func doc(_ starts: [TimeInterval]) -> LyricsDocument {
    let lines = starts.enumerated().map { i, s in
        LyricLine(start: s, end: i + 1 < starts.count ? starts[i + 1] : s + 3,
                  words: [WordToken(text: "l\(i)", start: s, end: s + 1, isEstimated: true)])
    }
    return LyricsDocument(trackID: "t", providerID: "p", lines: lines)
}

@Test func durationConvertsMillisecondsToSeconds() {
    let s = PlaybackState(trackID: "spotify:track:x", title: "T", artist: "A", album: "B",
                          durationMs: 265427, position: 83.7, isPlaying: true)
    #expect(abs(s.duration - 265.427) < 0.0001)
}

@Test func indexAtReturnsNilBeforeFirstLine() {
    #expect(doc([10, 20, 30]).index(at: 5) == nil)
}

@Test func indexAtFindsActiveLine() {
    let d = doc([10, 20, 30])
    #expect(d.index(at: 10) == 0)
    #expect(d.index(at: 19.9) == 0)
    #expect(d.index(at: 20) == 1)
    #expect(d.index(at: 999) == 2)
}

@Test func wordProgressClamps() {
    let w = WordToken(text: "hi", start: 4, end: 6, isEstimated: true)
    #expect(w.progress(at: 3) == 0)
    #expect(w.progress(at: 5) == 0.5)
    #expect(w.progress(at: 9) == 1)
}

@Test func wordTokenDefaultsToNoGlyph() {
    let w = WordToken(text: "hi", start: 0, end: 1, isEstimated: true)
    #expect(w.glyph == nil)
    #expect(w.fontPage == nil)
}

@Test func wordTokenCarriesGlyphAndPage() {
    let w = WordToken(text: "x", start: 0, end: 0.58, isEstimated: false,
                      glyph: "\u{FC41}", fontPage: 1)
    #expect(w.glyph == "\u{FC41}")
    #expect(w.fontPage == 1)
    #expect(w.isEstimated == false)
}

@Test func documentDefaultsToLatinScript() {
    let d = LyricsDocument(trackID: "t", providerID: "p", lines: [])
    #expect(d.script == .latin)
}

@Test func documentRoundTripsNewFieldsThroughCodable() throws {
    let d = LyricsDocument(trackID: "t", providerID: "quran", script: .arabic, lines: [
        LyricLine(start: 0, end: 1, words: [
            WordToken(text: "x", start: 0, end: 1, isEstimated: false, glyph: "g", fontPage: 48)
        ])
    ])
    let back = try JSONDecoder().decode(LyricsDocument.self, from: JSONEncoder().encode(d))
    #expect(back == d)
    #expect(back.script == .arabic)
    #expect(back.lines[0].words[0].fontPage == 48)
}

@Test func playbackStateCarriesTrackNumberAndGenre() {
    let s = PlaybackState(trackID: "m:1", title: "T", artist: "A", album: "Quran",
                          durationMs: 46497, position: 0, isPlaying: true,
                          trackNumber: 1, genre: "Quran")
    #expect(s.trackNumber == 1)
    #expect(s.genre == "Quran")
    #expect(s.query.quranHint?.trackNumber == 1)
}

@Test func playbackStateDefaultsThoseToNil() {
    let s = PlaybackState(trackID: "s:1", title: "T", artist: "A", album: "B",
                          durationMs: 1000, position: 0, isPlaying: true)
    #expect(s.trackNumber == nil)
    #expect(s.genre == nil)
}

@Test func cacheSchemaVersionIsThree() {
    #expect(LyricsCache.schemaVersion == 9)
}
