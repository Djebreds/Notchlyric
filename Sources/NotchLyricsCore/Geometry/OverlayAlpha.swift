import Foundation

/// What the overlay is doing right now.
public enum OverlayState: Equatable, Sendable {
    /// Nothing is playing — the panel is not on screen at all.
    case hidden
    /// Playing, but with nothing to show: an instrumental break, the run-in
    /// before the first line, or a change of track. The panel stays put so it
    /// does not blink in and out between lines.
    case idle
    /// Showing a line.
    case active
}

/// Decides how opaque the overlay should be.
public enum OverlayAlpha {
    /// Opacity while the cursor is over the panel.
    public static let hoveredAlpha: Double = 0.18
    /// Opacity during instrumental breaks and track changes.
    public static let idleAlpha: Double = 0.38

    public static let fadeInDuration: Double = 0.22
    public static let fadeOutDuration: Double = 0.3
    /// Hover feedback should feel immediate, so it is quicker than show/hide.
    public static let hoverDuration: Double = 0.14
    /// Settling into or out of an instrumental break should be unhurried.
    public static let idleDuration: Double = 0.45

    public static func target(state: OverlayState, hovered: Bool) -> Double {
        switch state {
        case .hidden:
            return 0
        case .idle:
            // Whichever reason wants it dimmer wins.
            return hovered ? min(idleAlpha, hoveredAlpha) : idleAlpha
        case .active:
            return hovered ? hoveredAlpha : 1
        }
    }
}
