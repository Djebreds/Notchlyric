import Foundation

/// Decides how opaque the overlay should be.
///
/// Hovering dims the panel rather than hiding it, so whatever sits behind it
/// stays readable without the lyric disappearing entirely.
public enum OverlayAlpha {
    /// Opacity while the cursor is over the panel.
    public static let hoveredAlpha: Double = 0.18

    public static let fadeInDuration: Double = 0.22
    public static let fadeOutDuration: Double = 0.3
    /// Hover feedback should feel immediate, so it is quicker than show/hide.
    public static let hoverDuration: Double = 0.14

    public static func target(visible: Bool, hovered: Bool) -> Double {
        guard visible else { return 0 }
        return hovered ? hoveredAlpha : 1
    }
}
