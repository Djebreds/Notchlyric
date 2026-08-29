import SwiftUI
import NotchLyricsCore

/// Lays word views out in wrapped rows.
///
/// Each subview is measured at its base size. Emphasis is applied with
/// `scaleEffect`, which is a purely visual transform and does not feed back
/// into layout — so growing a word can never re-wrap the line.
struct WordFlowLayout: Layout {
    var spacing: CGFloat = 6
    var rowSpacing: CGFloat = 2
    var rtl: Bool = false
    /// Identity of the line being laid out. Measurements are reused while this
    /// is unchanged, so text is not re-measured on every emphasis frame —
    /// scaleEffect and colour do not alter a word's reported size.
    var lineID: Double = 0

    struct Cache {
        struct Key: Equatable {
            let lineID: Double
            let count: Int
            let width: CGFloat
        }
        var sizes: [CGSize] = []
        var rows: [[Int]] = []
        var key: Key?
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    /// A degenerate proposal (nil or non-positive width) must not be taken
    /// literally: wrapping to it would put every word on its own row and report
    /// an enormous height, which AppKit would then apply to the window.
    private func usableWidth(_ proposed: CGFloat?) -> CGFloat {
        guard let proposed, proposed.isFinite, proposed > 1 else { return .greatestFiniteMagnitude }
        return proposed
    }

    private func measure(_ subviews: Subviews, maxWidth: CGFloat, cache: inout Cache) {
        let key = Cache.Key(lineID: lineID, count: subviews.count, width: maxWidth)
        guard cache.key != key else { return }        // text metrics are unchanged
        cache.key = key
        cache.sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        cache.rows = WordWrapper.wrap(widths: cache.sizes.map(\.width),
                                      maxWidth: maxWidth, spacing: spacing)
    }

    private func rowWidth(_ row: [Int], _ cache: Cache) -> CGFloat {
        row.reduce(0) { $0 + cache.sizes[$1].width } + spacing * CGFloat(max(row.count - 1, 0))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let maxWidth = usableWidth(proposal.width)
        measure(subviews, maxWidth: maxWidth, cache: &cache)
        guard !cache.rows.isEmpty else { return .zero }

        let height = cache.rows.enumerated().reduce(CGFloat.zero) { acc, entry in
            let h = entry.element.map { cache.sizes[$0].height }.max() ?? 0
            return acc + h + (entry.offset > 0 ? rowSpacing : 0)
        }
        let width = cache.rows.map { rowWidth($0, cache) }.max() ?? 0
        return CGSize(width: min(width, maxWidth), height: height)

    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout Cache) {
        let maxWidth = usableWidth(proposal.width ?? bounds.width)
        measure(subviews, maxWidth: maxWidth, cache: &cache)

        var y = bounds.minY
        for row in cache.rows {
            let rowH = row.map { cache.sizes[$0].height }.max() ?? 0
            var x = bounds.midX - rowWidth(row, cache) / 2
            for index in (rtl ? Array(row.reversed()) : row) {
                let size = cache.sizes[index]
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (rowH - size.height) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowH + rowSpacing
        }
    }
}

/// One line of words, each emphasised independently without disturbing layout.
struct WordFlow: View {
    let words: [WordToken]
    let time: TimeInterval
    let style: SweepStyle
    let rtl: Bool
    let spacing: CGFloat
    /// Identity of this line, so layout measurements can be reused between frames.
    let lineID: Double
    /// Base font for a word — never the emphasised size.
    let font: (WordToken) -> Font
    let text: (WordToken) -> String

    var body: some View {
        WordFlowLayout(spacing: spacing, rtl: rtl, lineID: lineID) {
            ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                let progress = word.progress(at: time)
                Text(verbatim: text(word))
                    .font(font(word))
                    .foregroundColor(.white.opacity(
                        WordEmphasis.opacity(progress: progress, style: style)))
                    .fixedSize()
                    // visual only: does not participate in layout
                    .scaleEffect(WordEmphasis.scale(progress: progress, style: style),
                                 anchor: .center)
            }
        }
    }
}
