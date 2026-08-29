import Testing
import Foundation
@testable import NotchLyricsCore

private let a0 = ContinuousClock.now

private func st(_ id: String, playing: Bool, position: TimeInterval = 0) -> PlaybackState {
    PlaybackState(trackID: id, title: id, artist: "a", album: "b",
                  durationMs: 1000, position: position, isPlaying: playing)
}

@Test func arbiterHidesWhenNothingReported() {
    var a = SourceArbiter()
    #expect(a.update(sourceID: "spotify", state: nil, at: a0) == .hide)
}

@Test func arbiterUpdatesForTheOnlyPlayingSource() {
    var a = SourceArbiter()
    #expect(a.update(sourceID: "spotify", state: st("s", playing: true), at: a0)
            == .update(st("s", playing: true)))
}

@Test func arbiterHidesForAPausedSource() {
    var a = SourceArbiter()
    #expect(a.update(sourceID: "spotify", state: st("s", playing: false), at: a0) == .hide)
}

// MARK: - the regression: a silent source must not replay the winner's old sample

@Test func anIdleSourceReportingDoesNotReemitTheWinnersStaleState() {
    var a = SourceArbiter()
    _ = a.update(sourceID: "spotify", state: st("s", playing: true, position: 10), at: a0)
    // music polls a second later with nothing playing; spotify's stored sample
    // is now a second old and must not be fed back to the clock
    let d = a.update(sourceID: "music", state: nil, at: a0.advanced(by: .seconds(1)))
    #expect(d == .unchanged)
}

@Test func repeatedIdleReportsStayUnchanged() {
    var a = SourceArbiter()
    _ = a.update(sourceID: "spotify", state: st("s", playing: true, position: 10), at: a0)
    for i in 1...5 {
        let d = a.update(sourceID: "music", state: nil, at: a0.advanced(by: .seconds(i)))
        #expect(d == .unchanged)
    }
}

@Test func theWinnersOwnReportsAlwaysUpdate() {
    var a = SourceArbiter()
    _ = a.update(sourceID: "spotify", state: st("s", playing: true, position: 10), at: a0)
    let d = a.update(sourceID: "spotify", state: st("s", playing: true, position: 11),
                     at: a0.advanced(by: .seconds(1)))
    #expect(d == .update(st("s", playing: true, position: 11)))
}

// MARK: - switching

@Test func arbiterSwitchesToTheMostRecentlyStartedSource() {
    var a = SourceArbiter()
    _ = a.update(sourceID: "spotify", state: st("s", playing: true), at: a0)
    let d = a.update(sourceID: "music", state: st("m", playing: true),
                     at: a0.advanced(by: .seconds(1)))
    #expect(d == .update(st("m", playing: true)))
}

@Test func arbiterFallsBackWhenTheChosenSourceStops() {
    var a = SourceArbiter()
    _ = a.update(sourceID: "spotify", state: st("s", playing: true), at: a0)
    _ = a.update(sourceID: "music", state: st("m", playing: true), at: a0.advanced(by: .seconds(1)))
    // music stops: selection changes back to spotify, so that IS a real update
    let d = a.update(sourceID: "music", state: nil, at: a0.advanced(by: .seconds(2)))
    #expect(d == .update(st("s", playing: true)))
}

@Test func arbiterHidesOnceEverySourceStops() {
    var a = SourceArbiter()
    _ = a.update(sourceID: "spotify", state: st("s", playing: true), at: a0)
    #expect(a.update(sourceID: "spotify", state: nil, at: a0.advanced(by: .seconds(1))) == .hide)
}

@Test func arbiterStartInstantOnlyResetsOnPauseToPlay() {
    var a = SourceArbiter()
    _ = a.update(sourceID: "spotify", state: st("s", playing: true), at: a0)
    _ = a.update(sourceID: "spotify", state: st("s", playing: true), at: a0.advanced(by: .seconds(5)))
    let d = a.update(sourceID: "music", state: st("m", playing: true),
                     at: a0.advanced(by: .seconds(6)))
    #expect(d == .update(st("m", playing: true)))
}
