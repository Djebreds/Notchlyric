import Testing
import Foundation
@testable import NotchLyricsCore

private func doc(_ spans: [(TimeInterval, TimeInterval)], measured: Bool = false) -> LyricsDocument {
    LyricsDocument(trackID: "t", providerID: "p", lines: spans.map { s, e in
        LyricLine(start: s, end: e,
                  words: [WordToken(text: "w", start: s, end: e, isEstimated: !measured)])
    })
}

private let track = TrackQuery(trackID: "t", title: "T", artist: "A", album: "B", duration: 240)

@Test func anEntryEndingAtTheTrackLengthScoresBest() {
    let good = FitScore.of(doc([(10, 60), (200, 239)]), track: track)
    let short = FitScore.of(doc([(10, 60), (150, 180)]), track: track)
    #expect(good > short)
}

@Test func anEntryRunningPastTheTrackScoresWorse() {
    let fits = FitScore.of(doc([(10, 60), (200, 238)]), track: track)
    let over = FitScore.of(doc([(10, 60), (300, 340)]), track: track)
    #expect(fits > over)
}

@Test func aBadlyCompressedEntryScoresWorseThanAFittingOne() {
    // the lrcmux failure mode: right song, wrong recording, ends 50s early
    let fitting = FitScore.of(doc([(22, 40), (250, 277)]),
                              track: TrackQuery(trackID: "t", title: "T", artist: "A",
                                                album: "B", duration: 277))
    let compressed = FitScore.of(doc([(22, 40), (200, 223)]),
                                 track: TrackQuery(trackID: "t", title: "T", artist: "A",
                                                   album: "B", duration: 277))
    #expect(fitting > compressed)
}

@Test func measuredTimingsBreakATie() {
    let estimated = FitScore.of(doc([(10, 60), (200, 239)]), track: track)
    let measured = FitScore.of(doc([(10, 60), (200, 239)], measured: true), track: track)
    #expect(measured > estimated)
}

@Test func measuredTimingsDoNotOutweighBadAlignment() {
    // precision about the wrong recording must never beat a well-aligned entry
    let alignedEstimate = FitScore.of(doc([(10, 60), (200, 239)]), track: track)
    let measuredButOff = FitScore.of(doc([(10, 60), (300, 340)], measured: true), track: track)
    #expect(alignedEstimate > measuredButOff)
}

@Test func anEmptyDocumentScoresLowest() {
    #expect(FitScore.of(doc([]), track: track) == 0)
}

@Test func scoreIsIgnoredWhenTrackDurationIsUnknown() {
    let unknown = TrackQuery(trackID: "t", title: "T", artist: "A", album: "B", duration: 0)
    #expect(FitScore.of(doc([(10, 60)]), track: unknown) > 0)
}

@Test func aGoodEnoughEntryIsAcceptedWithoutCheckingOthers() {
    #expect(FitScore.isGoodEnough(FitScore.of(doc([(10, 60), (200, 239)]), track: track)))
    #expect(FitScore.isGoodEnough(FitScore.of(doc([(10, 60), (150, 180)]), track: track)) == false)
}
