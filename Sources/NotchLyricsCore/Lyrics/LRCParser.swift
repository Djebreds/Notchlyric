import Foundation

public enum LRCParser {
    /// Fallback span for a final line when the track duration is unknown.
    static let trailingLineFallback: TimeInterval = 4

    // Regex is not Sendable but matching is read-only, so these are safe to share.
    nonisolated(unsafe) private static let timeTag = /\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]/
    nonisolated(unsafe) private static let wordTag = /<(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?>/
    nonisolated(unsafe) private static let offsetTag = /\[offset:\s*([+-]?\d+)\s*\]/
    nonisolated(unsafe) private static let metadataTag = /^\[[a-zA-Z#]+:.*\]$/
    nonisolated(unsafe) private static let creditLine = /^(作词|作曲|编曲|制作人|出品|录音|混音)\s*[:：]/

    public static func parse(_ text: String, trackDuration: TimeInterval) -> [LyricLine] {
        var offset: TimeInterval = 0
        if let m = text.firstMatch(of: offsetTag), let ms = Int(m.1) {
            // A positive offset tag means lyrics should appear earlier.
            offset = -Double(ms) / 1000
        }

        var collected: [(start: TimeInterval, words: [WordToken], estimated: Bool)] = []

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            let stamps = line.matches(of: timeTag)
            guard !stamps.isEmpty, stamps[0].range.lowerBound == line.startIndex else {
                continue    // no leading timestamp -> not a lyric line
            }

            // Content begins after the final leading timestamp.
            var contentStart = line.startIndex
            var times: [TimeInterval] = []
            for s in stamps {
                guard s.range.lowerBound == contentStart else { break }
                times.append(seconds(minutes: s.1, seconds: s.2, fraction: s.3))
                contentStart = s.range.upperBound
            }
            guard !times.isEmpty else { continue }

            let content = String(line[contentStart...]).trimmingCharacters(in: .whitespaces)
            if content.firstMatch(of: metadataTag) != nil { continue }
            if content.firstMatch(of: creditLine) != nil { continue }

            let (words, estimated) = parseWords(content)
            for t in times {
                collected.append((start: max(0, t + offset), words: words, estimated: estimated))
            }
        }

        guard !collected.isEmpty else { return [] }
        collected.sort { $0.start < $1.start }

        return collected.enumerated().map { i, item in
            let end: TimeInterval
            if i + 1 < collected.count {
                end = collected[i + 1].start
            } else if trackDuration > item.start {
                end = trackDuration
            } else {
                end = item.start + trailingLineFallback
            }
            var words = item.words
            if item.estimated {
                // Real spans are filled in by WordTimingEstimator.
                words = words.map { var w = $0; w.start = item.start; w.end = end; return w }
            }
            return LyricLine(start: item.start, end: end, words: words)
        }
    }

    /// Returns tokens and whether their timings still need estimating.
    private static func parseWords(_ content: String) -> ([WordToken], Bool) {
        let tags = content.matches(of: wordTag)
        if tags.isEmpty {
            // CJK has no spaces, so splitting on whitespace would yield about
            // one "word" per line and per-word tracking would not work at all.
            if CJKSegmenter.isCJK(content) {
                let words = CJKSegmenter.segment(content).map {
                    WordToken(text: $0.romaji, start: 0, end: 0, isEstimated: true,
                              original: $0.text)
                }
                if !words.isEmpty { return (words, true) }
            }
            let words = content.split(separator: " ").map {
                WordToken(text: String($0), start: 0, end: 0, isEstimated: true)
            }
            return (words, true)
        }

        var tokens: [WordToken] = []
        for (i, tag) in tags.enumerated() {
            let start = seconds(minutes: tag.1, seconds: tag.2, fraction: tag.3)
            let textEnd = i + 1 < tags.count ? tags[i + 1].range.lowerBound : content.endIndex
            let word = String(content[tag.range.upperBound..<textEnd])
                .trimmingCharacters(in: .whitespaces)
            guard !word.isEmpty else { continue }
            tokens.append(WordToken(text: word, start: start, end: start, isEstimated: false))
        }
        for i in tokens.indices {
            tokens[i].end = i + 1 < tokens.count ? tokens[i + 1].start : tokens[i].start + 0.5
        }
        return (tokens, false)
    }

    private static func seconds(minutes: Substring, seconds sec: Substring,
                                fraction: Substring?) -> TimeInterval {
        let m = Double(minutes) ?? 0
        let s = Double(sec) ?? 0
        var f: Double = 0
        if let fraction, let raw = Double(fraction) {
            f = raw / pow(10, Double(fraction.count))
        }
        return m * 60 + s + f
    }
}
