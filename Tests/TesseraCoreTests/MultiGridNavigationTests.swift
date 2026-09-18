import Foundation
import CoreGraphics
import Testing
@testable import TesseraCore

private let multiGridDisplay = CGRect(x: 0, y: 24, width: 1200, height: 876)
private let layoutSelections: [[LayoutPreset]] = [
    [.twoByTwo], [.threeByTwo], [.fourByTwo],
    [.twoByTwo, .threeByTwo], [.twoByTwo, .fourByTwo], [.threeByTwo, .fourByTwo],
    [.twoByTwo, .threeByTwo, .fourByTwo],
]
private let spatialOrder: [GridPlacement] = [
    GridPlacement(layout: .fourByTwo, target: .column(1)),
    GridPlacement(layout: .threeByTwo, target: .column(1)),
    GridPlacement(layout: .twoByTwo, target: .column(1)),
    GridPlacement(layout: .fourByTwo, target: .column(2)),
    GridPlacement(layout: .threeByTwo, target: .column(2)),
    GridPlacement(layout: .fourByTwo, target: .column(3)),
    GridPlacement(layout: .twoByTwo, target: .column(2)),
    GridPlacement(layout: .threeByTwo, target: .column(3)),
    GridPlacement(layout: .fourByTwo, target: .column(4)),
]

private func arbitraryMultiGrid(_ layouts: [LayoutPreset], center: CGFloat) -> GridNavigation {
    GridNavigation(layouts: layouts,
        windowFrame: CGRect(x: center - 40, y: 100, width: 80, height: 80),
        visibleFrame: multiGridDisplay)
}

private func column(of placement: GridPlacement) -> Int {
    switch placement.target {
    case .column(let column): column
    case .zone(let zone): (zone - 1) % placement.layout.columns + 1
    }
}

private func center(of placement: GridPlacement) -> CGFloat {
    multiGridDisplay.minX + multiGridDisplay.width
        * (CGFloat(column(of: placement)) - 0.5) / CGFloat(placement.layout.columns)
}

private enum NavigationTestHeight: CaseIterable {
    case top, full, bottom

    func placement(in candidate: GridPlacement) -> GridPlacement {
        let columnNumber = column(of: candidate)
        let target: PlacementTarget
        switch self {
        case .top: target = .zone(columnNumber)
        case .full: target = .column(columnNumber)
        case .bottom: target = .zone(candidate.layout.columns + columnNumber)
        }
        return GridPlacement(layout: candidate.layout, target: target)
    }
}

@Test(arguments: layoutSelections)
func everyLayoutSelectionTraversesSpatialOrderAndPreservesHeight(_ layouts: [LayoutPreset]) throws {
    let expected = spatialOrder.filter { layouts.contains($0.layout) }
    #expect(expected.count == layouts.map(\.columns).reduce(0, +))
    let first = try #require(expected.first)
    for height in NavigationTestHeight.allCases {
        let starting = height.placement(in: first)
        let frame = try GridGeometry.frame(in: multiGridDisplay, layout: starting.layout,
            target: starting.target, gap: 8, scale: 2)
        var state = GridNavigation(layouts: layouts, windowFrame: frame, visibleFrame: multiGridDisplay, gap: 8, scale: 2)
        #expect(state.selectedPlacement == starting)
        let initial = state
        for candidate in Array(expected.dropFirst()) + [first] {
            let moved = state.move(.right)
            #expect(moved)
            #expect(state.selectedPlacement == height.placement(in: candidate))
            #expect(state.layout == candidate.layout)
            #expect(state.column == column(of: candidate))
            #expect(state.highlightedZoneIDs.allSatisfy { (1...(state.layout.columns * 2)).contains($0) })
        }
        #expect(state == initial)
        for candidate in expected.reversed() {
            let moved = state.move(.left)
            #expect(moved)
            #expect(state.selectedPlacement == height.placement(in: candidate))
        }
        #expect(state == initial)
    }
}

