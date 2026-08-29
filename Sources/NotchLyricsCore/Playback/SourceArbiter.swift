import Foundation

/// Chooses which player the overlay follows.
///
/// macOS usually pauses one media app when another starts, so ties are rare —
/// but when both report playing, the one that most recently transitioned from
/// not-playing to playing wins.
public struct SourceArbiter: Sendable {
    private struct Entry {
        var state: PlaybackState?
        var startedAt: ContinuousClock.Instant?
    }

    private var entries: [String: Entry] = [:]

    public init() {}

    public mutating func update(sourceID: String,
                                state: PlaybackState?,
                                at instant: ContinuousClock.Instant) -> PlaybackState? {
        let wasPlaying = entries[sourceID]?.state?.isPlaying ?? false
        let isPlaying = state?.isPlaying ?? false

        var entry = entries[sourceID] ?? Entry(state: nil, startedAt: nil)
        entry.state = state
        if isPlaying && !wasPlaying {
            entry.startedAt = instant          // only a fresh start resets the clock
        } else if !isPlaying {
            entry.startedAt = nil
        }
        entries[sourceID] = entry

        let playing = entries.values.filter { $0.state?.isPlaying == true }
        guard !playing.isEmpty else { return nil }
        return playing.max { lhs, rhs in
            (lhs.startedAt ?? instant) < (rhs.startedAt ?? instant)
        }?.state
    }
}
