import Testing
import Foundation
@testable import NotchLyricsCore

private let t0 = ContinuousClock.now

@Test func interpolatesWhilePlaying() {
    var c = PlaybackClock()
    c.ingest(position: 10, at: t0, isPlaying: true)
    #expect(abs(c.position(at: t0.advanced(by: .milliseconds(500))) - 10.5) < 0.01)
    #expect(abs(c.position(at: t0.advanced(by: .seconds(2))) - 12) < 0.01)
}

@Test func freezesWhilePaused() {
    var c = PlaybackClock()
    c.ingest(position: 10, at: t0, isPlaying: false)
    #expect(abs(c.position(at: t0.advanced(by: .seconds(5))) - 10) < 0.01)
}

@Test func smallDriftEasesInRatherThanJumping() {
    var c = PlaybackClock()
    c.ingest(position: 10, at: t0, isPlaying: true)
    let t1 = t0.advanced(by: .seconds(1))
    c.ingest(position: 11.1, at: t1, isPlaying: true)
    #expect(c.didSeek == false)
    #expect(abs(c.position(at: t1) - 11.0) < 0.01)
    #expect(abs(c.position(at: t1.advanced(by: .milliseconds(100))) - 11.15) < 0.01)
    #expect(abs(c.position(at: t1.advanced(by: .milliseconds(200))) - 11.3) < 0.01)
}

@Test func largeJumpIsTreatedAsSeekAndSnaps() {
    var c = PlaybackClock()
    c.ingest(position: 10, at: t0, isPlaying: true)
    let t1 = t0.advanced(by: .seconds(1))
    c.ingest(position: 90, at: t1, isPlaying: true)
    #expect(c.didSeek == true)
    #expect(abs(c.position(at: t1) - 90) < 0.01)
}

@Test func backwardSeekSnaps() {
    var c = PlaybackClock()
    c.ingest(position: 100, at: t0, isPlaying: true)
    let t1 = t0.advanced(by: .seconds(1))
    c.ingest(position: 5, at: t1, isPlaying: true)
    #expect(c.didSeek == true)
    #expect(abs(c.position(at: t1) - 5) < 0.01)
}

@Test func seekThresholdBoundary() {
    var c = PlaybackClock()
    c.ingest(position: 10, at: t0, isPlaying: true)
    let t1 = t0.advanced(by: .seconds(1))
    c.ingest(position: 11.3, at: t1, isPlaying: true)
    #expect(c.didSeek == true)
}

@Test func resumingAfterPauseRebases() {
    var c = PlaybackClock()
    c.ingest(position: 10, at: t0, isPlaying: false)
    let t1 = t0.advanced(by: .seconds(30))
    c.ingest(position: 10, at: t1, isPlaying: true)
    #expect(c.didSeek == false)
    #expect(abs(c.position(at: t1.advanced(by: .seconds(1))) - 11) < 0.01)
}

@Test func neverReturnsNegative() {
    var c = PlaybackClock()
    c.ingest(position: 0, at: t0, isPlaying: true)
    #expect(c.position(at: t0) >= 0)
}

@Test func positionIsZeroBeforeAnySample() {
    let c = PlaybackClock()
    #expect(c.position(at: t0) == 0)
}
