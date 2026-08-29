import Testing
import Foundation
@testable import NotchLyricsCore

// All fixtures are neutral sentences, never song lyrics.

// MARK: - detection

@Test func detectsJapaneseScript() {
    #expect(CJKSegmenter.isCJK("今日は良い天気ですね"))
    #expect(CJKSegmenter.isCJK("カタカナとひらがな"))
}

@Test func detectsChineseAndKorean() {
    #expect(CJKSegmenter.isCJK("今天天气很好"))
    #expect(CJKSegmenter.isCJK("오늘 날씨가 좋아요"))
}

@Test func doesNotFlagLatinText() {
    #expect(CJKSegmenter.isCJK("You leapt from crumbling bridges") == false)
    #expect(CJKSegmenter.isCJK("yozora ni ukabu hoshi") == false)   // already romaji
    #expect(CJKSegmenter.isCJK("") == false)
    #expect(CJKSegmenter.isCJK("   ") == false)
}

@Test func ignoresIncidentalCJKInMostlyLatinText() {
    // a stray character must not trigger reprocessing of a Latin line
    #expect(CJKSegmenter.isCJK("this is an english line with one 音 char") == false)
}

// MARK: - segmentation

@Test func segmentsJapaneseIntoManyTokens() {
    let out = CJKSegmenter.segment("夜空に浮かぶ星を数えている")
    #expect(out.count >= 6)                       // space split would give 1
    #expect(out.allSatisfy { !$0.text.isEmpty })
}

@Test func producesRomajiNotChineseReadings() {
    // CFStringTransform would render this "dōng jīng dōu"
    let out = CJKSegmenter.segment("東京都")
    let joined = out.map(\.romaji).joined()
    #expect(joined.lowercased().contains("tou"))
    #expect(joined.lowercased().contains("dong") == false)
}

@Test func romajiIsAsciiLetters() {
    for s in CJKSegmenter.segment("音楽を聴いている") {
        #expect(s.romaji.isEmpty == false)
        #expect(s.romaji.allSatisfy { $0.isASCII })
    }
}

@Test func keepsOriginalAlongsideRomaji() {
    let out = CJKSegmenter.segment("天気")
    #expect(out.first?.text == "天気")
    #expect(out.first?.romaji.lowercased() == "tenki")
}

@Test func passesLatinTokensThroughUnchanged() {
    let out = CJKSegmenter.segment("私はrockが好き")
    let romaji = out.map(\.romaji).joined(separator: " ").lowercased()
    #expect(romaji.contains("rock"))
}

@Test func segmenterReturnsEmptyForEmptyInput() {
    #expect(CJKSegmenter.segment("").isEmpty)
}

@Test func segmentationBeatsSpaceSplittingSubstantially() {
    let line = "静かな街を一人で歩いていた"
    let spaceSplit = line.split(separator: " ").count
    let tokenized = CJKSegmenter.segment(line).count
    #expect(spaceSplit == 1)
    #expect(tokenized >= 6)
}
