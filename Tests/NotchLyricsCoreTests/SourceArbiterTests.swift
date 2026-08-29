import Testing
import Foundation
@testable import NotchLyricsCore

private let a0 = ContinuousClock.now

private func st(_ id: String, playing: Bool) -> PlaybackState {
    PlaybackState(trackID: id, title: id, artist: "a", album: "b",
                  durationMs: 1000, position: 0, isPlaying: playing)
}

@Test func arbiterReturnsNilWhenNothingReported() {
    var a = SourceArbiter()
    #expect(a.update(sourceID: "spotify", state: nil, at: a0) == nil)
}

@Test func arbiterReturnsTheOnlyPlayingSource() {
    var a = SourceArbiter()
    _ = a.update(sourceID: "music", state: nil, at: a0)
    let out = a.update(sourceID: "spotify", state: st("s", playing: true), at: a0)
    #expect(out?.trackID == "s")
}

@Test func arbiterIgnoresPausedSources() {
    var a = SourceArbiter()
    #expect(a.update(sourceID: "spotify", state: st("s", playing: false), at: a0) == nil)
}

@Test func arbiterPrefersTheMostRecentToStart() {
    var a = SourceArbiter()
    _ = a.update(sourceID: "spotify", state: st("s", playing: true), at: a0)
    let out = a.update(sourceID: "music", state: st("m", playing: true),
                       at: a0.advanced(by: .seconds(1)))
    #expect(out?.trackID == "m")
}

@Test func arbiterFallsBackWhenTheChosenSourceStops() {
    var a = SourceArbiter()
    _ = a.update(sourceID: "spotify", state: st("s", playing: true), at: a0)
    _ = a.update(sourceID: "music", state: st("m", playing: true), at: a0.advanced(by: .seconds(1)))
    let out = a.update(sourceID: "music", state: nil, at: a0.advanced(by: .seconds(2)))
    #expect(out?.trackID == "s")
}

@Test func arbiterReturnsNilOnceEverySourceStops() {
    var a = SourceArbiter()
    _ = a.update(sourceID: "spotify", state: st("s", playing: true), at: a0)
    #expect(a.update(sourceID: "spotify", state: nil, at: a0.advanced(by: .seconds(1))) == nil)
}

@Test func arbiterStartInstantOnlyResetsOnPauseToPlay() {
    var a = SourceArbiter()
    _ = a.update(sourceID: "spotify", state: st("s", playing: true), at: a0)
    _ = a.update(sourceID: "spotify", state: st("s", playing: true), at: a0.advanced(by: .seconds(5)))
    let out = a.update(sourceID: "music", state: st("m", playing: true),
                       at: a0.advanced(by: .seconds(6)))
    #expect(out?.trackID == "m")
}

@Test func arbiterKeepsUpdatingTheChosenSourcePosition() {
    var a = SourceArbiter()
    _ = a.update(sourceID: "music", state: st("m", playing: true), at: a0)
    var moved = st("m", playing: true); moved.position = 12
    let out = a.update(sourceID: "music", state: moved, at: a0.advanced(by: .seconds(1)))
    #expect(out?.position == 12)
}
