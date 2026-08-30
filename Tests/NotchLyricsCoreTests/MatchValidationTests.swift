import Testing
import Foundation
@testable import NotchLyricsCore

private struct Probe: LyricsProvider {
    let id = "probe"
    func fetch(_ track: TrackQuery) async throws -> LyricsDocument? { nil }
}

private func line(_ start: TimeInterval, _ end: TimeInterval) -> LyricLine {
    LyricLine(start: start, end: end,
              words: [WordToken(text: "w", start: start, end: end, isEstimated: true)])
}

private let track = TrackQuery(trackID: "t", title: "It's Time",
                               artist: "Imagine Dragons", album: "It's Time", duration: 247)

// MARK: - lyrics must fit inside the track

@Test func acceptsLyricsThatEndWithinTheTrack() {
    #expect(Probe().timingsFit([line(3, 20), line(200, 246)], track: track))
}

@Test func rejectsLyricsRunningPastTheEndOfTheTrack() {
    // the observed failure: a live version's lyrics spanning 292s on a 247s track
    #expect(Probe().timingsFit([line(3, 20), line(288, 292.6)], track: track) == false)
}

@Test func rejectsTheObservedNetEaseMismatch() {
    // 60 lines to 260s against a 193s track
    let short = TrackQuery(trackID: "t", title: "T", artist: "A", album: "B", duration: 193)
    #expect(Probe().timingsFit([line(22, 30), line(255, 260)], track: short) == false)
}

@Test func toleratesASmallOverrun() {
    // LRC timestamps often sit a little past the final vocal
    #expect(Probe().timingsFit([line(3, 20), line(249, 252)], track: track))
}

@Test func toleratesTrailingCreditLinesPastTheAudio() {
    // Measured on a real track: 193s of audio, three trailing lines to 207.5s.
    // Judging on the final timestamp with a tight margin threw this away.
    let dido = TrackQuery(trackID: "t", title: "T", artist: "A", album: "B", duration: 193.3)
    var lines = (0..<35).map { line(Double($0) * 5, Double($0) * 5 + 4) }
    lines += [line(200, 202), line(204, 206), line(207.5, 209)]
    #expect(Probe().timingsFit(lines, track: dido))
}

@Test func acceptsAnythingWhenTrackDurationIsUnknown() {
    let unknown = TrackQuery(trackID: "t", title: "x", artist: "y", album: "z", duration: 0)
    #expect(Probe().timingsFit([line(3, 900)], track: unknown))
}

@Test func acceptsEmptyLines() {
    #expect(Probe().timingsFit([], track: track))
}

// MARK: - a candidate must be the same recording, not a variant

@Test func acceptsAnExactTitle() {
    #expect(LyricsMatch.isSameRecording(candidate: "It's Time", query: "It's Time"))
}

@Test func ignoresCaseAndPunctuation() {
    #expect(LyricsMatch.isSameRecording(candidate: "Its  Time", query: "It's Time"))
}

@Test func rejectsLiveAndOtherVariants() {
    for variant in ["It's Time (Live London Session)", "It's Time - Live in Vegas",
                    "It's Time (Acoustic)", "It's Time (Remix)", "It's Time (Karaoke Version)",
                    "It's Time - Instrumental", "It's Time (Demo)"] {
        #expect(LyricsMatch.isSameRecording(candidate: variant, query: "It's Time") == false,
                "should reject \(variant)")
    }
}

@Test func keepsVariantsWhenTheQueryAsksForThem() {
    // someone deliberately playing the live cut should still match it
    #expect(LyricsMatch.isSameRecording(candidate: "It's Time (Live in Vegas)",
                                        query: "It's Time (Live in Vegas)"))
}

@Test func allowsHarmlessSuffixes() {
    #expect(LyricsMatch.isSameRecording(candidate: "It's Time (2012 Remaster)",
                                        query: "It's Time") == false)
    #expect(LyricsMatch.isSameRecording(candidate: "It's Time!", query: "It's Time"))
}

// MARK: - script sanity: CJK lyrics on a plainly Latin track are a mismatch

@Test func rejectsCJKLyricsForALatinTrack() {
    #expect(LyricsMatch.scriptPlausible(lyricsAreCJK: true, track: track) == false)
}

@Test func acceptsLatinLyricsForALatinTrack() {
    #expect(LyricsMatch.scriptPlausible(lyricsAreCJK: false, track: track))
}

@Test func acceptsCJKLyricsWhenTheTrackItselfIsCJK() {
    let jp = TrackQuery(trackID: "t", title: "夜に駆ける", artist: "YOASOBI",
                        album: "THE BOOK", duration: 260)
    #expect(LyricsMatch.scriptPlausible(lyricsAreCJK: true, track: jp))
}

@Test func acceptsCJKLyricsWhenOnlyTheArtistIsCJK() {
    let mixed = TrackQuery(trackID: "t", title: "Idol", artist: "YOASOBI",
                           album: "アイドル", duration: 200)
    #expect(LyricsMatch.scriptPlausible(lyricsAreCJK: true, track: mixed))
}

@Test func artistMustMatchToo() {
    #expect(LyricsMatch.isSameArtist(candidate: "Imagine Dragons", query: "Imagine Dragons"))
    #expect(LyricsMatch.isSameArtist(candidate: "周杰倫", query: "Imagine Dragons") == false)
    #expect(LyricsMatch.isSameArtist(candidate: "", query: "Imagine Dragons") == false)
}
