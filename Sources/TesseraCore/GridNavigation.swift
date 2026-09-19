import Foundation
import CoreGraphics

/// Zone and column identifiers are both one-based. Screen targets span all columns.
public enum PlacementTarget: Equatable, Sendable {
    case zone(Int)
    case column(Int)
    case maximized
    case screenTop
    case screenBottom
}

/// An immutable destination: the target's identifiers are local to its layout.
public struct GridPlacement: Equatable, Sendable {
    public let layout: LayoutPreset
    public let target: PlacementTarget

    public init(layout: LayoutPreset, target: PlacementTarget) {
        self.layout = layout
        self.target = target
    }
}

public enum GridDirection: CaseIterable, Equatable, Sendable {
    case left
    case right
    case up
    case down
}

/// Pure selector state; it never moves a window or decides when to commit.
public struct GridNavigation: Equatable, Sendable {
    private enum Height: Equatable, Sendable {
        case top
        case full
        case bottom
    }

    private struct Candidate: Equatable, Sendable {
        let layout: LayoutPreset
        let column: Int
        var centerNumerator: Int { 2 * column - 1 }
        var centerDenominator: Int { 2 * layout.columns }
        var normalizedCenter: CGFloat { CGFloat(centerNumerator) / CGFloat(centerDenominator) }
    }

    /// Strict neighbors of an arbitrary window's original horizontal center.
    /// Precomputing both indices preserves that center's first-move semantics
    /// without replacing it with the initially highlighted candidate's center.
    private struct InitialHorizontalTargets: Equatable, Sendable {
        let left: Int
        let right: Int
    }

    private let candidates: [Candidate]
    private var candidateIndex = 0
    private var height: Height = .full
    private var isScreenWidth = false
    private var initialHorizontalTargets: InitialHorizontalTargets?

    public var layout: LayoutPreset { candidates[candidateIndex].layout }
    public var column: Int { candidates[candidateIndex].column }

    /// Convenience entry point retaining the single-layout API.
    public init(
        layout: LayoutPreset,
        windowFrame: CGRect,
        visibleFrame: CGRect,
        gap: CGFloat = 8,
        scale: CGFloat = 1
    ) {
        self.init(layouts: [layout], windowFrame: windowFrame, visibleFrame: visibleFrame, gap: gap, scale: scale)
    }

    /// Candidates from all enabled layouts are ordered by normalized column
    /// center. Input order and duplicate layouts have no effect; an empty array
    /// safely falls back to 3×2. Frames use AppKit's bottom-left coordinate space.
    ///
    /// An exact existing top/full/bottom placement resumes that candidate and
    /// height. Other windows highlight the nearest full-height candidate (ties
    /// left), but their first horizontal move uses the original window center.
    /// Invalid rectangles start at the leftmost full-height candidate. Invalid
    /// gap/scale values disable exact recognition without throwing or moving.
    public init(
        layouts: [LayoutPreset],
        windowFrame: CGRect,
        visibleFrame: CGRect,
        gap: CGFloat = 8,
        scale: CGFloat = 1
    ) {
        var enabled = LayoutPreset.allCases.filter { layouts.contains($0) }
        if enabled.isEmpty { enabled = [.threeByTwo] }
        candidates = enabled.flatMap { layout in
            (1...layout.columns).map { Candidate(layout: layout, column: $0) }
        }.sorted { left, right in
            // Rational comparison avoids rounding the ordering of centers.
            let lhs = left.centerNumerator * right.centerDenominator
            let rhs = right.centerNumerator * left.centerDenominator
            if lhs != rhs { return lhs < rhs }
            return left.layout.columns < right.layout.columns
        }
        guard isFinitePositiveRect(windowFrame), isFinitePositiveRect(visibleFrame),
              windowFrame.midX.isFinite else { return }

        // Screen-wide placements take precedence and do not depend on the
        // currently enabled grid. The retained candidate is only a preview.
        let screenTargets: [(PlacementTarget, Height)] = [
            (.maximized, .full), (.screenTop, .top), (.screenBottom, .bottom),
        ]
        for (target, matchedHeight) in screenTargets {
            if let frame = try? GridGeometry.frame(
                in: visibleFrame, layout: layout, target: target, gap: gap, scale: scale
            ), Self.matchesFrame(windowFrame, frame) {
                candidateIndex = nearestCenterCandidate
                height = matchedHeight
                isScreenWidth = true
                return
            }
        }

        for (index, candidate) in candidates.enumerated() {
            let targets: [(PlacementTarget, Height)] = [
                (.zone(candidate.column), .top),
                (.column(candidate.column), .full),
                (.zone(candidate.layout.columns + candidate.column), .bottom),
            ]
            for (target, matchedHeight) in targets {
                if let frame = try? GridGeometry.frame(
                    in: visibleFrame, layout: candidate.layout, target: target, gap: gap, scale: scale
                ), Self.matchesFrame(windowFrame, frame) {
                    candidateIndex = index
                    height = matchedHeight
                    return
                }
            }
        }

        let center = windowFrame.midX
        let centers = candidates.map { visibleFrame.minX + visibleFrame.width * $0.normalizedCenter }
        // Midpoint boundaries choose the nearest normalized center; <= keeps
        // exact ties on the left and avoids comparing rounded distance pairs.
        for index in 1..<centers.count {
            let boundary = centers[index - 1] + (centers[index] - centers[index - 1]) / 2
            guard center > boundary else { break }
            candidateIndex = index
        }
        initialHorizontalTargets = InitialHorizontalTargets(
            left: centers.lastIndex(where: { $0 < center }) ?? centers.count - 1,
            right: centers.firstIndex(where: { $0 > center }) ?? 0
        )
    }

