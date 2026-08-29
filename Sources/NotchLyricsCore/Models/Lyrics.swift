import Foundation

public struct WordToken: Equatable, Sendable, Codable {
    public var text: String
    public var start: TimeInterval
    public var end: TimeInterval
    public var isEstimated: Bool
    /// QCF glyph standing for the whole word; nil for Latin lyrics.
    public var glyph: String?
    /// Mushaf page whose QCF font renders `glyph`. Resolved per word because a
    /// verse can straddle a page boundary.
    public var fontPage: Int?

    public init(text: String, start: TimeInterval, end: TimeInterval, isEstimated: Bool,
                glyph: String? = nil, fontPage: Int? = nil) {
        self.text = text; self.start = start; self.end = end; self.isEstimated = isEstimated
        self.glyph = glyph; self.fontPage = fontPage
    }

    /// 0...1 progress of this word at `time`.
    public func progress(at time: TimeInterval) -> Double {
        guard end > start else { return time >= start ? 1 : 0 }
        return min(1, max(0, (time - start) / (end - start)))
    }
}

public struct LyricLine: Equatable, Sendable, Codable {
    public var start: TimeInterval
    public var end: TimeInterval
    public var words: [WordToken]

    public init(start: TimeInterval, end: TimeInterval, words: [WordToken]) {
        self.start = start; self.end = end; self.words = words
    }

    public var text: String { words.map(\.text).joined(separator: " ") }
    public var isBlank: Bool { words.isEmpty || text.trimmingCharacters(in: .whitespaces).isEmpty }
}

public struct LyricsDocument: Equatable, Sendable, Codable {
    public var trackID: String
    public var providerID: String
    public var script: Script
    public var lines: [LyricLine]

    public init(trackID: String, providerID: String, script: Script = .latin, lines: [LyricLine]) {
        self.trackID = trackID; self.providerID = providerID
        self.script = script; self.lines = lines
    }

    public var isEmpty: Bool { lines.allSatisfy(\.isBlank) }

    /// Index of the line active at `time`, or nil before the first line.
    public func index(at time: TimeInterval) -> Int? {
        guard !lines.isEmpty, time >= lines[0].start else { return nil }
        var lo = 0, hi = lines.count - 1, found = 0
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].start <= time { found = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return found
    }
}
