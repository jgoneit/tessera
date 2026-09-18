import Foundation
import CoreGraphics
import Testing
@testable import TesseraCore

private func display(_ id: UInt32, _ frame: CGRect, scale: CGFloat = 1) -> DisplayGeometry {
    DisplayGeometry(id: id, frame: frame, visibleFrame: frame, scale: scale)
}

@Test func coordinateConversionUsesPrimaryTopForEveryScreen() {
    let primaryTop: CGFloat = 1080
    let examples: [(CGRect, CGFloat)] = [
        (CGRect(x: 10, y: 100, width: 400, height: 300), 680),
        (CGRect(x: -2500, y: -500, width: 400, height: 300), 1280),
        (CGRect(x: 2000, y: 1200, width: 400, height: 300), -420),
        (CGRect(x: 2000, y: -1400, width: 400, height: 300), 2180),
    ]
    for (appKit, expectedY) in examples {
        let ax = CoordinateSpace.flip(appKit, primaryTop: primaryTop)
        #expect(ax == CGRect(x: appKit.minX, y: expectedY, width: appKit.width, height: appKit.height))
        #expect(CoordinateSpace.flip(ax, primaryTop: primaryTop) == appKit)
    }
}

@Test func fractionalCoordinateConversionRoundTrips() {
    let input = CGRect(x: -1572.25, y: 1402.5, width: 457.5, height: 238.25)
    let output = CoordinateSpace.flip(input, primaryTop: 1117)
    #expect(output.minY == -523.75)
    #expect(CoordinateSpace.flip(output, primaryTop: 1117) == input)
}

@Test func displaySelectionChoosesLargestOverlapInsteadOfWindowCenter() {
    let narrow = display(1, CGRect(x: 0, y: 0, width: 500, height: 1000))
    let right = display(2, CGRect(x: 500, y: 0, width: 1000, height: 1000))
    let window = CGRect(x: 400, y: 100, width: 600, height: 600)
    #expect(DisplaySelection.bestDisplay(for: window, in: [narrow, right]) == right)

    // The center is in the tall right screen, but the left one has more area.
    let left = display(3, CGRect(x: -1200, y: 0, width: 1200, height: 900))
    let tall = display(4, CGRect(x: 0, y: -500, width: 900, height: 1800))
    let crossing = CGRect(x: -1000, y: 0, width: 2100, height: 800)
    #expect(DisplaySelection.bestDisplay(for: crossing, in: [left, tall]) == left)
}

@Test func displayOverlapTiesPreserveEnumerationOrder() {
    let left = display(1, CGRect(x: -1000, y: 0, width: 1000, height: 800))
    let right = display(2, CGRect(x: 0, y: 0, width: 1000, height: 800))
    let window = CGRect(x: -100, y: 100, width: 200, height: 200)
    #expect(DisplaySelection.bestDisplay(for: window, in: [left, right]) == left)
    #expect(DisplaySelection.bestDisplay(for: window, in: [right, left]) == right)
}

@Test func displaySelectionUsesFullFrameIncludingReservedMenuAndDockArea() {
    let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let main = DisplayGeometry(id: 1, frame: frame, visibleFrame: frame.insetBy(dx: 50, dy: 50), scale: 2)
    let other = display(2, CGRect(x: 1000, y: 0, width: 1000, height: 800))
    #expect(DisplaySelection.bestDisplay(for: CGRect(x: 10, y: 10, width: 20, height: 20), in: [main, other]) == main)
}

@Test func offscreenWindowsChooseNearestDisplayCenterAndStableTies() {
    let left = display(1, CGRect(x: -1000, y: 0, width: 1000, height: 800))
    let right = display(2, CGRect(x: 0, y: 0, width: 1000, height: 800))
    let outside = CGRect(x: 2000, y: 2000, width: 200, height: 200)
    #expect(DisplaySelection.bestDisplay(for: outside, in: [left, right]) == right)
    let tied = CGRect(x: -50, y: 2000, width: 100, height: 100)
    #expect(DisplaySelection.bestDisplay(for: tied, in: [right, left]) == right)
    #expect(DisplaySelection.bestDisplay(for: tied, in: [left, right]) == left)
}

@Test func edgeTouchDoesNotCountAsOverlap() {
    let left = display(1, CGRect(x: 0, y: 0, width: 100, height: 1000))
    let right = display(2, CGRect(x: 200, y: 0, width: 100, height: 100))
    let window = CGRect(x: 100, y: 0, width: 50, height: 50)
    #expect(DisplaySelection.bestDisplay(for: window, in: [left, right]) == right)
}

@Test func invalidDisplayInputsDoNotProduceATarget() {
    let valid = display(1, CGRect(x: 0, y: 0, width: 100, height: 100))
    #expect(DisplaySelection.bestDisplay(for: valid.frame, in: []) == nil)
    #expect(DisplaySelection.bestDisplay(for: .zero, in: [valid]) == nil)
    #expect(DisplaySelection.bestDisplay(for: CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100), in: [valid]) == nil)
    let invalid = display(2, .zero)
    let invalidScale = display(3, valid.frame, scale: .infinity)
    #expect(DisplaySelection.bestDisplay(for: valid.frame, in: [invalid, invalidScale]) == nil)
    #expect(DisplaySelection.bestDisplay(for: valid.frame, in: [invalid, valid]) == valid)
}

@Test func resizedWindowClampsEachAxisToVisibleFrame() {
    let visible = CGRect(x: -1920, y: 24, width: 1920, height: 1056)
    let size = CGSize(width: 640, height: 480)
    #expect(PlacementGeometry.clampedOrigin(for: size, desiredOrigin: CGPoint(x: -1800, y: 100), in: visible) == CGPoint(x: -1800, y: 100))
    #expect(PlacementGeometry.clampedOrigin(for: size, desiredOrigin: CGPoint(x: -2500, y: -100), in: visible) == CGPoint(x: -1920, y: 24))
    #expect(PlacementGeometry.clampedOrigin(for: size, desiredOrigin: CGPoint(x: 10, y: 1200), in: visible) == CGPoint(x: -640, y: 600))
}

@Test func oversizedWindowsAlignToTopLeftWithoutClaimingToFit() {
    let visible = CGRect(x: 100, y: 50, width: 1000, height: 700)
    let oversized = CGSize(width: 1300, height: 900)
    let origin = PlacementGeometry.clampedOrigin(for: oversized, desiredOrigin: CGPoint(x: 300, y: 400), in: visible)
    #expect(origin == CGPoint(x: 100, y: 50))
    #expect(!visible.contains(CGRect(origin: origin, size: oversized)))
    #expect(CGRect(origin: origin, size: oversized).minY == visible.minY)
    #expect(PlacementGeometry.clampedOrigin(for: visible.size, desiredOrigin: .zero, in: visible) == visible.origin)
}