@Test(arguments: layoutSelections)
func multiGridNearestCenterTiesChooseLeft(_ layouts: [LayoutPreset]) {
    let expected = spatialOrder.filter { layouts.contains($0.layout) }
    for index in 0..<(expected.count - 1) {
        let midpoint = (center(of: expected[index]) + center(of: expected[index + 1])) / 2
        for offset: CGFloat in [-0.25, 0, 0.25] {
            let state = arbitraryMultiGrid(layouts, center: midpoint + offset)
            #expect(state.selectedPlacement == expected[offset <= 0 ? index : index + 1])
        }
    }
}

@Test func firstHorizontalMoveUsesCurrentCenterBeforeCandidateTraversal() {
    let layouts: [LayoutPreset] = [.twoByTwo, .threeByTwo]
    var left = arbitraryMultiGrid(layouts, center: multiGridDisplay.midX)
    #expect(left.selectedPlacement == GridPlacement(layout: .threeByTwo, target: .column(2)))
    let movedLeft = left.move(.left)
    #expect(movedLeft)
    #expect(left.selectedPlacement == GridPlacement(layout: .twoByTwo, target: .column(1)))
    left.move(.left)
    #expect(left.selectedPlacement == GridPlacement(layout: .threeByTwo, target: .column(1)))

    var right = arbitraryMultiGrid(layouts, center: multiGridDisplay.midX)
    let movedRight = right.move(.right)
    #expect(movedRight)
    #expect(right.selectedPlacement == GridPlacement(layout: .twoByTwo, target: .column(2)))
    right.move(.right)
    #expect(right.selectedPlacement == GridPlacement(layout: .threeByTwo, target: .column(3)))
}

@Test func firstHorizontalMoveMayPlaceTheAlreadyHighlightedCandidate() {
    // Center 190 is nearest 3×2 column 1 (200), but is still to its left.
    var state = arbitraryMultiGrid(LayoutPreset.allCases, center: 190)
    let highlighted = GridPlacement(layout: .threeByTwo, target: .column(1))
    #expect(state.selectedPlacement == highlighted)
    let movedToHighlight = state.move(.right)
    #expect(movedToHighlight)
    #expect(state.selectedPlacement == highlighted)
    let next = state.move(.right)
    #expect(next)
    #expect(state.selectedPlacement == GridPlacement(layout: .twoByTwo, target: .column(1)))

    // Moving left from the other side of the same highlighted center also places it.
    var fromRight = arbitraryMultiGrid(LayoutPreset.allCases, center: 210)
    #expect(fromRight.selectedPlacement == highlighted)
    let movedLeftToHighlight = fromRight.move(.left)
    #expect(movedLeftToHighlight)
    #expect(fromRight.selectedPlacement == highlighted)
    fromRight.move(.left)
    #expect(fromRight.selectedPlacement == GridPlacement(layout: .fourByTwo, target: .column(1)))
}

@Test(arguments: layoutSelections)
func firstHorizontalCandidateIsStrictAndWrapsPastScreenEdges(_ layouts: [LayoutPreset]) {
    let expected = spatialOrder.filter { layouts.contains($0.layout) }
    for (index, candidate) in expected.enumerated() {
        var left = arbitraryMultiGrid(layouts, center: center(of: candidate))
        var right = left
        let movedLeft = left.move(.left)
        let movedRight = right.move(.right)
        #expect(movedLeft && movedRight)
        #expect(left.selectedPlacement == expected[index == 0 ? expected.count - 1 : index - 1])
        #expect(right.selectedPlacement == expected[index == expected.count - 1 ? 0 : index + 1])
    }
    for outsideCenter: CGFloat in [-100, 1300] {
        var left = arbitraryMultiGrid(layouts, center: outsideCenter)
        var right = left
        let movedLeft = left.move(.left)
        let movedRight = right.move(.right)
        #expect(movedLeft && movedRight)
        #expect(left.selectedPlacement == expected.last)
        #expect(right.selectedPlacement == expected.first)
    }
}

