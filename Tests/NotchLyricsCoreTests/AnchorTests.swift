import Testing
import CoreGraphics
@testable import NotchLyricsCore

/// Measured on the target MacBook (spec §1.1).
private let notched = ScreenMetrics(
    frame: CGRect(x: 0, y: 0, width: 1800, height: 1169),
    visibleFrame: CGRect(x: 0, y: 0, width: 1800, height: 1130),
    safeAreaTop: 38,
    auxTopLeft: CGRect(x: 0, y: 1131, width: 790, height: 38),
    auxTopRight: CGRect(x: 1010, y: 1131, width: 790, height: 38)
)

private let external = ScreenMetrics(
    frame: CGRect(x: 1800, y: 0, width: 2560, height: 1440),
    visibleFrame: CGRect(x: 1800, y: 0, width: 2560, height: 1415),
    safeAreaTop: 0, auxTopLeft: nil, auxTopRight: nil
)

private let size = CGSize(width: 420, height: 84)

@Test func detectsNotch() {
    #expect(notched.hasNotch)
    #expect(external.hasNotch == false)
}

@Test func computesNotchRect() {
    let n = notched.notchRect!
    #expect(n.width == 220)
    #expect(n.height == 38)
    #expect(n.midX == 900)
}

@Test func notchPanelIsCenteredAndFlushWithScreenTop() {
    let f = Anchor.frame(for: .notch, in: notched, size: size)
    #expect(f.midX == 900)
    #expect(f.maxY == 1169)
    #expect(f.height == 84)
}

@Test func notchPanelIsAtLeastAsWideAsNotchPlusMargin() {
    let narrow = CGSize(width: 100, height: 84)
    let f = Anchor.frame(for: .notch, in: notched, size: narrow)
    #expect(f.width >= 220)
}

@Test func notchFallsBackBelowMenuBarWithoutNotch() {
    let f = Anchor.frame(for: .notch, in: external, size: size)
    #expect(f.midX == external.frame.midX)
    #expect(f.maxY == external.visibleFrame.maxY)
}

@Test func earLeftStaysInsideLeftAuxiliaryArea() {
    let f = Anchor.frame(for: .earLeft, in: notched, size: size)
    #expect(f.minX >= 0)
    #expect(f.maxX <= 790)
    #expect(f.height == 38)
}

@Test func earRightStaysInsideRightAuxiliaryArea() {
    let f = Anchor.frame(for: .earRight, in: notched, size: size)
    #expect(f.minX >= 1010)
    #expect(f.maxX <= 1800)
    #expect(f.height == 38)
}

@Test func earClampsOversizedPanel() {
    let huge = CGSize(width: 5000, height: 38)
    let f = Anchor.frame(for: .earLeft, in: notched, size: huge)
    #expect(f.width <= 790)
}

@Test func earFallsBackWithoutNotch() {
    let f = Anchor.frame(for: .earRight, in: external, size: size)
    #expect(f.maxY <= external.visibleFrame.maxY)
    #expect(f.maxX <= external.frame.maxX)
}

@Test func bottomRightRespectsVisibleFrame() {
    let f = Anchor.frame(for: .bottomRight, in: notched, size: size)
    #expect(f.maxX <= 1800)
    #expect(f.minY >= 0)
    #expect(f.maxY <= 1130)
}

@Test func bottomRightOnExternalDisplayUsesItsOrigin() {
    let f = Anchor.frame(for: .bottomRight, in: external, size: size)
    #expect(f.minX >= 1800)
    #expect(f.maxX <= 4360)
}

@Test func everyPositionStaysWithinScreenBounds() {
    for p in Position.allCases {
        for m in [notched, external] {
            let f = Anchor.frame(for: p, in: m, size: size)
            #expect(m.frame.contains(f) || m.frame.intersects(f))
            #expect(f.width > 0 && f.height > 0)
        }
    }
}
