import AppKit
import SwiftUI
import NotchLyricsCore

extension ScreenMetrics {
    init(_ screen: NSScreen) {
        self.init(frame: screen.frame,
                  visibleFrame: screen.visibleFrame,
                  safeAreaTop: screen.safeAreaInsets.top,
                  auxTopLeft: screen.auxiliaryTopLeftArea,
                  auxTopRight: screen.auxiliaryTopRightArea)
    }
}

/// Borderless click-through panel that floats above the menu bar on every Space.
/// This configuration was validated on the target machine (spec §1.6).
final class OverlayWindow: NSPanel {
    private(set) var position: Position
    /// Arabic needs a taller, wider panel than Latin lyrics.
    var script: Script = .latin
    private var hosting: NSHostingView<AnyView>?

    init(position: Position) {
        self.position = position
        super.init(contentRect: CGRect(x: 0, y: 0, width: 460, height: 84),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isMovable = false
        hidesOnDeactivate = false
        alphaValue = 0
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func setContent<V: View>(_ view: V) {
        let wrapped = AnyView(view)
        if let hosting {
            hosting.rootView = wrapped
        } else {
            let h = NSHostingView(rootView: wrapped)
            h.autoresizingMask = [.width, .height]
            contentView = h
            hosting = h
        }
    }

    /// Panel size per position: the ear is limited to the menu bar's height.
    private func preferredSize(for metrics: ScreenMetrics) -> CGSize {
        if script == .arabic, position == .notch {
            return CGSize(width: 560, height: 104)
        }
        return switch position {
        case .notch:       CGSize(width: 460, height: 84)
        case .earLeft, .earRight:
            CGSize(width: 340, height: max(22, metrics.safeAreaTop))
        case .bottomRight: CGSize(width: 380, height: 72)
        }
    }

    func reanchor(to screen: NSScreen?) {
        guard let screen = screen ?? NSScreen.main else { return }
        let metrics = ScreenMetrics(screen)
        let size = preferredSize(for: metrics)
        setFrame(Anchor.frame(for: position, in: metrics, size: size), display: true)
    }

    func setPosition(_ new: Position, screen: NSScreen?) {
        position = new
        reanchor(to: screen)
    }

    func fadeIn() {
        guard alphaValue < 1 else { return }
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            animator().alphaValue = 1
        }
    }

    func fadeOut() {
        guard alphaValue > 0 else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.alphaValue == 0 else { return }
            self.orderOut(nil)
        })
    }
}
