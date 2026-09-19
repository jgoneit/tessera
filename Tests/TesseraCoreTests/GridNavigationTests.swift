import Foundation
import CoreGraphics
import Testing
@testable import TesseraCore

private let navigationDisplay = CGRect(x: -1200.5, y: 40.25, width: 1200, height: 720)
private let recognitionDisplays = [
    navigationDisplay,
    CGRect(x: 1920.25, y: -1050.5, width: 1919.75, height: 1079.25),
]

private func navigation(_ layout: LayoutPreset, column: Int = 1) -> GridNavigation {
    let center = navigationDisplay.minX + navigationDisplay.width * (CGFloat(column) - 0.5) / CGFloat(layout.columns)
    return GridNavigation(
        layout: layout,
        windowFrame: CGRect(x: center - 100, y: 100, width: 200, height: 300),
        visibleFrame: navigationDisplay
    )
}

@Test(arguments: LayoutPreset.allCases)
func navigationStartsAtNearestColumnWithFullHeight(_ layout: LayoutPreset) {
    for column in 1...layout.columns {
        let state = navigation(layout, column: column)
        #expect(state.column == column)
        #expect(state.selectedTarget == .column(column))
        #expect(state.highlightedZoneIDs == [column, layout.columns + column])
    }
}

@Test(arguments: LayoutPreset.allCases)
func initialColumnBoundaryTiesChooseLeftAndNearbyCentersChooseCorrectSide(_ layout: LayoutPreset) {
    for column in 1..<layout.columns {
        let boundary = navigationDisplay.minX + navigationDisplay.width * CGFloat(column) / CGFloat(layout.columns)
        for offset: CGFloat in [-0.25, 0, 0.25] {
            let state = GridNavigation(
                layout: layout,
                windowFrame: CGRect(x: boundary + offset - 50, y: 50, width: 100, height: 100),
                visibleFrame: navigationDisplay
            )
            #expect(state.column == (offset <= 0 ? column : column + 1))
        }
    }
}

@Test(arguments: LayoutPreset.allCases)
func offscreenCentersChooseNearestEdgeColumn(_ layout: LayoutPreset) {
    for (center, expectedColumn) in [
        (navigationDisplay.minX - 500, 1),
        (navigationDisplay.minX, 1),
        (navigationDisplay.maxX, layout.columns),
        (navigationDisplay.maxX + 500, layout.columns),
    ] {
        let state = GridNavigation(
            layout: layout,
            windowFrame: CGRect(x: center - 50, y: -1000, width: 100, height: 100),
            visibleFrame: navigationDisplay
        )
        #expect(state.selectedTarget == .column(expectedColumn))
    }
}

@Test(arguments: LayoutPreset.allCases)
func initialColumnUsesWindowCenterRatherThanOriginOrVerticalPosition(_ layout: LayoutPreset) {
    let center = navigationDisplay.midX
    for width: CGFloat in [20, 2000] {
        for y: CGFloat in [-2000, 2000] {
            let state = GridNavigation(
                layout: layout,
                windowFrame: CGRect(x: center - width / 2, y: y, width: width, height: 200),
                visibleFrame: navigationDisplay
            )
            #expect(state.selectedTarget == .column((layout.columns + 1) / 2))
        }
    }
}

@Test(arguments: LayoutPreset.allCases)
func horizontalNavigationWrapsAtBothEndsForEachHeight(_ layout: LayoutPreset) {
    for verticalDirection: GridDirection? in [nil, .up, .down] {
        var state = navigation(layout)
        if let verticalDirection { state.move(verticalDirection) }
        for expected in Array(2...layout.columns) + [1] {
            let movedRight = state.move(.right)
            #expect(movedRight)
            #expect(state.column == expected)
            switch verticalDirection {
            case .up: #expect(state.selectedTarget == .zone(expected))
            case .down: #expect(state.selectedTarget == .zone(layout.columns + expected))
            default: #expect(state.selectedTarget == .column(expected))
            }
        }
        let movedLeft = state.move(.left)
        #expect(movedLeft)
        #expect(state.column == layout.columns)
        switch verticalDirection {
        case .up: #expect(state.highlightedZoneIDs == [layout.columns])
        case .down: #expect(state.highlightedZoneIDs == [layout.columns * 2])
        default: #expect(state.highlightedZoneIDs == [layout.columns, layout.columns * 2])
        }
    }
}

