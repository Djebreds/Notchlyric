import Foundation

public enum WordTimingEstimator {
    /// Used when a document has too few lines to measure a rate.
    /// Derived from 552 lines across 10 songs (p20 of gap ÷ characters).
    public static let fallbackSecondsPerCharacter: Double = 0.075
    public static let minimumSecondsPerCharacter: Double = 0.030
    public static let maximumSecondsPerCharacter: Double = 0.160

    /// Floor so a two-word line still gets a readable sweep.
    public static let minimumSungDuration: TimeInterval = 0.45

    /// Lines shorter than this are markers like "♪" and skew the rate.
    private static let minimumSampleLength = 6
    private static let minimumSampleCount = 5
    /// Dense passages sit at the low end of the distribution; the p20 of
    /// gap ÷ characters approximates continuous singing for this song.
    private static let ratePercentile = 0.20

    /// Fills in per-word spans for lines whose tokens are marked estimated.
    ///
    /// A line's gap runs to the *next line's start*, which usually includes
    /// dead air after the vocal ends — measured at 29% of the gap for a median
    /// line and 51% at p75. Spreading words across the whole gap therefore
    /// makes emphasis drift progressively behind the vocal and snap back each
    /// line. Words are instead distributed over an estimated sung duration,
    /// after which the line simply stays on screen fully sung.
    public static func apply(to lines: [LyricLine]) -> [LyricLine] {
        let rate = secondsPerCharacter(for: lines)

        return lines.map { line in
            guard !line.words.isEmpty, line.words.contains(where: \.isEstimated) else { return line }

            let gap = max(0, line.end - line.start)
            let weights = line.words.map { Double($0.text.count + 1) }
            let total = weights.reduce(0, +)
            guard total > 0, gap > 0 else {
                var l = line
                l.words = l.words.map { var w = $0; w.start = line.start; w.end = line.start; return w }
                return l
            }

            let characters = Double(line.words.reduce(0) { $0 + $1.text.count })
            let sung = min(gap, max(minimumSungDuration, characters * rate))

            var out = line.words
            var cursor = line.start
            for i in out.indices {
                let share = sung * (weights[i] / total)
                out[i].start = cursor
                cursor += share
                out[i].end = cursor
            }
            out[out.count - 1].end = line.start + sung   // absorb float drift
            var l = line
            l.words = out
            return l
        }
    }

    /// This song's own singing rate, in seconds per character.
    ///
    /// Rates vary about 2x between tracks (a fast pop song against a ballad),
    /// so a global constant cannot fit both; it is measured per document.
    public static func secondsPerCharacter(for lines: [LyricLine]) -> Double {
        var samples: [Double] = []
        for line in lines {
            let characters = line.words.reduce(0) { $0 + $1.text.count }
            let gap = line.end - line.start
            guard characters >= minimumSampleLength, gap > 0 else { continue }
            samples.append(gap / Double(characters))
        }

        guard samples.count >= minimumSampleCount else { return fallbackSecondsPerCharacter }
        samples.sort()
        let index = min(samples.count - 1, Int(Double(samples.count) * ratePercentile))
        return min(maximumSecondsPerCharacter, max(minimumSecondsPerCharacter, samples[index]))
    }
}
