import CoreGraphics
import Foundation
import TesseraCore

/// A synchronous, bounded AX transaction. The actor supplies the actual window
/// operations; tests can supply a window with the same resize constraints.
enum WindowPlacement {
    static func perform(
        frame: CGRect,
        visibleFrame: CGRect,
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

        do {
            guard isValid(frame), isValid(visibleFrame), contains(frame, in: visibleFrame) else {
                throw WindowSystemError.invalidGeometry
            }
            trace("requested", frame)
            try validateBeforeWrite()
            operation = "reading the initial window frame"
            let initial = try observe("initial")

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
                try setPosition(origin)
                operation = "reading the preparation move result"
                _ = try observe("prepared")
            }

            operation = "checking the window before resizing"
            try validateBeforeWrite()
            attemptedWrite = true
            observedFrame = nil
            operation = "resizing the window"
            try setSize(frame.size)
            operation = "reading the resize result"
            let resized = try observe("resized")

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
            try setPosition(origin)
            operation = "reading the final window frame"
            let actual = try observe("final")

            if PlacementResult.matchesRequestedFrame(actual, frame), contains(actual, in: visibleFrame) {
                return PlacementResult(outcome: .applied, message: L10n.text("Window arranged."), actualFrame: actual)
            }
            let message = contains(actual, in: visibleFrame)
                ? L10n.text("The window did not accept the exact requested size or position. It remains within the usable display area.")
                : L10n.text("The window did not accept the exact requested size or position. It could not be fitted fully inside the usable display area.")
            return PlacementResult(outcome: .constrained, message: message, actualFrame: actual)
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
