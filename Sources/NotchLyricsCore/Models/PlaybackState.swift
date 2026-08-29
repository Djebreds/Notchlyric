import Foundation

/// Player metadata that only matters for recitation detection.
public struct QuranHint: Equatable, Sendable {
    public var trackNumber: Int?
    public var genre: String?
    public init(trackNumber: Int?, genre: String?) {
        self.trackNumber = trackNumber; self.genre = genre
    }
}

public struct TrackQuery: Equatable, Sendable {
    public var trackID: String
    public var title: String
    public var artist: String
    public var album: String
    public var duration: TimeInterval   // seconds
    public var quranHint: QuranHint?

    public init(trackID: String, title: String, artist: String, album: String, duration: TimeInterval) {
        self.trackID = trackID; self.title = title; self.artist = artist
        self.album = album; self.duration = duration
    }
}

public struct PlaybackState: Equatable, Sendable {
    public var trackID: String
    public var title: String
    public var artist: String
    public var album: String
    public var durationMs: Int          // Spotify reports milliseconds
    public var position: TimeInterval   // seconds
    public var isPlaying: Bool
    public var trackNumber: Int?
    public var genre: String?
    /// Album art location: an http URL from Spotify, or a file URL for art
    /// extracted from a local Apple Music track. nil when there is none.
    public var artworkURL: String?

    public init(trackID: String, title: String, artist: String, album: String,
                durationMs: Int, position: TimeInterval, isPlaying: Bool,
                trackNumber: Int? = nil, genre: String? = nil,
                artworkURL: String? = nil) {
        self.trackID = trackID; self.title = title; self.artist = artist; self.album = album
        self.durationMs = durationMs; self.position = position; self.isPlaying = isPlaying
        self.trackNumber = trackNumber; self.genre = genre
        self.artworkURL = artworkURL
    }

    public var duration: TimeInterval { Double(durationMs) / 1000 }

    public var query: TrackQuery {
        var q = TrackQuery(trackID: trackID, title: title, artist: artist,
                           album: album, duration: duration)
        q.quranHint = QuranHint(trackNumber: trackNumber, genre: genre)
        return q
    }
}
