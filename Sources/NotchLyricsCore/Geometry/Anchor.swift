import CoreGraphics

public enum Anchor {
    public static let edgeInset: CGFloat = 16
    public static let earInset: CGFloat = 8

    public static func frame(for position: Position,
                             in metrics: ScreenMetrics,
                             size: CGSize) -> CGRect {
        switch position {
        case .notch:       notchFrame(metrics, size)
        case .earLeft:     earFrame(metrics, size, left: true)
        case .earRight:    earFrame(metrics, size, left: false)
        case .bottomRight: bottomRightFrame(metrics, size)
        }
    }

    private static func notchFrame(_ m: ScreenMetrics, _ size: CGSize) -> CGRect {
        guard let notch = m.notchRect else {
            // No notch: a pill centred under the menu bar.
            let w = min(size.width, m.visibleFrame.width - 2 * edgeInset)
            return CGRect(x: m.frame.midX - w / 2,
                          y: m.visibleFrame.maxY - size.height,
                          width: w, height: size.height)
        }
        // Wide enough to visually swallow the cutout, then hang below it.
        let w = min(max(size.width, notch.width), m.frame.width - 2 * edgeInset)
        return CGRect(x: notch.midX - w / 2,
                      y: m.frame.maxY - size.height,
                      width: w, height: size.height)
    }

    private static func earFrame(_ m: ScreenMetrics, _ size: CGSize, left: Bool) -> CGRect {
        guard let aux = left ? m.auxTopLeft : m.auxTopRight, m.hasNotch else {
            let w = min(size.width, m.visibleFrame.width - 2 * edgeInset)
            let x = left ? m.frame.minX + edgeInset : m.frame.maxX - w - edgeInset
            return CGRect(x: x, y: m.visibleFrame.maxY - size.height, width: w, height: size.height)
        }
        let w = min(size.width, aux.width - 2 * earInset)
        // Left ear must dodge the Apple menu; right ear butts against the cutout.
        let x = left ? aux.maxX - w - earInset : aux.minX + earInset
        return CGRect(x: x, y: aux.minY, width: w, height: m.safeAreaTop)
    }

    private static func bottomRightFrame(_ m: ScreenMetrics, _ size: CGSize) -> CGRect {
        let w = min(size.width, m.visibleFrame.width - 2 * edgeInset)
        let h = min(size.height, m.visibleFrame.height - 2 * edgeInset)
        return CGRect(x: m.visibleFrame.maxX - w - edgeInset,
                      y: m.visibleFrame.minY + edgeInset,
                      width: w, height: h)
    }
}
