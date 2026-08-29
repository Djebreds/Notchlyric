import Testing
import Foundation
@testable import NotchLyricsCore

@Test func hiddenIsFullyTransparent() {
    #expect(OverlayAlpha.target(visible: false, hovered: false) == 0)
    #expect(OverlayAlpha.target(visible: false, hovered: true) == 0)
}

@Test func visibleAndNotHoveredIsOpaque() {
    #expect(OverlayAlpha.target(visible: true, hovered: false) == 1)
}

@Test func hoveringDimsButDoesNotHide() {
    let a = OverlayAlpha.target(visible: true, hovered: true)
    #expect(a == OverlayAlpha.hoveredAlpha)
    #expect(a > 0)          // still visible enough to read
    #expect(a < 1)          // background shows through
}

@Test func hoverAlphaIsInAUsefulRange() {
    #expect(OverlayAlpha.hoveredAlpha >= 0.1)
    #expect(OverlayAlpha.hoveredAlpha <= 0.5)
}

@Test func hoverOnlyMattersWhileVisible() {
    // toggling hover while hidden must never reveal the panel
    for hovered in [true, false] {
        #expect(OverlayAlpha.target(visible: false, hovered: hovered) == 0)
    }
}

@Test func transitionDurationIsFasterForHoverThanForShowHide() {
    #expect(OverlayAlpha.hoverDuration < OverlayAlpha.fadeOutDuration)
}
