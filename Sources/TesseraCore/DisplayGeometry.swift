import Foundation
import CoreGraphics

public enum CoordinateSpace {
    /// Converts in either direction between AppKit's bottom-left desktop space
    /// and AX's top-left desktop space. Always use the primary screen's top,
    /// including when converting a rectangle on a secondary display.
    public static func flip(_ rect: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: rect.origin.x, y: primaryTop - rect.maxY, width: rect.width, height: rect.height)
    }
}

public struct DisplayGeometry: Sendable, Equatable {
    public let id: UInt32
    public let frame: CGRect
    public let visibleFrame: CGRect
    public let scale: CGFloat

    public init(id: UInt32, frame: CGRect, visibleFrame: CGRect, scale: CGFloat) {
        self.id = id
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.scale = scale
    }
}

public enum DisplaySelection {
    /// Uses largest overlap with the full screen frame. Exact ties retain screen
    /// enumeration order. A window outside every display uses the nearest center.
    /// Invalid windows or a list without any usable displays have no selection.
    public static func bestDisplay(for window: CGRect, in displays: [DisplayGeometry]) -> DisplayGeometry? {
        guard isFinitePositiveRect(window) else { return nil }
        let usable = displays.filter {
            isFinitePositiveRect($0.frame) && isFinitePositiveRect($0.visibleFrame)
                && $0.scale.isFinite && $0.scale > 0
        }
        var overlapped: DisplayGeometry?
        var greatestArea: CGFloat = 0
        var greatestLogArea: CGFloat = -.infinity
        for display in usable {
            let intersection = window.intersection(display.frame)
            guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { continue }
            let area = intersection.width * intersection.height
            // Log area disambiguates products that overflow; ordinary display
            // dimensions retain direct multiplication and exact tie behavior.
            let logArea = log(intersection.width) + log(intersection.height)
            if overlapped == nil || area > greatestArea
                || (!area.isFinite && !greatestArea.isFinite && logArea > greatestLogArea) {
                overlapped = display
                greatestArea = area
                greatestLogArea = logArea
            }
        }
        if let overlapped { return overlapped }

        var nearest: DisplayGeometry?
        var nearestDistance: CGFloat = .infinity
        for display in usable {
            // Scaling before subtraction and hypot avoids overflow for distant
            // finite coordinates; the common scale does not change ordering.
            let distance = hypot(
                window.midX / 4 - display.frame.midX / 4,
                window.midY / 4 - display.frame.midY / 4
            )
            if nearest == nil || distance < nearestDistance {
                nearest = display
                nearestDistance = distance
            }
        }
        return nearest
    }
}

public enum PlacementGeometry {
    /// AX/top-left coordinates. Suggests one move before a resize only when the
    /// requested size would extend beyond the visible frame at the current origin.
    /// The envelope accommodates both sizes while either axis changes. An
    /// oversized envelope is anchored at the visible minimum without claiming it
    /// fits. Invalid frames and origin changes within 0.001 pt produce no move;
    /// callers remain responsible for input validation and AX result verification.
    public static func preparationOrigin(
        currentFrame: CGRect,
        requestedFrame: CGRect,
        in visibleFrame: CGRect
    ) -> CGPoint? {
        guard isFinitePositiveRect(currentFrame), isFinitePositiveRect(requestedFrame),
              isFinitePositiveRect(visibleFrame) else { return nil }
        let resizedAtCurrentOrigin = CGRect(origin: currentFrame.origin, size: requestedFrame.size)
        guard !visibleFrame.contains(resizedAtCurrentOrigin) else { return nil }

        let envelope = CGSize(
            width: max(currentFrame.width, requestedFrame.width),
            height: max(currentFrame.height, requestedFrame.height)
        )
        let origin = clampedOrigin(for: envelope, desiredOrigin: currentFrame.origin, in: visibleFrame)
        let epsilon: CGFloat = 0.001
        guard abs(origin.x - currentFrame.origin.x) > epsilon
                || abs(origin.y - currentFrame.origin.y) > epsilon else { return nil }
        return origin
    }

    /// AX/top-left coordinates. Keeps a resized window inside the visible frame
    /// whenever it fits; an oversized axis is anchored at the visible minimum.
    public static func clampedOrigin(for size: CGSize, desiredOrigin: CGPoint, in visibleFrame: CGRect) -> CGPoint {
        CGPoint(
            x: max(visibleFrame.minX, min(desiredOrigin.x, visibleFrame.maxX - size.width)),
            y: max(visibleFrame.minY, min(desiredOrigin.y, visibleFrame.maxY - size.height))
        )
    }
}
