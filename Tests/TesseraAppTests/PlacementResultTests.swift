import Foundation
import Testing
@testable import TesseraApp

@Suite("Placement readback classification")
struct PlacementResultTests {
    private let requested = CGRect(x: -1511.5, y: 22.5, width: 377.5, height: 470.5)

    @Test("Only exact success and classified size adjustments use brief feedback")
    func feedbackDuration() {
        let cases: [(PlacementResult.Outcome, PlacementResult.ConstraintReason?, Duration)] = [
            (.applied, nil, .seconds(1)),
            (.constrained, .sizeAdjusted, .seconds(1)),
            (.constrained, .positionMismatch, .seconds(4)),
            (.constrained, .outsideVisibleArea, .seconds(4)),
            (.constrained, nil, .seconds(4)),
            (.unavailable, nil, .seconds(4)),
            (.failed, nil, .seconds(4)),
        ]
        for (outcome, reason, duration) in cases {
            let result = PlacementResult(outcome: outcome, message: "Feedback", actualFrame: nil,
                constraintReason: reason)
            #expect(result.feedbackDuration == duration)
        }
    }

    @Test("Existing result construction leaves the constraint cause unclassified")
    func defaultConstraintReason() {
        let result = PlacementResult(outcome: .constrained, message: "Legacy feedback", actualFrame: requested)
        #expect(result.constraintReason == nil)
        #expect(result.actualFrame == requested)
        #expect(result.feedbackDuration == .seconds(4))
    }

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
