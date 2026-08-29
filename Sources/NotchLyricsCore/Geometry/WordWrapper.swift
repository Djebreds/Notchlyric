import CoreGraphics

/// Greedy line breaking over pre-measured word widths.
///
/// Widths are measured at each word's *base* size, never its emphasised size,
/// so growing a word on screen cannot change where lines break.
public enum WordWrapper {
    /// Returns the word indices belonging to each row, in order.
    public static func wrap(widths: [CGFloat],
                            maxWidth: CGFloat,
                            spacing: CGFloat) -> [[Int]] {
        guard !widths.isEmpty else { return [] }

        var rows: [[Int]] = []
        var current: [Int] = []
        var used: CGFloat = 0

        for (index, width) in widths.enumerated() {
            let advance = current.isEmpty ? width : spacing + width
            if !current.isEmpty && used + advance > maxWidth {
                rows.append(current)
                current = [index]
                used = width
            } else {
                current.append(index)
                used += advance
            }
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }
}
