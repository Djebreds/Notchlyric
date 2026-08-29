import Testing
import Foundation
@testable import NotchLyricsCore

private func qw(_ pos: Int, _ text: String, _ glyph: String,
                page: Int, line: Int) -> QuranTiming.WordText {
    .init(position: pos, textUthmani: text, glyph: glyph, page: page, lineNumber: line)
}

@Test func groupsWordsIntoMushafLines() {
    let timings = [QuranTiming.VerseTiming(verseKey: "1:1", segments: [
        [1, 0, 580], [2, 580, 1409], [3, 1409, 2502], [4, 2502, 5840],
    ])]
    let words = ["1:1": [qw(1,"a","g1",page:1,line:2), qw(2,"b","g2",page:1,line:2),
                         qw(3,"c","g3",page:1,line:3), qw(4,"d","g4",page:1,line:3)]]
    let lines = QuranTiming.mushafLines(timings: timings, words: words)
    #expect(lines.count == 2)
    #expect(lines[0].words.count == 2)
    #expect(lines[0].start == 0)
    #expect(abs(lines[0].end - 1.409) < 0.001)
    #expect(abs(lines[1].start - 1.409) < 0.001)
}

@Test func convertsMillisecondsToSeconds() {
    let timings = [QuranTiming.VerseTiming(verseKey: "1:1", segments: [[1, 6025, 7025]])]
    let lines = QuranTiming.mushafLines(timings: timings,
                                        words: ["1:1": [qw(1,"a","g",page:1,line:1)]])
    #expect(abs(lines[0].words[0].start - 6.025) < 0.001)
    #expect(abs(lines[0].words[0].end - 7.025) < 0.001)
}

@Test func skipsMalformedSegments() {
    let timings = [QuranTiming.VerseTiming(verseKey: "1:3", segments: [[1, 11615, 12855], [1]])]
    let words = ["1:3": [qw(1,"a","g1",page:1,line:1), qw(2,"b","g2",page:1,line:1)]]
    let lines = QuranTiming.mushafLines(timings: timings, words: words)
    #expect(lines.count == 1)
    #expect(lines[0].words.count == 1)
}

@Test func carriesGlyphAndPagePerWord() {
    let timings = [QuranTiming.VerseTiming(verseKey: "2:1", segments: [[1,0,100],[2,100,200]])]
    let words = ["2:1": [qw(1,"a","g1",page:48,line:15), qw(2,"b","g2",page:49,line:1)]]
    let lines = QuranTiming.mushafLines(timings: timings, words: words)
    #expect(lines.count == 2)
    #expect(lines[0].words[0].fontPage == 48)
    #expect(lines[1].words[0].fontPage == 49)
    #expect(lines[0].words[0].glyph == "g1")
}

@Test func marksTimingsAsMeasuredNotEstimated() {
    let timings = [QuranTiming.VerseTiming(verseKey: "1:1", segments: [[1,0,580]])]
    let lines = QuranTiming.mushafLines(timings: timings,
                                        words: ["1:1": [qw(1,"a","g",page:1,line:1)]])
    #expect(lines[0].words[0].isEstimated == false)
}

@Test func ignoresSegmentsWithNoMatchingWord() {
    let timings = [QuranTiming.VerseTiming(verseKey: "1:1", segments: [[9, 0, 100]])]
    #expect(QuranTiming.mushafLines(timings: timings,
                                    words: ["1:1": [qw(1,"a","g",page:1,line:1)]]).isEmpty)
}

@Test func linesAreOrderedByTime() {
    let timings = [QuranTiming.VerseTiming(verseKey: "1:1", segments: [[1,5000,5500]]),
                   QuranTiming.VerseTiming(verseKey: "1:2", segments: [[1,1000,1500]])]
    let words = ["1:1": [qw(1,"late","g1",page:1,line:9)],
                 "1:2": [qw(1,"early","g2",page:1,line:1)]]
    let lines = QuranTiming.mushafLines(timings: timings, words: words)
    #expect(lines.map { $0.words[0].text } == ["early", "late"])
}

@Test func returnsEmptyForNoTimings() {
    #expect(QuranTiming.mushafLines(timings: [], words: [:]).isEmpty)
}