@Test func initialVerticalMoveUsesNearestFullHeightAndClearsOriginalCenter() {
    for direction: GridDirection in [.up, .down] {
        var state = arbitraryMultiGrid(LayoutPreset.allCases, center: 190)
        let changed = state.move(direction)
        #expect(changed)
        #expect(state.selectedPlacement == GridPlacement(layout: .threeByTwo,
            target: .zone(direction == .up ? 1 : 4)))
        let clamped = state.move(direction)
        #expect(!clamped)
        state.move(.right)
        #expect(state.selectedPlacement == GridPlacement(layout: .twoByTwo,
            target: .zone(direction == .up ? 1 : 3)))
        state.move(direction == .up ? .down : .up)
        #expect(state.selectedPlacement == GridPlacement(layout: .twoByTwo, target: .column(1)))
    }
}

@Test(arguments: layoutSelections)
func exactFramesResumeEveryEnabledLayoutAndHeight(_ layouts: [LayoutPreset]) throws {
    let expected = spatialOrder.filter { layouts.contains($0.layout) }
    let displays = [multiGridDisplay, CGRect(x: -2100.25, y: -800.5, width: 1919.75, height: 1079.25)]
    for display in displays {
        for gap: CGFloat in [0, 8, 12] {
            for scale: CGFloat in [1, 2] {
                for (index, candidate) in expected.enumerated() {
                    for height in NavigationTestHeight.allCases {
                        let placement = height.placement(in: candidate)
                        let frame = try GridGeometry.frame(in: display, layout: placement.layout,
                            target: placement.target, gap: gap, scale: scale)
                        var state = GridNavigation(layouts: layouts, windowFrame: frame,
                            visibleFrame: display, gap: gap, scale: scale)
                        #expect(state.selectedPlacement == placement)
                        // Resuming an exact placement must not use a raw-center first step,
                        // even when pixel allocation moves its center away from the ideal.
                        state.move(.left)
                        let previous = expected[index == 0 ? expected.count - 1 : index - 1]
                        #expect(state.selectedPlacement == height.placement(in: previous))
                    }
                }
            }
        }
    }
}

@Test func selectedLayoutsNormalizeOrderDuplicatesAndEmptyInput() {
    var canonical = arbitraryMultiGrid(LayoutPreset.allCases, center: 190)
    var reordered = arbitraryMultiGrid([.fourByTwo, .twoByTwo, .fourByTwo, .threeByTwo, .twoByTwo], center: 190)
    #expect(canonical == reordered)
    for direction: GridDirection in [.right, .up, .right, .left, .down, .down, .right] {
        canonical.move(direction)
        reordered.move(direction)
        #expect(canonical == reordered)
    }
    #expect(arbitraryMultiGrid([], center: 190) == arbitraryMultiGrid([.threeByTwo], center: 190))
}

@Test(arguments: LayoutPreset.allCases)
func singleLayoutEntryPointMatchesTheSelectedLayoutArray(_ layout: LayoutPreset) {
    for x: CGFloat in [-100, 190, 600, 1300] {
        let frame = CGRect(x: x - 40, y: 100, width: 80, height: 80)
        var original = GridNavigation(layout: layout, windowFrame: frame, visibleFrame: multiGridDisplay)
        var array = GridNavigation(layouts: [layout], windowFrame: frame, visibleFrame: multiGridDisplay)
        #expect(original == array)
        for direction: GridDirection in [.left, .right, .right, .up, .up, .down, .down, .left] {
            let originalMoved = original.move(direction)
            let arrayMoved = array.move(direction)
            #expect(originalMoved == arrayMoved)
            #expect(original == array)
        }
    }
}

@Test(arguments: layoutSelections)
func invalidMultiGridFramesKeepAValidLeftmostCandidate(_ layouts: [LayoutPreset]) {
    let expected = spatialOrder.filter { layouts.contains($0.layout) }
    for invalid in [CGRect.zero, CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100)] {
        for state in [
            GridNavigation(layouts: layouts, windowFrame: invalid, visibleFrame: multiGridDisplay),
            GridNavigation(layouts: layouts, windowFrame: multiGridDisplay, visibleFrame: invalid),
        ] {
            #expect(state.selectedPlacement == expected.first)
            #expect(state.column == 1)
            #expect(state.highlightedZoneIDs == [1, state.layout.columns + 1])
        }
    }
}
