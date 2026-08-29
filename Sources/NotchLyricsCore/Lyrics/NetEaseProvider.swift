import Foundation

/// NetEase Cloud Music. No authentication required, but a Referer header is
/// mandatory or the endpoint rejects the request (spec §1.5).
public struct NetEaseProvider: LyricsProvider {
    public let id = "netease"
    private let http: any HTTPFetching

    public init(http: any HTTPFetching) { self.http = http }

    private static let headers = [
        "Referer": "https://music.163.com",
        "Content-Type": "application/x-www-form-urlencoded",
    ]

    private struct SearchResponse: Decodable {
        struct Result: Decodable { let songs: [Song]? }
        struct Song: Decodable {
            let id: Int
            let name: String
            let duration: Int      // milliseconds
        }
        let result: Result?
    }

    private struct LyricResponse: Decodable {
        struct LRC: Decodable { let lyric: String? }
        let lrc: LRC?
    }

    public func fetch(_ track: TrackQuery) async throws -> LyricsDocument? {
        guard let songID = try await search(track) else { return nil }

        guard let url = URL(string:
            "https://music.163.com/api/song/lyric?id=\(songID)&lv=1&kv=1&tv=-1")
        else { return nil }

        let (data, status) = try await http.get(url, headers: Self.headers)
        guard status == 200 else { return nil }

        let payload = try JSONDecoder().decode(LyricResponse.self, from: data)
        guard let lrc = payload.lrc?.lyric, !lrc.isEmpty else { return nil }

        return buildDocument(trackID: track.trackID, lrc: lrc, duration: track.duration)
    }

    private func search(_ track: TrackQuery) async throws -> Int? {
        guard let url = URL(string: "https://music.163.com/api/search/get/") else { return nil }

        var form = URLComponents()
        form.queryItems = [
            .init(name: "s", value: "\(track.title) \(track.artist)"),
            .init(name: "type", value: "1"),
            .init(name: "offset", value: "0"),
            .init(name: "limit", value: "5"),
        ]
        let body = Data((form.percentEncodedQuery ?? "").utf8)

        let (data, status) = try await http.post(url, headers: Self.headers, body: body)
        guard status == 200 else { return nil }

        let payload = try JSONDecoder().decode(SearchResponse.self, from: data)
        guard let songs = payload.result?.songs else { return nil }

        // NetEase durations are milliseconds; compare in seconds.
        return songs.first { durationMatches(Double($0.duration) / 1000, track) }?.id
    }
}
