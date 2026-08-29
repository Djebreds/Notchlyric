import Foundation

/// What the arbiter wants the overlay to do with an incoming report.
public enum ArbiterDecision: Equatable, Sendable {
    /// A fresh sample worth feeding to the clock.
    case update(PlaybackState)
    /// Bookkeeping only — the selected source has nothing new to say.
    case unchanged
    /// Nothing is playing anywhere.
    case hide
}

/// Chooses which player the overlay follows.
///
/// Sources poll independently, so a silent source reports just as often as a
/// playing one. Handing back the selected source's stored sample on those ticks
/// would replay a position up to a poll-interval old and drag the clock
/// backwards, so those reports resolve to `.unchanged` instead.
public struct SourceArbiter: Sendable {
    private struct Entry {
        var state: PlaybackState?
        var startedAt: ContinuousClock.Instant?
    }

    private var entries: [String: Entry] = [:]
    private var selected: String?

    public init() {}

    public mutating func update(sourceID: String,
                                state: PlaybackState?,
                                at instant: ContinuousClock.Instant) -> ArbiterDecision {
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

        let playing = entries.filter { $0.value.state?.isPlaying == true }
        guard let winner = playing.max(by: {
            ($0.value.startedAt ?? instant) < ($1.value.startedAt ?? instant)
        }), let winning = winner.value.state else {
            selected = nil
            return .hide
        }

        let previous = selected
        selected = winner.key

        // Fresh: the source that just reported is the one we follow.
        if winner.key == sourceID { return .update(winning) }
        // The selection moved to a different source, so the overlay must switch.
        if previous != winner.key { return .update(winning) }
        // Someone else ticked; our source's stored sample is stale.
        return .unchanged
    }
}
