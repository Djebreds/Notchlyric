import Testing
import Foundation
@testable import NotchLyricsCore

private let timingJSON = """
{"audio_files":[{"chapter_id":1,"duration":46000,"verse_timings":[
 {"verse_key":"1:1","segments":[[1,0,580],[2,580,1409]]}]}]}
"""

private let wordsJSON = """
{"verses":[{"verse_key":"1:1","words":[
 {"position":1,"char_type_name":"word","text_uthmani":"alpha","code_v2":"g1","v2_page":1,"line_number":2},
 {"position":2,"char_type_name":"word","text_uthmani":"beta","code_v2":"g2","v2_page":1,"line_number":2},
 {"position":3,"char_type_name":"end","text_uthmani":"marker","code_v2":null,"v2_page":1,"line_number":2}]}]}
"""

private func quranQuery(duration: TimeInterval = 46.497,
                        genre: String? = "Quran",
                        track: Int? = 1,
                        album: String = "Quran — Murattal") -> TrackQuery {
    var q = TrackQuery(trackID: "music:X", title: "001. Al-Fatihah",
                       artist: "Mishary Rashid Alafasy", album: album, duration: duration)
    q.quranHint = QuranHint(trackNumber: track, genre: genre)
    return q
}

@Test func detectsSurahFromTrackNumber() {
    #expect(QuranProvider.surahNumber(for: quranQuery()) == 1)
}

@Test func rejectsWhenNothingMarksItAsQuran() {
    #expect(QuranProvider.surahNumber(for: quranQuery(genre: nil, album: "Born To Die")) == nil)
}

@Test func acceptsWhenOnlyTheAlbumSaysQuran() {
    #expect(QuranProvider.surahNumber(for: quranQuery(genre: nil)) == 1)
}

@Test func rejectsOutOfRangeTrackNumbers() {
    #expect(QuranProvider.surahNumber(for: quranQuery(track: 0)) == nil)
    #expect(QuranProvider.surahNumber(for: quranQuery(track: 115)) == nil)
    #expect(QuranProvider.surahNumber(for: quranQuery(track: nil)) == nil)
}

@Test func buildsAnArabicDocument() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "audio_files", json: timingJSON)
    await http.stub(urlContains: "verses/by_chapter", json: wordsJSON)
    let doc = try await QuranProvider(http: http).fetch(quranQuery())
    #expect(doc?.script == .arabic)
    #expect(doc?.providerID == "quran")
    #expect(doc?.lines.count == 1)
    #expect(doc?.lines[0].words.count == 2)     // the "end" marker token is excluded
    #expect(doc?.lines[0].words[0].fontPage == 1)
    #expect(doc?.lines[0].words[0].glyph == "g1")
}

@Test func rejectsWhenDurationDisagrees() async throws {
    let http = StubHTTP()
    await http.stub(urlContains: "audio_files", json: timingJSON)
    await http.stub(urlContains: "verses/by_chapter", json: wordsJSON)
    let doc = try await QuranProvider(http: http).fetch(quranQuery(duration: 60))
    #expect(doc == nil)
}

@Test func returnsNilForNonQuranTracks() async throws {
    let http = StubHTTP()
    let doc = try await QuranProvider(http: http).fetch(sampleQuery)
    #expect(doc == nil)
}
