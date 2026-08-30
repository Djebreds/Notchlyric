import Testing
import Foundation
@testable import NotchLyricsCore

@Test func offsetStartsAtZero() {
    #expect(SyncOffset.clamp(0) == 0)
}

@Test func nudgingMovesByOneStep() {
    #expect(SyncOffset.nudged(0, by: .later) == SyncOffset.step)
    #expect(SyncOffset.nudged(0, by: .earlier) == -SyncOffset.step)
}

@Test func nudgesAccumulate() {
    var o: TimeInterval = 0
    for _ in 0..<4 { o = SyncOffset.nudged(o, by: .later) }
    #expect(abs(o - SyncOffset.step * 4) < 0.0001)
}

@Test func offsetIsClampedToASensibleRange() {
    #expect(SyncOffset.clamp(999) == SyncOffset.limit)
    #expect(SyncOffset.clamp(-999) == -SyncOffset.limit)
}

@Test func nudgingCannotEscapeTheLimit() {
    var o = SyncOffset.limit
    for _ in 0..<10 { o = SyncOffset.nudged(o, by: .later) }
    #expect(o == SyncOffset.limit)
}

@Test func aPositiveOffsetShowsLyricsLater() {
    // +0.5 means the lyric for a given moment is the one from half a second ago
    #expect(SyncOffset.apply(10, offset: 0.5) == 9.5)
}

@Test func aNegativeOffsetShowsLyricsEarlier() {
    #expect(SyncOffset.apply(10, offset: -0.5) == 10.5)
}

@Test func applyNeverReturnsNegativeTime() {
    #expect(SyncOffset.apply(0.1, offset: 2) == 0)
}

@Test func labelReadsAsSecondsWithSign() {
    #expect(SyncOffset.label(0) == "0.00s")
    #expect(SyncOffset.label(0.25).hasPrefix("+"))
    #expect(SyncOffset.label(-0.25).hasPrefix("-"))
}