@Test(arguments: LayoutPreset.allCases)
func verticalNavigationPassesThroughFullHeightAndClampsAtEnds(_ layout: LayoutPreset) {
    var state = navigation(layout, column: 2)
    let movedToTop = state.move(.up)
    #expect(movedToTop)
    #expect(state.selectedTarget == .zone(2))
    let movedPastTop = state.move(.up)
    #expect(!movedPastTop)
    #expect(state.selectedTarget == .zone(2))
    let movedFromTopToFull = state.move(.down)
    #expect(movedFromTopToFull)
    #expect(state.selectedTarget == .column(2))
    let movedToBottom = state.move(.down)
    #expect(movedToBottom)
    #expect(state.selectedTarget == .zone(layout.columns + 2))
    let movedPastBottom = state.move(.down)
    #expect(!movedPastBottom)
    #expect(state.selectedTarget == .zone(layout.columns + 2))
    let movedFromBottomToFull = state.move(.up)
    #expect(movedFromBottomToFull)
    #expect(state.selectedTarget == .column(2))
}

@Test(arguments: LayoutPreset.allCases)
func mixedNavigationAlwaysSelectsValidConsistentTargets(_ layout: LayoutPreset) {
    var state = navigation(layout)
    let moves: [GridDirection] = [.left, .up, .right, .up, .down, .down, .right, .down, .left, .up]
    for direction in Array(repeating: moves, count: 10).flatMap({ $0 }) {
        state.move(direction)
        #expect((1...layout.columns).contains(state.column))
        #expect(!state.highlightedZoneIDs.isEmpty)
        #expect(state.highlightedZoneIDs.allSatisfy { (1...(layout.columns * layout.rows)).contains($0) })
        switch state.selectedTarget {
        case .column(let column):
            #expect(column == state.column)
            #expect(state.highlightedZoneIDs == [column, column + layout.columns])
        case .zone(let zone):
            #expect((zone - 1) % layout.columns + 1 == state.column)
            #expect(state.highlightedZoneIDs == [zone])
        case .maximized, .screenTop, .screenBottom:
            Issue.record("Grid-only movement must not enter a screen-wide state")
        }
    }
}

@Test func invalidInitialRectanglesSafelyFallBackToFirstFullColumn() {
    let invalidFrames = [
        CGRect.zero,
        CGRect(x: 0, y: 0, width: -100, height: 100),
        CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100),
        CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 100),
        CGRect(x: CGFloat.greatestFiniteMagnitude, y: 0, width: CGFloat.greatestFiniteMagnitude, height: 100),
    ]
    for layout in LayoutPreset.allCases {
        for invalid in invalidFrames {
            for state in [
                GridNavigation(layout: layout, windowFrame: invalid, visibleFrame: navigationDisplay),
                GridNavigation(layout: layout, windowFrame: navigationDisplay, visibleFrame: invalid),
            ] {
                #expect(state.column == 1)
                #expect(state.selectedTarget == .column(1))
                #expect(state.highlightedZoneIDs == [1, layout.columns + 1])
            }
        }
    }
}

@Test(arguments: LayoutPreset.allCases)
func freshNavigationDoesNotRetainPriorSelection(_ layout: LayoutPreset) {
    var previous = navigation(layout, column: 2)
    previous.move(.right)
    previous.move(.down)
    let fresh = navigation(layout, column: 2)
    #expect(fresh.selectedTarget == .column(2))
    #expect(fresh != previous)
}

