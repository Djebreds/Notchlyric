import Foundation

public protocol LyricsProvider: Sendable {
    var id: String { get }
    /// Returns nil when the provider simply has no synced lyrics for this track.
    /// Throws only on transport or decoding failure.
    func fetch(_ track: TrackQuery) async throws -> LyricsDocument?
}

public extension LyricsProvider {
    /// Rejects a candidate whose length disagrees with the playing track.
    func durationMatches(_ candidate: TimeInterval, _ track: TrackQuery,
                         tolerance: TimeInterval = 3) -> Bool {
        guard candidate > 0, track.duration > 0 else { return true }
        return abs(candidate - track.duration) <= tolerance
    }

    /// Parses, times and validates lyrics against the track that is playing.
    ///
    /// Returns nil when the result looks like a different recording: timings
    /// running past the end of the track, or CJK lyrics on a track whose own
    /// metadata is entirely Latin.
    func buildDocument(for track: TrackQuery, lrc: String) -> LyricsDocument? {
        let lines = WordTimingEstimator.apply(to: LRCParser.parse(lrc, trackDuration: track.duration))
        let doc = LyricsDocument(trackID: track.trackID, providerID: id, lines: lines)
        guard !doc.isEmpty else { return nil }

        guard timingsFit(lines, track: track) else { return nil }

        let lyricsAreCJK = CJKSegmenter.isCJK(lines.prefix(8).map(\.text).joined(separator: " "))
        guard LyricsMatch.scriptPlausible(lyricsAreCJK: lyricsAreCJK, track: track) else { return nil }

        return doc
    }
}
