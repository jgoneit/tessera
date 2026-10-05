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
    /// At an outer horizontal edge, continue from the far opposite display.
    /// A vertical boundary without a neighbor still stops. Displays with no
    /// horizontal separation (including mirrors) do not form a horizontal loop.
    public static func navigationDestination(
        of source: DisplayGeometry, toward direction: GridDirection, in displays: [DisplayGeometry]
    ) -> DisplayGeometry? {
        if let adjacent = neighbor(of: source, toward: direction, in: displays) { return adjacent }
        guard isFinitePositiveRect(source.frame), direction == .left || direction == .right else { return nil }
        let candidates = displays.filter { candidate in
            guard candidate.id != source.id, isFinitePositiveRect(candidate.frame),
                  isFinitePositiveRect(candidate.visibleFrame), candidate.scale.isFinite, candidate.scale > 0 else { return false }
            return direction == .left
                ? candidate.frame.minX >= source.frame.maxX
                : candidate.frame.maxX <= source.frame.minX
        }
        return candidates.min { left, right in
            let leftEdge = direction == .left ? left.frame.maxX : left.frame.minX
            let rightEdge = direction == .left ? right.frame.maxX : right.frame.minX
            if leftEdge != rightEdge { return direction == .left ? leftEdge > rightEdge : leftEdge < rightEdge }
            let leftOverlaps = min(source.frame.maxY, left.frame.maxY) > max(source.frame.minY, left.frame.minY)
            let rightOverlaps = min(source.frame.maxY, right.frame.maxY) > max(source.frame.minY, right.frame.minY)
            if leftOverlaps != rightOverlaps { return leftOverlaps }
            let leftOffset = abs(source.frame.midY - left.frame.midY)
            let rightOffset = abs(source.frame.midY - right.frame.midY)
            if leftOffset != rightOffset { return leftOffset < rightOffset }
            return left.id < right.id
        }
    }

    /// Uses physical arrangement, not enumeration order. Prefer screens whose
    /// perpendicular spans overlap, then the closest edge, perpendicular center,
    /// and stable display ID. Diagonal screens are a fallback; mirrored screens
    /// and screens not beyond the requested edge are not directional neighbors.
    public static func neighbor(
        of source: DisplayGeometry, toward direction: GridDirection, in displays: [DisplayGeometry]
    ) -> DisplayGeometry? {
        guard isFinitePositiveRect(source.frame) else { return nil }
        let horizontal = direction == .left || direction == .right
        let sourceMin = horizontal ? source.frame.minY : source.frame.minX
        let sourceMax = horizontal ? source.frame.maxY : source.frame.maxX
        let candidates = displays.compactMap { candidate -> (DisplayGeometry, Bool, CGFloat, CGFloat)? in
            guard candidate.id != source.id, isFinitePositiveRect(candidate.frame),
                  isFinitePositiveRect(candidate.visibleFrame), candidate.scale.isFinite, candidate.scale > 0 else { return nil }
            let distance: CGFloat = switch direction {
            case .left: source.frame.minX - candidate.frame.maxX
            case .right: candidate.frame.minX - source.frame.maxX
            case .up: candidate.frame.minY - source.frame.maxY
            case .down: source.frame.minY - candidate.frame.maxY
            }
            guard distance >= 0 else { return nil }
            let candidateMin = horizontal ? candidate.frame.minY : candidate.frame.minX
            let candidateMax = horizontal ? candidate.frame.maxY : candidate.frame.maxX
            let overlaps = min(sourceMax, candidateMax) > max(sourceMin, candidateMin)
            let offset = abs((sourceMin / 2 + sourceMax / 2) - (candidateMin / 2 + candidateMax / 2))
            return (candidate, overlaps, distance, offset)
        }
        return candidates.min { left, right in
            if left.1 != right.1 { return left.1 }
            if left.2 != right.2 { return left.2 < right.2 }
            if left.3 != right.3 { return left.3 < right.3 }
            return left.0.id < right.0.id
        }?.0
    }

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
