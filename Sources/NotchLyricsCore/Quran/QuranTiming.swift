import Foundation

public enum QuranTiming {
    /// One verse's word segments. Values are milliseconds, absolute within the
    /// chapter audio file — not relative to the verse.
    public struct VerseTiming: Sendable {
        public let verseKey: String
        public let segments: [[Int]]
        public init(verseKey: String, segments: [[Int]]) {
            self.verseKey = verseKey; self.segments = segments
        }
    }

    /// One word of text. `position` is 1-based within its verse and is what
    /// segment tuples index by.
    public struct WordText: Sendable {
        public let position: Int
        public let textUthmani: String
        public let glyph: String?
        public let page: Int?
        public let lineNumber: Int?
        public init(position: Int, textUthmani: String, glyph: String?,
                    page: Int?, lineNumber: Int?) {
            self.position = position; self.textUthmani = textUthmani
            self.glyph = glyph; self.page = page; self.lineNumber = lineNumber
        }
    }

    /// Builds display lines grouped the way a printed mushaf breaks them.
    ///
    /// Verses are unbounded — the longest is 128 words — but mushaf lines are
    /// not, measuring median 9 and max 14 words. Grouping by (page, line) keeps
    /// every display unit small enough for the overlay.
    public static func mushafLines(timings: [VerseTiming],
                                   words: [String: [WordText]]) -> [LyricLine] {
        struct Key: Hashable { let page: Int; let line: Int }
        var grouped: [Key: [WordToken]] = [:]

        for timing in timings {
            guard let verseWords = words[timing.verseKey] else { continue }
            let byPosition = Dictionary(verseWords.map { ($0.position, $0) },
                                        uniquingKeysWith: { first, _ in first })

            for segment in timing.segments {
                // A small fraction of real segments are truncated tuples.
                guard segment.count == 3, let word = byPosition[segment[0]] else { continue }

                let token = WordToken(text: word.textUthmani,
                                      start: Double(segment[1]) / 1000,
                                      end: Double(segment[2]) / 1000,
                                      isEstimated: false,          // measured, not inferred
                                      glyph: word.glyph,
                                      fontPage: word.page)
                let key = Key(page: word.page ?? 0, line: word.lineNumber ?? 0)
                grouped[key, default: []].append(token)
            }
        }

        return grouped.values.compactMap { tokens -> LyricLine? in
            guard !tokens.isEmpty else { return nil }
            let ordered = tokens.sorted { $0.start < $1.start }
            return LyricLine(start: ordered.first!.start, end: ordered.last!.end, words: ordered)
        }
        .sorted { $0.start < $1.start }
    }
}
