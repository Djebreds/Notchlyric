import Foundation

/// How the current line conveys which word is being sung.
public enum SweepStyle: String, CaseIterable, Sendable, Codable {
    /// Each word brightens gradually as it is sung. Smooth, but reads slowly
    /// because every word is mid-fade for its whole duration.
    case fill
    /// The active word pops larger and is fully lit at once. Snappier — the
    /// eye tracks a single moving emphasis rather than a gradient.
    case scale

    public var displayName: String {
        switch self {
        case .fill:  "Fade In Words"
        case .scale: "Pop Active Word"
        }
    }
}

/// Per-word emphasis, kept out of the view so it can be tested directly.
public enum WordEmphasis {
    /// Peak size increase for the active word in `.scale` style.
    public static let maxScaleBoost: Double = 0.24

    private static let dimOpacity: Double = 0.30
    private static let sungOpacity: Double = 0.85

    public static func scale(progress: Double, style: SweepStyle) -> Double {
        guard style == .scale else { return 1.0 }
        let p = clamp(progress)
        // Smooth symmetric bump: flat at both ends, peak mid-word.
        return 1.0 + maxScaleBoost * sin(.pi * p)
    }

    public static func opacity(progress: Double, style: SweepStyle) -> Double {
        let p = clamp(progress)
        switch style {
        case .fill:
            // Gradual ramp across the word.
            return dimOpacity + (1.0 - dimOpacity) * p
        case .scale:
            // Binary states: upcoming, active, already sung. Size carries the
            // emphasis, so opacity only separates the three.
            if p <= 0 { return dimOpacity }
            if p >= 1 { return sungOpacity }
            return 1.0
        }
    }

    private static func clamp(_ p: Double) -> Double { min(1, max(0, p)) }
}
