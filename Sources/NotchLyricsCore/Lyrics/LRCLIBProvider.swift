import Foundation

public struct LRCLIBProvider: LyricsProvider {
    public let id = "lrclib"
    private let http: any HTTPFetching

    public init(http: any HTTPFetching) { self.http = http }

    private struct Payload: Decodable {
        let instrumental: Bool?
        let duration: Double?
        let syncedLyrics: String?
    }

    public func fetch(_ track: TrackQuery) async throws -> LyricsDocument? {
        var c = URLComponents(string: "https://lrclib.net/api/get")!
        c.queryItems = [
            .init(name: "track_name", value: track.title),
            .init(name: "artist_name", value: track.artist),
            .init(name: "album_name", value: track.album),
            // LRCLIB expects whole seconds, not milliseconds.
            .init(name: "duration", value: String(Int(track.duration.rounded()))),
        ]
        guard let url = c.url else { return nil }

        let (data, status) = try await http.get(url, headers: [:])
        guard status == 200 else { return nil }

        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.instrumental != true,
              let lrc = payload.syncedLyrics, !lrc.isEmpty,
              durationMatches(payload.duration ?? 0, track)
        else { return nil }

        return buildDocument(trackID: track.trackID, lrc: lrc, duration: track.duration)
    }
}
