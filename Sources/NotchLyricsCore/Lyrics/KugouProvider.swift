import Foundation

/// Kugou Music. No authentication required.
///
/// Three steps: find the song, ask which lyric records match it, then download
/// one. Its catalogue overlaps LRCLIB and NetEase only partly, which is the
/// point of having it.
public struct KugouProvider: LyricsProvider {
    public let id = "kugou"
    private let http: any HTTPFetching

    public init(http: any HTTPFetching) { self.http = http }

    private static let headers = [
        "Referer": "https://www.kugou.com",
    ]

    private struct SearchResponse: Decodable {
        struct Data: Decodable { let info: [Song]? }
        struct Song: Decodable {
            let hash: String
            let songname: String
            let singername: String
            let duration: Int        // seconds
        }
        let data: Data?
    }

    private struct CandidateResponse: Decodable {
        struct Candidate: Decodable { let id: String; let accesskey: String }
        let candidates: [Candidate]?
    }

    private struct DownloadResponse: Decodable {
        let content: String?
    }

    public func fetch(_ track: TrackQuery) async throws -> LyricsDocument? {
        guard let song = try await findSong(track) else { return nil }
        guard let candidate = try await findLyric(hash: song.hash,
                                                 durationMs: song.duration * 1000)
        else { return nil }
        guard let lrc = try await download(candidate) else { return nil }
        return buildDocument(for: track, lrc: lrc)
    }

    private func findSong(_ track: TrackQuery) async throws -> SearchResponse.Song? {
        var c = URLComponents(string: "https://mobileservice.kugou.com/api/v3/search/song")!
        c.queryItems = [
            .init(name: "keyword", value: "\(track.title) \(track.artist)"),
            .init(name: "page", value: "1"),
            .init(name: "pagesize", value: "5"),
        ]
        guard let url = c.url else { return nil }

        let (data, status) = try await http.get(url, headers: Self.headers)
        guard status == 200 else { return nil }
        let payload = try JSONDecoder().decode(SearchResponse.self, from: data)

        // Same guards as every other provider: a variant recording or a
        // different artist is worse than showing nothing.
        return (payload.data?.info ?? []).first { song in
            durationMatches(Double(song.duration), track)
                && LyricsMatch.isSameRecording(candidate: song.songname, query: track.title)
                && LyricsMatch.isSameArtist(candidate: song.singername, query: track.artist)
        }
    }

    private func findLyric(hash: String, durationMs: Int) async throws
        -> CandidateResponse.Candidate? {
        var c = URLComponents(string: "https://krcs.kugou.com/search")!
        c.queryItems = [
            .init(name: "ver", value: "1"),
            .init(name: "man", value: "yes"),
            .init(name: "client", value: "mobi"),
            .init(name: "keyword", value: ""),
            .init(name: "duration", value: String(durationMs)),
            .init(name: "hash", value: hash),
        ]
        guard let url = c.url else { return nil }

        let (data, status) = try await http.get(url, headers: Self.headers)
        guard status == 200 else { return nil }
        return try JSONDecoder().decode(CandidateResponse.self, from: data).candidates?.first
    }

    private func download(_ candidate: CandidateResponse.Candidate) async throws -> String? {
        var c = URLComponents(string: "https://lyrics.kugou.com/download")!
        c.queryItems = [
            .init(name: "ver", value: "1"),
            .init(name: "client", value: "pc"),
            .init(name: "id", value: candidate.id),
            .init(name: "accesskey", value: candidate.accesskey),
            .init(name: "fmt", value: "lrc"),
            .init(name: "charset", value: "utf8"),
        ]
        guard let url = c.url else { return nil }

        let (data, status) = try await http.get(url, headers: Self.headers)
        guard status == 200 else { return nil }

        // The body arrives base64-encoded.
        guard let encoded = try JSONDecoder().decode(DownloadResponse.self, from: data).content,
              let decoded = Data(base64Encoded: encoded),
              let lrc = String(data: decoded, encoding: .utf8), !lrc.isEmpty
        else { return nil }
        return lrc
    }
}
