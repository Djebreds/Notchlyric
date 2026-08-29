import Testing
import CoreGraphics
@testable import NotchLyricsCore

@Test func wrapsWordsThatFitOnOneLine() {
    let rows = WordWrapper.wrap(widths: [30, 40, 50], maxWidth: 200, spacing: 5)
    #expect(rows == [[0, 1, 2]])
}

@Test func breaksWhenTheLineIsFull() {
    // 60 + 5 + 60 = 125 fits; adding another 60 would exceed 200
    let rows = WordWrapper.wrap(widths: [60, 60, 60, 60], maxWidth: 200, spacing: 5)
    #expect(rows.count == 2)
    #expect(rows[0] == [0, 1, 2])
    #expect(rows[1] == [3])
}

@Test func aWordWiderThanTheLineGetsItsOwnRow() {
    let rows = WordWrapper.wrap(widths: [50, 500, 50], maxWidth: 200, spacing: 5)
    #expect(rows == [[0], [1], [2]])
}

@Test func spacingCountsBetweenWordsOnly() {
    // three 60s with spacing 20: 60+20+60+20+60 = 220 > 200 -> breaks
    let rows = WordWrapper.wrap(widths: [60, 60, 60], maxWidth: 200, spacing: 20)
    #expect(rows[0] == [0, 1])
}

@Test func everyWordAppearsExactlyOnce() {
    let widths: [CGFloat] = [30, 45, 70, 20, 90, 55, 40]
    let rows = WordWrapper.wrap(widths: widths, maxWidth: 160, spacing: 6)
    #expect(rows.flatMap { $0 }.sorted() == Array(0..<widths.count))
}

@Test func handlesEmptyInput() {
    #expect(WordWrapper.wrap(widths: [], maxWidth: 200, spacing: 5).isEmpty)
}

@Test func handlesZeroWidthGracefully() {
    let rows = WordWrapper.wrap(widths: [10, 10], maxWidth: 0, spacing: 5)
    #expect(rows.flatMap { $0 }.count == 2)     // never drops words
}

@Test func rowWidthNeverExceedsTheLimitUnlessASingleWordDoes() {
    let widths: [CGFloat] = [40, 40, 40, 40, 40]
    let maxWidth: CGFloat = 130, spacing: CGFloat = 5
    for row in WordWrapper.wrap(widths: widths, maxWidth: maxWidth, spacing: spacing) {
        let total = row.reduce(0) { $0 + widths[$1] } + spacing * CGFloat(max(row.count - 1, 0))
        #expect(row.count == 1 || total <= maxWidth + 0.001)
    }
}
