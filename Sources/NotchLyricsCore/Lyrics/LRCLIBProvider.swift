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
        // The album a player reports is often the single, while the timed entry
        // sits under the studio album, so two attempts are made. The second is
        // used when the first has no timestamps at all, and also when the
        // first's timings clearly do not belong to this recording.
        let withAlbum = try await syncedLyrics(for: track, includeAlbum: true)
        if let withAlbum, fits(withAlbum, track) {
            return buildDocument(for: track, lrc: withAlbum)
        }

        let withoutAlbum = track.album.isEmpty
            ? nil
            : try await syncedLyrics(for: track, includeAlbum: false)
        if let withoutAlbum, fits(withoutAlbum, track) {
            return buildDocument(for: track, lrc: withoutAlbum)
        }

        // Neither fits cleanly. A poorly-tailed entry still beats nothing, so
        // fall back rather than reject — choosing between candidates is safe,
        // rejecting the only candidate is not.
        if let withAlbum { return buildDocument(for: track, lrc: withAlbum) }
        if let withoutAlbum { return buildDocument(for: track, lrc: withoutAlbum) }
        return nil
    }

    /// Whether an entry's timings plausibly belong to this recording.
    ///
    /// Used only to choose between two candidates, never to reject outright:
    /// real files carry trailing credit lines past the audio, so a generous
    /// margin keeps a good entry from losing to nothing.
    private func fits(_ lrc: String, _ track: TrackQuery) -> Bool {
        guard track.duration > 0 else { return true }
        let lines = LRCParser.parse(lrc, trackDuration: track.duration)
        guard let last = lines.map(\.start).max() else { return false }
        return last <= track.duration + 15
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
