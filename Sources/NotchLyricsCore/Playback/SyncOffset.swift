import Foundation

/// A manual nudge applied to the playhead before choosing a lyric.
///
/// Line timings are contributed by hand and are sometimes offset against a
/// particular master, so the clock can be exactly right while the words still
/// arrive early or late. Re-syncing cannot help there — it aligns the clock to
/// the player, which was never the thing that was wrong.
public enum SyncOffset {
    public enum Direction { case earlier, later }

    /// One press worth of adjustment.
    public static let step: TimeInterval = 0.25
    /// Nothing plausible needs more than a few seconds either way.
    public static let limit: TimeInterval = 3.0

    public static func clamp(_ offset: TimeInterval) -> TimeInterval {
        min(limit, max(-limit, offset))
    }

    public static func nudged(_ offset: TimeInterval, by direction: Direction) -> TimeInterval {
        clamp(offset + (direction == .later ? step : -step))
    }

    /// Shifts the playhead used for lyric selection.
    ///
    /// A positive offset asks for the lyric from slightly earlier, which makes
    /// the words appear later on screen.
    public static func apply(_ position: TimeInterval, offset: TimeInterval) -> TimeInterval {
        max(0, position - clamp(offset))
    }

    public static func label(_ offset: TimeInterval) -> String {
        let v = clamp(offset)
        if abs(v) < 0.001 { return "0.00s" }
        return String(format: "%@%.2fs", v > 0 ? "+" : "-", abs(v))
    }
}
