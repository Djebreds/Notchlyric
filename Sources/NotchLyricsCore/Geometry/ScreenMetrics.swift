import CoreGraphics

/// AppKit-free description of a display, so geometry stays unit-testable.
public struct ScreenMetrics: Equatable, Sendable {
    public var frame: CGRect
    public var visibleFrame: CGRect
    public var safeAreaTop: CGFloat
    public var auxTopLeft: CGRect?
    public var auxTopRight: CGRect?

    public init(frame: CGRect, visibleFrame: CGRect, safeAreaTop: CGFloat,
                auxTopLeft: CGRect?, auxTopRight: CGRect?) {
        self.frame = frame; self.visibleFrame = visibleFrame
        self.safeAreaTop = safeAreaTop
        self.auxTopLeft = auxTopLeft; self.auxTopRight = auxTopRight
    }

    public var hasNotch: Bool {
        safeAreaTop > 0 && auxTopLeft != nil && auxTopRight != nil
    }

    /// The camera cutout — a region with no pixels behind it (spec §1.1).
    public var notchRect: CGRect? {
        guard let l = auxTopLeft, let r = auxTopRight, r.minX > l.maxX else { return nil }
        return CGRect(x: l.maxX, y: l.minY, width: r.minX - l.maxX, height: safeAreaTop)
    }
}
