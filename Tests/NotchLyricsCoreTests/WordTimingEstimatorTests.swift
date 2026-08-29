import Testing
import Foundation
@testable import NotchLyricsCore

private func line(_ text: String, _ start: TimeInterval, _ end: TimeInterval) -> LyricLine {
    LyricLine(start: start, end: end,
              words: text.split(separator: " ").map {
                  WordToken(text: String($0), start: start, end: end, isEstimated: true)
              })
}

/// A line sung densely: gap matches a plausible singing rate.
private func denseDocument() -> [LyricLine] {
    // 24 chars per line, 1.7s gaps -> ~0.07 s/char
    (0..<12).map { i in
        line("aaaa bbbb cccc dddd eeee", Double(i) * 1.7, Double(i + 1) * 1.7)
    }
}

// MARK: - the regression this fixes

@Test func wordsFinishBeforeTheGapEndsWhenThereIsDeadAir() {
    // Dense song (~0.07 s/char) but this line is followed by 10s of silence.
    var lines = denseDocument()
    lines.append(line("aaaa bbbb cccc dddd eeee", 20.4, 30.4))
    let out = WordTimingEstimator.apply(to: lines)
    let last = out.last!

    // 24 chars at the song's own rate is well under 10s.
    #expect(last.words.last!.end < 25.4)
    // The line itself still stays on screen for the whole gap.
    #expect(last.end == 30.4)
}

@Test func denseLinesStillConsumeTheWholeGap() {
    let out = WordTimingEstimator.apply(to: denseDocument())
    let l = out[3]
    // Nothing to trim: singing fills the gap, so words span it end to end.
    #expect(abs(l.words.last!.end - l.end) < 0.15)
}

@Test func rateIsDerivedPerDocumentNotGlobally() {
    let fast = (0..<12).map { i in line("aaaa bbbb cccc", Double(i) * 0.9, Double(i + 1) * 0.9) }
    let slow = (0..<12).map { i in line("aaaa bbbb cccc", Double(i) * 2.4, Double(i + 1) * 2.4) }

    let fastRate = WordTimingEstimator.secondsPerCharacter(for: fast)
    let slowRate = WordTimingEstimator.secondsPerCharacter(for: slow)
    #expect(slowRate > fastRate)

    // Same text, different songs -> different sung durations.
    let f = WordTimingEstimator.apply(to: fast)[3]
    let s = WordTimingEstimator.apply(to: slow)[3]
    let fDur = f.words.last!.end - f.start
    let sDur = s.words.last!.end - s.start
    #expect(sDur > fDur)
}

@Test func rateFallsBackWhenThereIsTooLittleData() {
    let rate = WordTimingEstimator.secondsPerCharacter(for: [line("hello there", 0, 30)])
    #expect(rate == WordTimingEstimator.fallbackSecondsPerCharacter)
}

@Test func rateIsClampedAgainstPathologicalData() {
    let absurd = (0..<12).map { i in line("aaaaaaaaaa", Double(i) * 60, Double(i + 1) * 60) }
    let rate = WordTimingEstimator.secondsPerCharacter(for: absurd)
    #expect(rate <= WordTimingEstimator.maximumSecondsPerCharacter)
    #expect(rate >= WordTimingEstimator.minimumSecondsPerCharacter)
}

@Test func shortLinesKeepAReadableMinimumDuration() {
    var lines = denseDocument()
    lines.append(line("oh", 20.4, 30.4))
    let last = WordTimingEstimator.apply(to: lines).last!
    #expect(last.words.last!.end - last.start >= WordTimingEstimator.minimumSungDuration - 0.001)
}

@Test func sungDurationNeverExceedsTheGap() {
    // Very long line, very short gap: must not overrun into the next line.
    var lines = denseDocument()
    lines.append(line(String(repeating: "word ", count: 40), 20.4, 21.0))
    let last = WordTimingEstimator.apply(to: lines).last!
    #expect(last.words.last!.end <= 21.0 + 0.001)
}

// MARK: - distribution mechanics

@Test func distributesProportionallyByCharacterCount() {
    var lines = denseDocument()
    lines.append(line("a mississippi", 20.4, 30.4))
    let w = WordTimingEstimator.apply(to: lines).last!.words
    #expect((w[1].end - w[1].start) > (w[0].end - w[0].start) * 3)
}

@Test func wordsAreContiguousOrderedAndStartOnTime() {
    let l = WordTimingEstimator.apply(to: denseDocument())[3]
    let w = l.words
    #expect(w.first!.start == l.start)
    for i in 0..<(w.count - 1) {
        #expect(abs(w[i].end - w[i + 1].start) < 0.0001)
        #expect(w[i].start < w[i].end)
    }
}

@Test func preservesRealWordTimings() {
    let real = LyricLine(start: 0, end: 10, words: [
        WordToken(text: "a", start: 0, end: 1, isEstimated: false),
        WordToken(text: "b", start: 1, end: 2, isEstimated: false),
    ])
    #expect(WordTimingEstimator.apply(to: [real])[0].words == real.words)
}

@Test func handlesBlankLine() {
    let blank = LyricLine(start: 0, end: 5, words: [])
    #expect(WordTimingEstimator.apply(to: [blank])[0].words.isEmpty)
}

@Test func handlesZeroLengthSpan() {
    let out = WordTimingEstimator.apply(to: [line("a b", 7, 7)])
    #expect(out[0].words.allSatisfy { $0.start == 7 && $0.end == 7 })
}
