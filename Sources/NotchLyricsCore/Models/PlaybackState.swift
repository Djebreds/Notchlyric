import Foundation

public struct TrackQuery: Equatable, Sendable {
    public var trackID: String
    public var title: String
    public var artist: String
    public var album: String
    public var duration: TimeInterval   // seconds

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

    public init(trackID: String, title: String, artist: String, album: String,
                durationMs: Int, position: TimeInterval, isPlaying: Bool) {
        self.trackID = trackID; self.title = title; self.artist = artist; self.album = album
        self.durationMs = durationMs; self.position = position; self.isPlaying = isPlaying
    }

    public var duration: TimeInterval { Double(durationMs) / 1000 }

    public var query: TrackQuery {
        TrackQuery(trackID: trackID, title: title, artist: artist, album: album, duration: duration)
    }
}
