import CoreGraphics
import Foundation
import TesseraCore

/// A synchronous, bounded AX transaction. The actor supplies the actual window
/// operations; tests can supply a window with the same resize constraints.
enum WindowPlacement {
    static func perform(
        frame: CGRect,
        visibleFrame: CGRect,
        retrySizeAfterMove: Bool = false,
        readFrame: () throws -> CGRect,
        validate: () throws -> Void,
        setSize: (CGSize) throws -> Void,
        setPosition: (CGPoint) throws -> Void,
        trace: (String, CGRect) -> Void = { _, _ in }
    ) -> PlacementResult {
        var attemptedWrite = false
        var failedRead = false
        var observedFrame: CGRect?
        var operation = "checking the window"

        func validateBeforeWrite() throws {
            try Task.checkCancellation()
            try validate()
            // Validation can block in AX IPC, so cancellation must be checked
            // again before the following attribute write.
            try Task.checkCancellation()
        }

        func observe(_ stage: String) throws -> CGRect {
            // A failed read must never expose an older frame as the new result.
            observedFrame = nil
            do {
                let actual = try readFrame()
                guard isValid(actual) else { throw WindowSystemError.invalidGeometry }
                observedFrame = actual
                trace(stage, actual)
                return actual
            } catch {
                failedRead = true
                throw error
            }
        }

        /// Writes, then reads the result back as `stage`. Validation has just
        /// confirmed that the attribute is settable, yet some apps apply a write
        /// and still reply attribute-unsupported (Gemini does for every size
        /// change). That reply is accepted only when the readback shows the
        /// write moved the window toward the request; otherwise it stays
        /// terminal with that readback as its result. Nothing is written again.
        func write(_ apply: () throws -> Void, reading: String, stage: String,
                   progressed: (CGRect) -> Bool) throws -> CGRect {
            let writing = operation
            do {
                try apply()
            } catch let error as WindowSystemError where error.isAttributeUnsupported {
                operation = reading
                let actual = try observe(stage)
                guard progressed(actual) else {
                    operation = writing
                    throw error
                }
                trace("acceptedDespiteReply", actual)
                return actual
            }
            operation = reading
            return try observe(stage)
        }
        func resize(to size: CGSize, from before: CGRect, stage: String) throws -> CGRect {
            try write({ try setSize(size) }, reading: "reading the resize result", stage: stage) {
                movedToward(CGPoint(x: $0.width, y: $0.height), from: CGPoint(x: before.width, y: before.height),
                    to: CGPoint(x: size.width, y: size.height))
            }
        }
        func move(to origin: CGPoint, from before: CGRect, reading: String, stage: String) throws -> CGRect {
            try write({ try setPosition(origin) }, reading: reading, stage: stage) {
                movedToward($0.origin, from: before.origin, to: origin)
            }
        }

        do {
            guard isValid(frame), isValid(visibleFrame), contains(frame, in: visibleFrame) else {
                throw WindowSystemError.invalidGeometry
            }
            trace("requested", frame)
            try validateBeforeWrite()
            operation = "reading the initial window frame"
            let initial = try observe("initial")
            var current = initial

            if let origin = PlacementGeometry.preparationOrigin(
                currentFrame: initial, requestedFrame: frame, in: visibleFrame
            ) {
                operation = "checking the window before the preparation move"
                try validateBeforeWrite()
                // A failed AX setter can still have changed the window. Mark
                // the attempt before calling it, including this first move.
                attemptedWrite = true
                observedFrame = nil
                operation = "preparing room for the resize"
                current = try move(to: origin, from: initial,
                    reading: "reading the preparation move result", stage: "prepared")
            }

            operation = "checking the window before resizing"
            try validateBeforeWrite()
            attemptedWrite = true
            observedFrame = nil
            operation = "resizing the window"
            let resized = try resize(to: frame.size, from: current, stage: "resized")

            // Always use the size the application actually accepted. This is
            // AX top-left space; oversized windows remain anchored at minY.
            let origin = PlacementGeometry.clampedOrigin(
                for: resized.size, desiredOrigin: frame.origin, in: visibleFrame
            )
            operation = "checking the window before the final move"
            try validateBeforeWrite()
            attemptedWrite = true
            observedFrame = nil
            operation = "moving the resized window"
            var actual = try move(to: origin, from: resized,
                reading: "reading the final window frame", stage: "final")

            // Some applications use their previous display's size limit until
            // the final move is processed. Retry once only when crossing screens;
            // permanent app constraints still produce the usual constrained result.
            if retrySizeAfterMove, !PlacementResult.matchesRequestedFrame(actual, frame) {
                operation = "checking the window before resizing"
                try validateBeforeWrite()
                observedFrame = nil
                operation = "resizing the window"
                let retried = try resize(to: frame.size, from: actual, stage: "resizedAfterDisplayMove")
                operation = "checking the window before the final move"
                try validateBeforeWrite()
                observedFrame = nil
                operation = "moving the resized window"
                actual = try move(to: PlacementGeometry.clampedOrigin(
                    for: retried.size, desiredOrigin: frame.origin, in: visibleFrame), from: retried,
                    reading: "reading the final window frame", stage: "final")
            }

            if PlacementResult.matchesRequestedFrame(actual, frame), contains(actual, in: visibleFrame) {
                return PlacementResult(outcome: .applied, message: L10n.text("Window arranged."), actualFrame: actual)
            }
            let reason: PlacementResult.ConstraintReason
            let message: String
            if !contains(actual, in: visibleFrame) {
                reason = .outsideVisibleArea
                message = L10n.text("The window could not fit fully inside the usable display area.")
            } else {
                // Use final readback, not the requested size: an app can accept
                // a larger height while still aligning correctly at either edge.
                let acceptedOrigin = PlacementGeometry.clampedOrigin(
                    for: actual.size, desiredOrigin: frame.origin, in: visibleFrame
                )
                let aligned = CGRect(origin: acceptedOrigin, size: actual.size)
                if PlacementResult.matchesRequestedFrame(actual, aligned) {
                    reason = .sizeAdjusted
                    message = L10n.text("Arranged · Adjusted to app size")
                } else {
                    reason = .positionMismatch
                    message = L10n.text("The window could not be aligned to the requested position.")
                }
            }
            return PlacementResult(outcome: .constrained, message: message, actualFrame: actual,
                constraintReason: reason)
        } catch {
            // A setter error may be ambiguous. A single diagnostic read can
            // reveal its result, but an already failed read is never retried.
            if attemptedWrite, observedFrame == nil, !failedRead,
               let actual = try? readFrame(), isValid(actual) {
                observedFrame = actual
            }
            let cancelled = error is CancellationError
            guard attemptedWrite else {
                return PlacementResult(outcome: .unavailable,
                    message: cancelled
                        ? L10n.text("Arrangement was cancelled before the window was changed.")
                        : UserFacingError.message(error),
                    actualFrame: observedFrame)
            }
            let detail = cancelled ? L10n.text("Arrangement was cancelled.") : UserFacingError.message(error)
            return PlacementResult(outcome: .failed,
                message: L10n.format("Placement stopped while %@. The window may be partly arranged. %@", L10n.text(operation), detail),
                actualFrame: observedFrame)
        }
    }

