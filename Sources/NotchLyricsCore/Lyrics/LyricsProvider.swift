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

    func buildDocument(trackID: String, lrc: String, duration: TimeInterval) -> LyricsDocument? {
        let lines = WordTimingEstimator.apply(to: LRCParser.parse(lrc, trackDuration: duration))
        let doc = LyricsDocument(trackID: trackID, providerID: id, lines: lines)
        return doc.isEmpty ? nil : doc
    }
}