    public var selectedTarget: PlacementTarget {
        if isScreenWidth {
            return switch height {
            case .top: .screenTop
            case .full: .maximized
            case .bottom: .screenBottom
            }
        }
        return switch height {
        case .top: .zone(column)
        case .full: .column(column)
        case .bottom: .zone(layout.columns + column)
        }
    }

    public var selectedPlacement: GridPlacement { GridPlacement(layout: layout, target: selectedTarget) }

    public var highlightedZoneIDs: [Int] {
        switch selectedTarget {
        case .zone(let id): [id]
        case .column(let id): [id, layout.columns + id]
        case .maximized: Array(1...(layout.columns * layout.rows))
        case .screenTop: Array(1...layout.columns)
        case .screenBottom: Array((layout.columns + 1)...(layout.columns * layout.rows))
        }
    }

    /// Sets a screen-wide full-height logical state. Callers may reapply its
    /// frame even when this returns false; maximizing is not a restore toggle.
    @discardableResult
    public mutating func maximize() -> Bool {
        let changed = !isScreenWidth || height != .full
        candidateIndex = nearestCenterCandidate
        height = .full
        isScreenWidth = true
        initialHorizontalTargets = nil
        return changed
    }

    private var nearestCenterCandidate: Int {
        var closest = 0
        for index in 1..<candidates.count {
            let previous = candidates[index - 1].normalizedCenter
            let next = candidates[index].normalizedCenter
            guard 0.5 > previous + (next - previous) / 2 else { break }
            closest = index
        }
        return closest
    }

    /// Horizontal movement follows candidate order, wraps, and retains height
    /// across layouts. Vertical movement follows top ↔ full ↔ bottom and stops
    /// at the ends. True means an accepted placement step, including the first
    /// move from an arbitrary window into its already highlighted candidate.
    @discardableResult
    public mutating func move(_ direction: GridDirection) -> Bool {
        switch direction {
        case .left:
            if isScreenWidth {
                candidateIndex = candidates.lastIndex(where: { $0.normalizedCenter < 0.5 }) ?? candidates.count - 1
            } else {
                candidateIndex = initialHorizontalTargets?.left
                    ?? (candidateIndex == 0 ? candidates.count - 1 : candidateIndex - 1)
            }
            isScreenWidth = false
        case .right:
            if isScreenWidth {
                candidateIndex = candidates.firstIndex(where: { $0.normalizedCenter > 0.5 }) ?? 0
            } else {
                candidateIndex = initialHorizontalTargets?.right
                    ?? (candidateIndex == candidates.count - 1 ? 0 : candidateIndex + 1)
            }
            isScreenWidth = false
        case .up:
            switch height {
            case .top: return false
            case .full: height = .top
            case .bottom: height = .full
            }
        case .down:
            switch height {
            case .top: height = .full
            case .full: height = .bottom
            case .bottom: return false
            }
        }
        initialHorizontalTargets = nil
        return true
    }

    private static func matchesFrame(_ actual: CGRect, _ expected: CGRect) -> Bool {
        let epsilon: CGFloat = 0.001
        return abs(actual.minX - expected.minX) <= epsilon
            && abs(actual.minY - expected.minY) <= epsilon
            && abs(actual.maxX - expected.maxX) <= epsilon
            && abs(actual.maxY - expected.maxY) <= epsilon
    }
}
