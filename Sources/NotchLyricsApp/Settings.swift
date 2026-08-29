import Foundation
import NotchLyricsCore

@MainActor
final class Settings {
    private enum Key {
        static let position = "position"
        static let netEaseEnabled = "netEaseEnabled"
        static let sweepStyle = "sweepStyle"
        static let romanizeCJK = "romanizeCJK"
    }

    static let shared = Settings()
    private let defaults = UserDefaults.standard

    /// Called when a setting changes so the overlay can react without a restart.
    var onChange: (() -> Void)?

    var position: Position {
        get { Position(rawValue: defaults.string(forKey: Key.position) ?? "") ?? .notch }
        set { defaults.set(newValue.rawValue, forKey: Key.position); onChange?() }
    }

    var sweepStyle: SweepStyle {
        get { SweepStyle(rawValue: defaults.string(forKey: Key.sweepStyle) ?? "") ?? .scale }
        set { defaults.set(newValue.rawValue, forKey: Key.sweepStyle); onChange?() }
    }

    /// Show romaji for Japanese/Chinese/Korean lyrics instead of the source
    /// script. Segmentation happens either way — it is what makes per-word
    /// tracking work at all for those scripts.
    var romanizeCJK: Bool {
        get { defaults.object(forKey: Key.romanizeCJK) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.romanizeCJK); onChange?() }
    }

    var netEaseEnabled: Bool {
        get { defaults.object(forKey: Key.netEaseEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.netEaseEnabled); onChange?() }
    }
}
