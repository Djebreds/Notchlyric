import Foundation

/// lrcmux, an aggregator fronting several catalogues behind one call.
///
/// Its distinguishing feature is `meta.level`: when it reports `"word"` the
/// response carries measured per-word timings, so emphasis is exact rather than
/// distributed across the line by character weight the way every other song
/// source has to be.
public struct LrcmuxProvider: LyricsProvider {
    public let id = "lrcmux"
    private let http: any HTTPFetching
    private let baseURL: String

    public init(http: any HTTPFetching, baseURL: String = "https://api.lrcmux.dev") {
        self.http = http
        self.baseURL = baseURL
    }

    private struct Response: Decodable {
        struct Meta: Decodable { let level: String? }
        struct Word: Decodable { let text: String?; let start: Int?; let end: Int? }
        struct Line: Decodable {
            let text: String?
            let start: Int?
            let end: Int?
            let words: [Word]?
        }
        let meta: Meta?
        let lines: [Line]?
    }

    public func fetch(_ track: TrackQuery) async throws -> LyricsDocument? {
        var c = URLComponents(string: baseURL + "/get")!
        c.queryItems = [
            .init(name: "artist", value: track.artist),
            .init(name: "title", value: track.title),
            .init(name: "album", value: track.album),
            .init(name: "duration", value: String(Int(track.duration.rounded()))),
        ]
        guard let url = c.url else { return nil }

        let (data, status) = try await http.get(url, headers: [:])
        // A miss is a plain 404 here.
        guard status == 200 else { return nil }

        let payload = try JSONDecoder().decode(Response.self, from: data)
        guard let rawLines = payload.lines, !rawLines.isEmpty else { return nil }

        let lines = build(rawLines, wordLevel: payload.meta?.level == "word", track: track)
        guard !lines.isEmpty else { return nil }

        // Same sanity check as every other source: an English track does not
        // have Chinese lyrics, however confident the aggregator is.
        let sample = lines.prefix(8).map(\.text).joined(separator: " ")
        guard LyricsMatch.scriptPlausible(lyricsAreCJK: CJKSegmenter.isCJK(sample), track: track)
        else { return nil }

        return LyricsDocument(trackID: track.trackID, providerID: id, lines: lines)
    }

    private func build(_ raw: [Response.Line],
                       wordLevel: Bool,
                       track: TrackQuery) -> [LyricLine] {
        var out: [LyricLine] = []
        var needsEstimate = false

        for line in raw {
            guard let text = line.text, let start = line.start else { continue }
            let lineStart = Double(start) / 1000
            let lineEnd = Double(line.end ?? start) / 1000

            let measured = (line.words ?? []).compactMap { w -> WordToken? in
                guard wordLevel, let t = w.text, let s = w.start, let e = w.end,
                      !t.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                return WordToken(text: t, start: Double(s) / 1000, end: Double(e) / 1000,
                                 isEstimated: false)
            }

            if !measured.isEmpty {
                out.append(LyricLine(start: lineStart, end: lineEnd, words: measured))
                continue
            }

            // Only line timings offered: split the text and let the estimator
            // fill the spans, exactly as the LRC path does.
            let segments = CJKSegmenter.isCJK(text)
                ? CJKSegmenter.segment(text).map {
                    WordToken(text: $0.romaji, start: lineStart, end: lineEnd,
                              isEstimated: true, original: $0.text)
                }
                : text.split(separator: " ").map {
                    WordToken(text: String($0), start: lineStart, end: lineEnd, isEstimated: true)
                }
            guard !segments.isEmpty else { continue }
            needsEstimate = true
            out.append(LyricLine(start: lineStart, end: lineEnd, words: segments))
        }

        return needsEstimate ? WordTimingEstimator.apply(to: out) : out
    }
}