    /// True when `actual` matches `target`, or is closer to it than `before`
    /// on at least one axis without moving away on either. Drift away from
    /// the request is never taken as evidence that a write took effect.
    static func movedToward(_ actual: CGPoint, from before: CGPoint, to target: CGPoint) -> Bool {
        let tolerance: CGFloat = 0.5
        let axes = [(abs(actual.x - target.x), abs(before.x - target.x)),
                    (abs(actual.y - target.y), abs(before.y - target.y))]
        if axes.allSatisfy({ $0.0 <= tolerance }) { return true }
        return axes.allSatisfy { $0.0 <= $0.1 + tolerance } && axes.contains { $0.0 < $0.1 - tolerance }
    }

    private static func isValid(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite && frame.origin.y.isFinite
            && frame.size.width.isFinite && frame.size.height.isFinite
            && frame.size.width > 0 && frame.size.height > 0
            && frame.maxX.isFinite && frame.maxY.isFinite
    }

    private static func contains(_ frame: CGRect, in bounds: CGRect) -> Bool {
        let epsilon: CGFloat = 0.001
        return frame.minX >= bounds.minX - epsilon && frame.minY >= bounds.minY - epsilon
            && frame.maxX <= bounds.maxX + epsilon && frame.maxY <= bounds.maxY + epsilon
    }
}
