import Foundation

/// Turns coarse 1 Hz position samples into a smooth continuous estimate.
///
/// Uses `ContinuousClock` so sleep/wake cannot corrupt the timeline. All
/// instants are supplied by the caller, which keeps this pure and testable.
public struct PlaybackClock: Sendable {
    public static let seekThreshold: TimeInterval = 0.25
    public static let correctionWindow: TimeInterval = 0.2

    private var anchorPosition: TimeInterval = 0
    private var anchorInstant: ContinuousClock.Instant?
    private var isPlaying = false

    private var pendingDelta: TimeInterval = 0
    private var correctionStart: ContinuousClock.Instant?

    public private(set) var didSeek = false

    public init() {}

    public var hasSample: Bool { anchorInstant != nil }

    public mutating func ingest(position newPosition: TimeInterval,
                                at instant: ContinuousClock.Instant,
                                isPlaying playing: Bool) {
        didSeek = false

        guard anchorInstant != nil else {
            anchorPosition = max(0, newPosition)
            anchorInstant = instant
            isPlaying = playing
            return
        }

        // Fold everything applied so far into a fresh anchor.
        let current = position(at: instant)
        anchorPosition = current
        anchorInstant = instant
        pendingDelta = 0
        correctionStart = nil

        let wasPlaying = isPlaying
        isPlaying = playing

        let delta = newPosition - current
        if abs(delta) >= Self.seekThreshold {
            anchorPosition = max(0, newPosition)
            // A pause/resume boundary explains the gap; don't call that a seek.
            didSeek = wasPlaying == playing
        } else if delta != 0 {
            pendingDelta = delta
            correctionStart = instant
        }
    }

    public func position(at instant: ContinuousClock.Instant) -> TimeInterval {
        guard let anchorInstant else { return 0 }

        var p = anchorPosition
        if isPlaying {
            p += Self.seconds(from: anchorInstant.duration(to: instant))
        }
        if let correctionStart, pendingDelta != 0 {
            let elapsed = Self.seconds(from: correctionStart.duration(to: instant))
            let factor = min(1, max(0, elapsed / Self.correctionWindow))
            p += pendingDelta * factor
        }
        return max(0, p)
    }

    private static func seconds(from d: Duration) -> TimeInterval {
        let c = d.components
        return TimeInterval(c.seconds) + TimeInterval(c.attoseconds) * 1e-18
    }
}
