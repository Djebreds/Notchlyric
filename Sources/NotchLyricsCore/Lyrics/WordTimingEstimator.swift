import Foundation

public enum WordTimingEstimator {
    /// Fills in per-word spans for lines whose tokens are marked estimated.
    ///
    /// Each word's share of the line is proportional to `text.count + 1`. The
    /// +1 keeps single-character words from collapsing to a near-zero span.
    public static func apply(to lines: [LyricLine]) -> [LyricLine] {
        lines.map { line in
            guard !line.words.isEmpty, line.words.contains(where: \.isEstimated) else { return line }

            let span = max(0, line.end - line.start)
            let weights = line.words.map { Double($0.text.count + 1) }
            let total = weights.reduce(0, +)
            guard total > 0, span > 0 else {
                var l = line
                l.words = l.words.map { var w = $0; w.start = line.start; w.end = line.start; return w }
                return l
            }

            var out = line.words
            var cursor = line.start
            for i in out.indices {
                let share = span * (weights[i] / total)
                out[i].start = cursor
                cursor += share
                out[i].end = cursor
            }
            out[out.count - 1].end = line.end   // absorb float drift
            var l = line
            l.words = out
            return l
        }
    }
}
