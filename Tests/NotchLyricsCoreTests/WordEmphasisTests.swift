import Testing
import Foundation
@testable import NotchLyricsCore

@Test func sweepStyleHasTwoVariants() {
    #expect(SweepStyle.allCases.count == 2)
    #expect(SweepStyle.allCases.contains(.fill))
    #expect(SweepStyle.allCases.contains(.scale))
}

// MARK: - fill style

@Test func fillOpacityRampsWithProgress() {
    #expect(abs(WordEmphasis.opacity(progress: 0, style: .fill) - 0.30) < 0.001)
    #expect(abs(WordEmphasis.opacity(progress: 1, style: .fill) - 1.0) < 0.001)
    let mid = WordEmphasis.opacity(progress: 0.5, style: .fill)
    #expect(mid > 0.30 && mid < 1.0)
}

@Test func fillStyleNeverScales() {
    for p in stride(from: 0.0, through: 1.0, by: 0.1) {
        #expect(WordEmphasis.scale(progress: p, style: .fill) == 1.0)
    }
}

// MARK: - scale style

@Test func scaleStyleIsFlatForUnsungAndFinishedWords() {
    #expect(WordEmphasis.scale(progress: 0, style: .scale) == 1.0)
    #expect(WordEmphasis.scale(progress: 1, style: .scale) == 1.0)
}

@Test func scaleStylePeaksMidWord() {
    let peak = WordEmphasis.scale(progress: 0.5, style: .scale)
    #expect(peak > 1.0)
    #expect(abs(peak - (1.0 + WordEmphasis.maxScaleBoost)) < 0.001)
}

@Test func scaleStyleRisesThenFalls() {
    let quarter = WordEmphasis.scale(progress: 0.25, style: .scale)
    let half = WordEmphasis.scale(progress: 0.5, style: .scale)
    let threeQuarter = WordEmphasis.scale(progress: 0.75, style: .scale)
    #expect(quarter < half)
    #expect(threeQuarter < half)
    #expect(abs(quarter - threeQuarter) < 0.001)   // symmetric
}

@Test func scaleStaysWithinBounds() {
    for p in stride(from: 0.0, through: 1.0, by: 0.05) {
        let s = WordEmphasis.scale(progress: p, style: .scale)
        #expect(s >= 1.0 && s <= 1.0 + WordEmphasis.maxScaleBoost + 0.001)
    }
}

@Test func scaleStyleSnapsOpacityRatherThanRamping() {
    // The point of this variant: the active word is fully lit immediately,
    // not faded in gradually like .fill.
    let unsung = WordEmphasis.opacity(progress: 0, style: .scale)
    let active = WordEmphasis.opacity(progress: 0.01, style: .scale)
    let sung = WordEmphasis.opacity(progress: 1, style: .scale)
    #expect(active == 1.0)
    #expect(unsung < active)
    #expect(sung < active)      // finished words step back so the active one leads
    #expect(sung > unsung)
}

@Test func progressIsClampedDefensively() {
    #expect(WordEmphasis.scale(progress: -5, style: .scale) == 1.0)
    #expect(WordEmphasis.scale(progress: 9, style: .scale) == 1.0)
    #expect(WordEmphasis.opacity(progress: -5, style: .fill) >= 0)
    #expect(WordEmphasis.opacity(progress: 9, style: .fill) <= 1)
}
