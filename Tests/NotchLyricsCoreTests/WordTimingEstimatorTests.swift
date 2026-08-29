import Testing
import Foundation
@testable import NotchLyricsCore

private func estimatedLine(_ text: String, _ start: TimeInterval, _ end: TimeInterval) -> LyricLine {
    LyricLine(start: start, end: end,
              words: text.split(separator: " ").map {
                  WordToken(text: String($0), start: start, end: end, isEstimated: true)
              })
}

@Test func distributesSpanAcrossWords() {
    let out = WordTimingEstimator.apply(to: [estimatedLine("aa bb cc", 0, 9)])
    let w = out[0].words
    #expect(w.count == 3)
    #expect(w[0].start == 0)
    #expect(abs(w[2].end - 9) < 0.0001)
    #expect(abs(w[0].end - 3) < 0.0001)
    #expect(abs(w[1].start - 3) < 0.0001)
}

@Test func longerWordsGetMoreTime() {
    let out = WordTimingEstimator.apply(to: [estimatedLine("a mississippi", 0, 10)])
    let w = out[0].words
    let short = w[0].end - w[0].start
    let long = w[1].end - w[1].start
    #expect(long > short * 3)
}

@Test func wordsAreContiguousAndOrdered() {
    let out = WordTimingEstimator.apply(to: [estimatedLine("one two three four", 5, 13)])
    let w = out[0].words
    for i in 0..<(w.count - 1) {
        #expect(abs(w[i].end - w[i + 1].start) < 0.0001)
        #expect(w[i].start < w[i].end)
    }
    #expect(w.first!.start == 5)
    #expect(abs(w.last!.end - 13) < 0.0001)
}

@Test func preservesRealWordTimings() {
    let real = LyricLine(start: 0, end: 10, words: [
        WordToken(text: "a", start: 0, end: 1, isEstimated: false),
        WordToken(text: "b", start: 1, end: 2, isEstimated: false),
    ])
    let out = WordTimingEstimator.apply(to: [real])
    #expect(out[0].words == real.words)
}

@Test func handlesBlankLine() {
    let blank = LyricLine(start: 0, end: 5, words: [])
    #expect(WordTimingEstimator.apply(to: [blank])[0].words.isEmpty)
}

@Test func handlesZeroLengthSpan() {
    let out = WordTimingEstimator.apply(to: [estimatedLine("a b", 7, 7)])
    #expect(out[0].words.allSatisfy { $0.start == 7 && $0.end == 7 })
}
