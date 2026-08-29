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
