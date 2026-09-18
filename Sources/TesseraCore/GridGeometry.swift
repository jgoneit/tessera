import Foundation
import CoreGraphics

public enum GridGeometryError: Error, Equatable, Sendable {
    case invalidVisibleFrame
    case invalidGap
    case invalidScale
    case invalidZoneID(Int)
    case invalidColumn(Int)
    case unsupportedCoordinateRange
    case insufficientSpace
}

public enum GridGeometry {
    /// Supports a single zone or a full-height column. A column includes the
    /// space between its two zones, retaining only the outer top/bottom gaps.
    public static func frame(
        in visibleFrame: CGRect,
        layout: LayoutPreset,
        target: PlacementTarget,
        gap: CGFloat,
        scale: CGFloat
    ) throws -> CGRect {
        switch target {
        case .zone(let zoneID):
            return try frame(in: visibleFrame, layout: layout, zoneID: zoneID, gap: gap, scale: scale)
        case .column(let column):
            guard (1...layout.columns).contains(column) else {
                throw GridGeometryError.invalidColumn(column)
            }
            let top = try frame(in: visibleFrame, layout: layout, zoneID: column, gap: gap, scale: scale)
            let bottom = try frame(
                in: visibleFrame, layout: layout,
                zoneID: (layout.rows - 1) * layout.columns + column, gap: gap, scale: scale
            )
            return top.union(bottom)
        }
    }

    /// Returns an AppKit-coordinate frame in logical points.
    ///
    /// The visible bounds are rounded inward once in backing pixels. Gaps are
    /// rounded to the nearest pixel; remaining pixels are distributed from left
    /// to right and top to bottom. Thus neighboring cells share exact boundaries
    /// when the gap is zero, even when the available pixel count is not divisible
    /// by the number of cells.
    public static func frame(
        in visibleFrame: CGRect,
        layout: LayoutPreset,
        zoneID: Int,
        gap: CGFloat,
        scale: CGFloat
    ) throws -> CGRect {
        guard isFinitePositiveRect(visibleFrame) else {
            throw GridGeometryError.invalidVisibleFrame
        }
        guard gap.isFinite, gap >= 0 else { throw GridGeometryError.invalidGap }
        guard scale.isFinite, scale > 0 else { throw GridGeometryError.invalidScale }
        guard (1...(layout.columns * layout.rows)).contains(zoneID) else {
            throw GridGeometryError.invalidZoneID(zoneID)
        }

        // Beyond this range CGFloat cannot reliably represent individual pixels.
        // The bound also keeps all subsequent integer arithmetic well within Int.
        let largestExactPixel: CGFloat = 4_503_599_627_370_496 // 2^52
        let pixelValues = [
            visibleFrame.minX * scale, visibleFrame.minY * scale,
            visibleFrame.maxX * scale, visibleFrame.maxY * scale,
            gap * scale,
        ]
        guard pixelValues.allSatisfy({ $0.isFinite && abs($0) <= largestExactPixel }) else {
            throw GridGeometryError.unsupportedCoordinateRange
        }
        let minX = Int(pixelValues[0].rounded(.up))
        let minY = Int(pixelValues[1].rounded(.up))
        let maxX = Int(pixelValues[2].rounded(.down))
        let maxY = Int(pixelValues[3].rounded(.down))
        let gapPixels = Int(pixelValues[4].rounded(.toNearestOrAwayFromZero))
        let availableWidth = maxX - minX - (layout.columns + 1) * gapPixels
        let availableHeight = maxY - minY - (layout.rows + 1) * gapPixels
        guard availableWidth >= layout.columns, availableHeight >= layout.rows else {
            throw GridGeometryError.insufficientSpace
        }

        let column = (zoneID - 1) % layout.columns
        let row = (zoneID - 1) / layout.columns
        let horizontal = partition(availableWidth, count: layout.columns, index: column)
        let vertical = partition(availableHeight, count: layout.rows, index: row)
        let left = minX + gapPixels + horizontal.offset + column * gapPixels
        let top = maxY - gapPixels - vertical.offset - row * gapPixels
        let result = CGRect(
            x: CGFloat(left) / scale,
            y: CGFloat(top - vertical.length) / scale,
            width: CGFloat(horizontal.length) / scale,
            height: CGFloat(vertical.length) / scale
        )
        guard isFinitePositiveRect(result) else {
            throw GridGeometryError.unsupportedCoordinateRange
        }
        return result
    }

    private static func partition(_ length: Int, count: Int, index: Int) -> (offset: Int, length: Int) {
        let base = length / count
        let remainder = length % count
        return (index * base + min(index, remainder), base + (index < remainder ? 1 : 0))
    }
}

/// CGRect standardizes negative dimensions in min/max accessors, so inspect the
/// original dimensions before using those accessors. Also reject endpoint overflow.
func isFinitePositiveRect(_ rect: CGRect) -> Bool {
    rect.origin.x.isFinite && rect.origin.y.isFinite
        && rect.size.width.isFinite && rect.size.height.isFinite
        && rect.size.width > 0 && rect.size.height > 0
        && rect.maxX.isFinite && rect.maxY.isFinite
}
