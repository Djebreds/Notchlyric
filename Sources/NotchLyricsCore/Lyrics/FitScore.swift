import Foundation

/// Scores how well a candidate's timings match the recording being played.
///
/// Sources routinely hold a *different* recording of the same song — a live
/// cut, a remaster, a shorter edit — and its timings drift against the audio
/// even though the words are right. There is no way to verify alignment
/// without the audio itself, but the track's duration is a usable proxy: a
/// candidate whose lyrics run to the end of the track, and no further, is
/// almost always the one timed against it.
public enum FitScore {
    /// A candidate at or above this is taken without consulting other sources.
    public static let goodEnough: Double = 0.75
    /// Trailing credit lines commonly sit a little past the audio.
    private static let tailTolerance: TimeInterval = 15
    /// Small bonus so measured word timings win between equally aligned
    /// candidates — never enough to outrank better alignment.
    private static let measuredBonus: Double = 0.05

    public static func of(_ doc: LyricsDocument, track: TrackQuery) -> Double {
        guard !doc.lines.isEmpty else { return 0 }

        let measured = doc.lines.flatMap(\.words).contains { !$0.isEstimated }
        let bonus = measured ? measuredBonus : 0

        // Without a duration there is nothing to compare against, so accept.
        guard track.duration > 0 else { return min(1, 0.9 + bonus) }

        let last = doc.lines.map(\.end).max() ?? 0
        if last > track.duration + tailTolerance {
            // Running past the end means a longer recording. The further past,
            // the less likely it belongs to this one.
            let over = last - track.duration
            return max(0, (1 - min(1, over / track.duration)) * 0.5) + bonus
        }

        // Otherwise reward covering the track: an entry ending near the end is
        // far more likely to be the right recording than one stopping early.
        return min(1, last / track.duration) * 0.9 + bonus
    }

    public static func isGoodEnough(_ score: Double) -> Bool { score >= goodEnough }
}
