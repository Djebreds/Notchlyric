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
        /// Position in the printed mushaf: verse order, then word order within it.
        struct Placed { let order: (Int, Int); let token: WordToken }
        var grouped: [Key: [Placed]] = [:]

        // `timings` arrives in recitation order, so its index is the verse order.
        for (verseOrder, timing) in timings.enumerated() {
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
                grouped[key, default: []].append(
                    Placed(order: (verseOrder, segment[0]), token: token))
            }
        }

        return grouped.values.compactMap { placed -> LyricLine? in
            guard !placed.isEmpty else { return nil }

            // Order by the printed mushaf, never by the clock. Recorded segment
            // timings are occasionally out of sequence, and sorting by time
            // would rearrange the words on screen — making the emphasis appear
            // to jump backwards even though the recitation is moving forward.
            let ordered = placed
                .sorted { ($0.order.0, $0.order.1) < ($1.order.0, $1.order.1) }
                .map(\.token)

            var tokens = ordered
            for i in 1..<max(tokens.count, 1) where tokens.count > 1 {
                // Clamp so emphasis advances monotonically through the line.
                tokens[i].start = max(tokens[i].start, tokens[i - 1].start)
                tokens[i].end = max(tokens[i].end, tokens[i].start)
                tokens[i].end = max(tokens[i].end, tokens[i - 1].end)
            }

            let start = tokens.map(\.start).min() ?? 0
            let end = tokens.map(\.end).max() ?? start
            return LyricLine(start: start, end: end, words: tokens)
        }
        .sorted { $0.start < $1.start }
    }
}
