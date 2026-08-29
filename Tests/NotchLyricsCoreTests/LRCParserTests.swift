import Testing
import Foundation
@testable import NotchLyricsCore

@Test func parsesBasicTimestamps() {
    let lrc = """
    [00:17.38] Kiss me hard before you go
    [00:21.61] Summertime sadness
    """
    let lines = LRCParser.parse(lrc, trackDuration: 265)
    #expect(lines.count == 2)
    #expect(abs(lines[0].start - 17.38) < 0.001)
    #expect(lines[0].text == "Kiss me hard before you go")
    #expect(abs(lines[0].end - 21.61) < 0.001)
}

@Test func parsesMillisecondPrecision() {
    let lines = LRCParser.parse("[00:17.320]Kiss me", trackDuration: 100)
    #expect(abs(lines[0].start - 17.32) < 0.001)
}

@Test func lastLineEndsAtTrackDuration() {
    let lines = LRCParser.parse("[00:10.00] only line", trackDuration: 42)
    #expect(lines[0].end == 42)
}

@Test func lastLineFallsBackWhenDurationUnknown() {
    let lines = LRCParser.parse("[00:10.00] only line", trackDuration: 0)
    #expect(lines[0].end == 14)
}

@Test func skipsMetadataTags() {
    let lrc = """
    [ar:Lana Del Rey]
    [ti:Summertime Sadness]
    [00:17.38] real line
    """
    let lines = LRCParser.parse(lrc, trackDuration: 100)
    #expect(lines.count == 1)
    #expect(lines[0].text == "real line")
}

@Test func appliesOffsetTag() {
    let lrc = """
    [offset:+500]
    [00:10.00] shifted
    """
    let lines = LRCParser.parse(lrc, trackDuration: 100)
    #expect(abs(lines[0].start - 9.5) < 0.001)
}

@Test func expandsMultipleTimestampsOnOneLine() {
    let lines = LRCParser.parse("[00:10.00][00:50.00] chorus", trackDuration: 100)
    #expect(lines.count == 2)
    #expect(lines[0].start == 10)
    #expect(lines[1].start == 50)
    #expect(lines.map(\.text) == ["chorus", "chorus"])
}

@Test func stripsNetEaseCreditLines() {
    let lrc = """
    [00:00.000] 作词 : Lana Del Rey
    [00:01.000] 作曲 : Rick Nowels
    [00:17.320]Kiss me hard
    """
    let lines = LRCParser.parse(lrc, trackDuration: 100)
    #expect(lines.count == 1)
    #expect(lines[0].text == "Kiss me hard")
}

@Test func keepsBlankLinesAsGaps() {
    let lrc = """
    [00:10.00] first
    [00:12.00]
    [00:20.00] second
    """
    let lines = LRCParser.parse(lrc, trackDuration: 100)
    #expect(lines.count == 3)
    #expect(lines[1].isBlank)
    #expect(lines[0].end == 12)
}

@Test func sortsOutOfOrderTimestamps() {
    let lines = LRCParser.parse("[00:50.00] later\n[00:10.00] earlier", trackDuration: 100)
    #expect(lines.map(\.text) == ["earlier", "later"])
}

@Test func ignoresMalformedLines() {
    let lines = LRCParser.parse("no timestamp here\n[bad] also bad\n[00:10.00] good", trackDuration: 100)
    #expect(lines.count == 1)
    #expect(lines[0].text == "good")
}

@Test func parsesEnhancedWordTags() {
    let lines = LRCParser.parse("[00:10.00] <00:10.00>Kiss <00:10.50>me <00:11.00>hard", trackDuration: 100)
    #expect(lines.count == 1)
    #expect(lines[0].words.map(\.text) == ["Kiss", "me", "hard"])
    #expect(lines[0].words[0].isEstimated == false)
    #expect(abs(lines[0].words[1].start - 10.5) < 0.001)
}

@Test func returnsEmptyForEmptyInput() {
    #expect(LRCParser.parse("", trackDuration: 100).isEmpty)
}
