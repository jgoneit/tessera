import Foundation
import Testing
@testable import TesseraApp

@Suite("Placement readback classification")
struct PlacementResultTests {
    private let requested = CGRect(x: -1511.5, y: 22.5, width: 377.5, height: 470.5)

    @Test("An exact fractional frame on an offset display is applied")
    func exactFractionalFrame() {
        let actual = CGRect(x: -1511.5, y: 22.5, width: 377.5, height: 470.5)
        #expect(PlacementResult.matchesRequestedFrame(actual, requested))
    }

    @Test("Subpixel floating-point noise does not become a false constraint")
    func floatingPointNoise() {
        let actual = CGRect(
            x: requested.minX + 0.0002,
            y: requested.minY - 0.0002,
            width: requested.width + 0.0003,
            height: requested.height - 0.0003
        )
        #expect(PlacementResult.matchesRequestedFrame(actual, requested))
    }

    @Test("A half-pixel adjustment at 2x is a real constraint")
    func halfPixelAdjustment() {
        let halfPixel: CGFloat = 0.5 / 2
        let adjustedFrames = [
            requested.offsetBy(dx: halfPixel, dy: 0),
            requested.offsetBy(dx: 0, dy: -halfPixel),
            CGRect(origin: requested.origin,
                size: CGSize(width: requested.width + halfPixel, height: requested.height)),
            CGRect(origin: requested.origin,
                size: CGSize(width: requested.width, height: requested.height - halfPixel)),
        ]
        for actual in adjustedFrames {
            #expect(!PlacementResult.matchesRequestedFrame(actual, requested))
        }
    }

    @Test("Small origin and size changes cannot accumulate beyond the edge tolerance")
    func accumulatedFarEdgeAdjustment() {
        let rightEdgeAdjusted = CGRect(
            x: requested.minX + 0.00075,
            y: requested.minY,
            width: requested.width + 0.00075,
            height: requested.height
        )
        let bottomEdgeAdjusted = CGRect(
            x: requested.minX,
            y: requested.minY + 0.00075,
            width: requested.width,
            height: requested.height + 0.00075
        )
        #expect(!PlacementResult.matchesRequestedFrame(rightEdgeAdjusted, requested))
        #expect(!PlacementResult.matchesRequestedFrame(bottomEdgeAdjusted, requested))
    }
}
