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

    struct Cache {
        var sizes: [CGSize] = []
        var rows: [[Int]] = []
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    private func measure(_ subviews: Subviews, maxWidth: CGFloat, cache: inout Cache) {
        cache.sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        cache.rows = WordWrapper.wrap(widths: cache.sizes.map(\.width),
                                      maxWidth: maxWidth, spacing: spacing)
    }

    private func rowWidth(_ row: [Int], _ cache: Cache) -> CGFloat {
        row.reduce(0) { $0 + cache.sizes[$1].width } + spacing * CGFloat(max(row.count - 1, 0))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
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
        let maxWidth = proposal.width ?? bounds.width
        if cache.sizes.count != subviews.count { measure(subviews, maxWidth: maxWidth, cache: &cache) }

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
    /// Base font for a word — never the emphasised size.
    let font: (WordToken) -> Font
    let text: (WordToken) -> String

    var body: some View {
        WordFlowLayout(spacing: spacing, rtl: rtl) {
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
