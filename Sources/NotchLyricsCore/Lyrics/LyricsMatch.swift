import Foundation

/// Guards against a provider returning a different recording than the one
/// playing.
///
/// Duration alone is not enough: a live cut can land within seconds of the
/// studio version, and a search may return an unrelated song entirely.
public enum LyricsMatch {
    /// Suffixes that mark a different recording of the same song.
    private static let variantMarkers = [
        "live", "remix", "acoustic", "instrumental", "karaoke", "cover",
        "demo", "remaster", "remastered", "reprise", "edit", "session",
    ]

    static func normalise(_ s: String) -> String {
        s.lowercased()
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }
            .map(String.init)
            .joined()
            .split(separator: " ")
            .joined(separator: " ")
    }

    private static func markers(in text: String) -> Set<String> {
        let words = Set(normalise(text).split(separator: " ").map(String.init))
        return Set(variantMarkers).intersection(words)
    }

    /// True when a candidate title names the same recording as the query.
    ///
    /// A candidate carrying a variant marker the query does not ask for is a
    /// different recording, however close its duration.
    public static func isSameRecording(candidate: String, query: String) -> Bool {
        // A marker the candidate carries but the query never asked for means a
        // different recording, however close the durations.
        let unwanted = markers(in: candidate).subtracting(markers(in: query))
        guard unwanted.isEmpty else { return false }
        let c = normalise(candidate), q = normalise(query)
        return c == q || c.contains(q) || q.contains(c)
    }

    public static func isSameArtist(candidate: String, query: String) -> Bool {
        let c = normalise(candidate), q = normalise(query)
        guard !c.isEmpty, !q.isEmpty else { return false }
        return c == q || c.contains(q) || q.contains(c)
    }

    /// Rejects CJK lyrics for a track whose own metadata is entirely Latin.
    ///
    /// This is the catch-all for a search returning an unrelated song: an
    /// English rock track does not have Chinese lyrics.
    public static func scriptPlausible(lyricsAreCJK: Bool, track: TrackQuery) -> Bool {
        guard lyricsAreCJK else { return true }
        return CJKSegmenter.isCJK(track.title)
            || CJKSegmenter.isCJK(track.artist)
            || CJKSegmenter.isCJK(track.album)
    }
}
