import Testing
import Foundation
@testable import NotchLyricsCore

@Test func hiddenIsFullyTransparent() {
    #expect(OverlayAlpha.target(state: .hidden, hovered: false) == 0)
    #expect(OverlayAlpha.target(state: .hidden, hovered: true) == 0)
}

@Test func activeAndNotHoveredIsOpaque() {
    #expect(OverlayAlpha.target(state: .active, hovered: false) == 1)
}

@Test func hoveringDimsButDoesNotHide() {
    let a = OverlayAlpha.target(state: .active, hovered: true)
    #expect(a == OverlayAlpha.hoveredAlpha)
    #expect(a > 0 && a < 1)
}

// MARK: - idle: instrumental breaks and track changes

@Test func idleStaysVisibleButDim() {
    let a = OverlayAlpha.target(state: .idle, hovered: false)
    #expect(a == OverlayAlpha.idleAlpha)
    #expect(a > 0)                                  // must not disappear
    #expect(a < OverlayAlpha.target(state: .active, hovered: false))
}

@Test func idleIsBrighterThanHover() {
    // idle should read as "still here", hover as "get out of the way"
    #expect(OverlayAlpha.idleAlpha > OverlayAlpha.hoveredAlpha)
}

@Test func hoveringWhileIdleTakesTheDimmerOfTheTwo() {
    let a = OverlayAlpha.target(state: .idle, hovered: true)
    #expect(a == min(OverlayAlpha.idleAlpha, OverlayAlpha.hoveredAlpha))
}

@Test func hoverNeverRevealsAHiddenPanel() {
    for hovered in [true, false] {
        #expect(OverlayAlpha.target(state: .hidden, hovered: hovered) == 0)
    }
}

@Test func everyStateStaysInRange() {
    for state in [OverlayState.hidden, .idle, .active] {
        for hovered in [true, false] {
            let a = OverlayAlpha.target(state: state, hovered: hovered)
            #expect(a >= 0 && a <= 1)
        }
    }
}

@Test func transitionDurationIsFasterForHoverThanForShowHide() {
    #expect(OverlayAlpha.hoverDuration < OverlayAlpha.fadeOutDuration)
}
