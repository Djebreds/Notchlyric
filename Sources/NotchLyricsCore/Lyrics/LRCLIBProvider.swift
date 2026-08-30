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
        // The album Spotify reports is often the single, while the timed entry
        // sits under the studio album, so an exact match can return an entry
        // that only has plain text. Retry without the album, keeping duration
        // so the match stays constrained.
        if let lrc = try await syncedLyrics(for: track, includeAlbum: true) {
            return buildDocument(for: track, lrc: lrc)
        }
        if !track.album.isEmpty,
           let lrc = try await syncedLyrics(for: track, includeAlbum: false) {
            return buildDocument(for: track, lrc: lrc)
        }
        return nil
    }

    private func syncedLyrics(for track: TrackQuery, includeAlbum: Bool) async throws -> String? {
        var c = URLComponents(string: "https://lrclib.net/api/get")!
        var items: [URLQueryItem] = [
            .init(name: "track_name", value: track.title),
            .init(name: "artist_name", value: track.artist),
        ]
        if includeAlbum { items.append(.init(name: "album_name", value: track.album)) }
        // LRCLIB expects whole seconds, not milliseconds.
        items.append(.init(name: "duration", value: String(Int(track.duration.rounded()))))
        c.queryItems = items
        guard let url = c.url else { return nil }

        let (data, status) = try await http.get(url, headers: [:])
        guard status == 200 else { return nil }

        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.instrumental != true,
              let lrc = payload.syncedLyrics, !lrc.isEmpty,
              durationMatches(payload.duration ?? 0, track)
        else { return nil }
        return lrc
    }
}