@Test(arguments: LayoutPreset.allCases)
func reopeningAnArrangedHalfRecognizesItsZoneAndMovesThroughFullHeight(_ layout: LayoutPreset) throws {
    for display in recognitionDisplays {
        for gap: CGFloat in [0, 4, 8, 12] {
            for scale: CGFloat in [1, 2] {
                for zoneID in 1...(layout.columns * layout.rows) {
                    let frame = try GridGeometry.frame(
                        in: display, layout: layout, zoneID: zoneID, gap: gap, scale: scale
                    )
                    var state = GridNavigation(
                        layout: layout, windowFrame: frame, visibleFrame: display, gap: gap, scale: scale
                    )
                    let column = (zoneID - 1) % layout.columns + 1
                    #expect(state.column == column)
                    #expect(state.selectedTarget == .zone(zoneID))
                    #expect(state.highlightedZoneIDs == [zoneID])

                    let towardFull: GridDirection = zoneID <= layout.columns ? .down : .up
                    let moved = state.move(towardFull)
                    #expect(moved)
                    #expect(state.selectedTarget == .column(column))
                    #expect(state.highlightedZoneIDs == [column, layout.columns + column])
                }
            }
        }
    }
}

@Test(arguments: LayoutPreset.allCases)
func reopeningAFullColumnKeepsFullHeight(_ layout: LayoutPreset) throws {
    for display in recognitionDisplays {
        for gap: CGFloat in [0, 4, 8, 12] {
            for scale: CGFloat in [1, 2] {
                for column in 1...layout.columns {
                    let frame = try GridGeometry.frame(
                        in: display, layout: layout, target: .column(column), gap: gap, scale: scale
                    )
                    let state = GridNavigation(
                        layout: layout, windowFrame: frame, visibleFrame: display, gap: gap, scale: scale
                    )
                    #expect(state.selectedTarget == .column(column))
                }
            }
        }
    }
}

@Test(arguments: LayoutPreset.allCases)
func anArbitraryOrAdjustedWindowStillStartsAtTheNearestFullColumn(_ layout: LayoutPreset) throws {
    for display in recognitionDisplays {
        for gap: CGFloat in [0, 4, 8, 12] {
            for scale: CGFloat in [1, 2] {
                for column in 1...layout.columns {
                    let arranged = try GridGeometry.frame(
                        in: display, layout: layout, zoneID: column, gap: gap, scale: scale
                    )
                    let adjusted = arranged.insetBy(dx: 0.25, dy: 0.25)
                    let arbitrary = CGRect(x: arranged.midX - 50, y: display.midY - 50, width: 100, height: 100)
                    for frame in [adjusted, arbitrary] {
                        let state = GridNavigation(
                            layout: layout, windowFrame: frame, visibleFrame: display, gap: gap, scale: scale
                        )
                        #expect(state.selectedTarget == .column(column))
                    }
                }
            }
        }
    }
}

@Test(arguments: LayoutPreset.allCases)
func initialHeightRecognitionToleratesOnlyNoiseOnAllFourEdges(_ layout: LayoutPreset) throws {
    let exact = try GridGeometry.frame(
        in: navigationDisplay, layout: layout, zoneID: 2, gap: 8, scale: 2
    )
    let noise = CGRect(x: exact.minX + 0.0002, y: exact.minY - 0.0002,
        width: exact.width + 0.0003, height: exact.height - 0.0003)
    let noisy = GridNavigation(layout: layout, windowFrame: noise,
        visibleFrame: navigationDisplay, gap: 8, scale: 2)
    #expect(noisy.selectedTarget == .zone(2))

    let accumulatedEdgeChange = CGRect(x: exact.minX + 0.00075, y: exact.minY,
        width: exact.width + 0.00075, height: exact.height)
    let adjusted = GridNavigation(layout: layout, windowFrame: accumulatedEdgeChange,
        visibleFrame: navigationDisplay, gap: 8, scale: 2)
    #expect(adjusted.selectedTarget == .column(2))
}

@Test(arguments: LayoutPreset.allCases)
func invalidRecognitionSettingsSafelyKeepTheNearestFullColumn(_ layout: LayoutPreset) throws {
    let frame = try GridGeometry.frame(
        in: navigationDisplay, layout: layout, zoneID: 2, gap: 8, scale: 2
    )
    let invalidSettings: [(gap: CGFloat, scale: CGFloat)] = [
        (-1, 2), (.nan, 2), (.infinity, 2), (1000, 2),
        (8, 0), (8, -1), (8, .nan), (8, .infinity),
    ]
    for settings in invalidSettings {
        let state = GridNavigation(layout: layout, windowFrame: frame,
            visibleFrame: navigationDisplay, gap: settings.gap, scale: settings.scale)
        #expect(state.selectedTarget == .column(2))
    }
}
