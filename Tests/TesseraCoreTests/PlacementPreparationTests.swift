import Foundation
import CoreGraphics
import Testing
@testable import TesseraCore

@Test func expandingRightThirdToRightHalfPreparesSpaceBeforeResizing() throws {
    for scale: CGFloat in [1, 2] {
        for gap: CGFloat in [0, 8, 12] {
            let visible = CGRect(x: 0, y: 0, width: 1200, height: 800)
            let third = try GridGeometry.frame(
                in: visible, layout: .threeByTwo, target: .column(3), gap: gap, scale: scale)
            let half = try GridGeometry.frame(
                in: visible, layout: .twoByTwo, target: .column(2), gap: gap, scale: scale)
            let origin = try #require(PlacementGeometry.preparationOrigin(
                currentFrame: third, requestedFrame: half, in: visible))
            #expect(origin == CGPoint(x: visible.maxX - half.width, y: third.minY))
            #expect(visible.contains(CGRect(origin: origin, size: third.size)))
            #expect(visible.contains(CGRect(origin: origin, size: half.size)))
        }
    }
}

@Test func leftThirdAndMiddleThirdCanExpandWithoutPreparation() throws {
    let visible = CGRect(x: 0, y: 0, width: 1200, height: 800)
    for (sourceColumn, targetColumn) in [(1, 1), (2, 2)] {
        let third = try GridGeometry.frame(
            in: visible, layout: .threeByTwo, target: .column(sourceColumn), gap: 8, scale: 2)
        let half = try GridGeometry.frame(
            in: visible, layout: .twoByTwo, target: .column(targetColumn), gap: 8, scale: 2)
        #expect(PlacementGeometry.preparationOrigin(currentFrame: third, requestedFrame: half, in: visible) == nil)
    }
}

@Test func bottomExpansionPreparesAnAXTopLeftOrigin() {
    let visible = CGRect(x: 0, y: 0, width: 1200, height: 800)
    let current = CGRect(x: 100, y: 500, width: 500, height: 300)
    let requested = CGRect(x: 100, y: 50, width: 500, height: 700)
    #expect(PlacementGeometry.preparationOrigin(currentFrame: current, requestedFrame: requested, in: visible)
        == CGPoint(x: 100, y: 100))
}

@Test func mixedShrinkAndGrowthUsesTheEnvelopeOfBothSizes() throws {
    let visible = CGRect(x: 0, y: 0, width: 1200, height: 800)
    let current = CGRect(x: 1000, y: 600, width: 400, height: 200)
    let requested = CGRect(x: 100, y: 100, width: 200, height: 600)
    let origin = try #require(PlacementGeometry.preparationOrigin(
        currentFrame: current, requestedFrame: requested, in: visible))
    #expect(origin == CGPoint(x: 800, y: 200))
    #expect(visible.contains(CGRect(origin: origin, size: current.size)))
    #expect(visible.contains(CGRect(origin: origin, size: requested.size)))
}

@Test func preparationSupportsNegativeAndFractionalScreenCoordinates() throws {
    let visible = CGRect(x: -1920.5, y: -1079.75, width: 1920, height: 1055.5)
    let current = CGRect(x: -500.25, y: -324.5, width: 400, height: 300)
    let requested = CGRect(x: -1000.5, y: -800.75, width: 900.5, height: 700.25)
    let origin = try #require(PlacementGeometry.preparationOrigin(
        currentFrame: current, requestedFrame: requested, in: visible))
    #expect(origin == CGPoint(x: -901, y: -724.5))
    #expect(visible.contains(CGRect(origin: origin, size: current.size)))
    #expect(visible.contains(CGRect(origin: origin, size: requested.size)))
}

@Test func alreadyFittingResizeDoesNotMoveTowardTheFinalDestinationEarly() {
    let visible = CGRect(x: 0, y: 0, width: 1200, height: 800)
    let current = CGRect(x: 100, y: 100, width: 300, height: 200)
    for requested in [
        CGRect(x: 700, y: 300, width: 400, height: 400),
        CGRect(x: 900, y: 600, width: 300, height: 200),
        CGRect(x: 1000, y: 700, width: 200, height: 100),
    ] {
        #expect(PlacementGeometry.preparationOrigin(currentFrame: current, requestedFrame: requested, in: visible) == nil)
    }
}

@Test func oversizedEnvelopeAnchorsAtVisibleMinimumWithoutClaimingToFit() throws {
    let visible = CGRect(x: -1200, y: 24, width: 1200, height: 800)
    let current = CGRect(x: -900, y: 500, width: 1500, height: 1000)
    let requested = CGRect(x: -1200, y: 24, width: 1200, height: 800)
    let origin = try #require(PlacementGeometry.preparationOrigin(
        currentFrame: current, requestedFrame: requested, in: visible))
    #expect(origin == visible.origin)
    #expect(!visible.contains(CGRect(origin: origin, size: current.size)))
    #expect(visible.contains(CGRect(origin: origin, size: requested.size)))

    // Shrinking already fits at the current origin, despite the old oversized size.
    let shrinking = CGRect(x: -1000, y: 100, width: 200, height: 200)
    #expect(PlacementGeometry.preparationOrigin(currentFrame: current, requestedFrame: shrinking, in: visible) == nil)
}

@Test func preparationAvoidsNoOpAndSubToleranceMoves() {
    let visible = CGRect(x: 0, y: 0, width: 1200, height: 800)
    let requested = CGRect(x: 0, y: 0, width: 1400, height: 900)
    let anchored = CGRect(x: 0, y: 0, width: 1400, height: 900)
    #expect(PlacementGeometry.preparationOrigin(currentFrame: anchored, requestedFrame: requested, in: visible) == nil)
    let almostAnchored = CGRect(x: 0.0005, y: 0.0005, width: 1400, height: 900)
    #expect(PlacementGeometry.preparationOrigin(currentFrame: almostAnchored, requestedFrame: requested, in: visible) == nil)
    let displaced = CGRect(x: 0.002, y: 0, width: 1400, height: 900)
    #expect(PlacementGeometry.preparationOrigin(currentFrame: displaced, requestedFrame: requested, in: visible) == CGPoint.zero)
}

@Test func invalidPreparationGeometryDoesNotSuggestAMutation() {
    let valid = CGRect(x: 0, y: 0, width: 1200, height: 800)
    for invalid in [CGRect.zero, CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100),
                    CGRect(x: 0, y: 0, width: -100, height: 100)] {
        #expect(PlacementGeometry.preparationOrigin(currentFrame: invalid, requestedFrame: valid, in: valid) == nil)
        #expect(PlacementGeometry.preparationOrigin(currentFrame: valid, requestedFrame: invalid, in: valid) == nil)
        #expect(PlacementGeometry.preparationOrigin(currentFrame: valid, requestedFrame: valid, in: invalid) == nil)
    }
}
