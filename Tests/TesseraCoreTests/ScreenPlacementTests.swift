import Foundation
import CoreGraphics
import Testing
@testable import TesseraCore

private let screenPlacementDisplays = [
    CGRect(x: 0, y: 24, width: 1440, height: 876),
    CGRect(x: -2560, y: -720, width: 2560, height: 1417),
    CGRect(x: -100.2, y: -47.7, width: 1000.9, height: 700.4),
]
private let screenPlacementSelections: [[LayoutPreset]] = [
    [.twoByTwo], [.threeByTwo], [.fourByTwo],
    [.twoByTwo, .threeByTwo], [.twoByTwo, .fourByTwo], [.threeByTwo, .fourByTwo],
    [.twoByTwo, .threeByTwo, .fourByTwo],
]
private let screenTargets: [PlacementTarget] = [.maximized, .screenTop, .screenBottom]

@Test func maximizedFramesIgnoreGapAndLayoutWhileAligningInsideVisibleBounds() throws {
    for display in screenPlacementDisplays {
        for scale: CGFloat in [1, 2] {
            let expected = CGRect(
                x: (display.minX * scale).rounded(.up) / scale,
                y: (display.minY * scale).rounded(.up) / scale,
                width: ((display.maxX * scale).rounded(.down) - (display.minX * scale).rounded(.up)) / scale,
                height: ((display.maxY * scale).rounded(.down) - (display.minY * scale).rounded(.up)) / scale
            )
            for layout in LayoutPreset.allCases {
                for gap: CGFloat in [0, 4, 8, 12, 1000] {
                    let actual = try GridGeometry.frame(in: display, layout: layout,
                        target: .maximized, gap: gap, scale: scale)
                    #expect(actual == expected)
                    #expect(display.contains(actual))
                }
            }
        }
    }
}

@Test func screenHalvesSpanTheGridRowAndPreserveOuterAndMiddlePixelGaps() throws {
    for display in screenPlacementDisplays {
        for scale: CGFloat in [1, 2] {
            for gap: CGFloat in [0, 0.3, 4, 8, 12] {
                let gapInPoints = (gap * scale).rounded(.toNearestOrAwayFromZero) / scale
                var referenceTop: CGRect?
                var referenceBottom: CGRect?
                for layout in LayoutPreset.allCases {
                    let top = try GridGeometry.frame(in: display, layout: layout,
                        target: .screenTop, gap: gap, scale: scale)
                    let bottom = try GridGeometry.frame(in: display, layout: layout,
                        target: .screenBottom, gap: gap, scale: scale)
                    let topLeft = try GridGeometry.frame(in: display, layout: layout,
                        zoneID: 1, gap: gap, scale: scale)
                    let topRight = try GridGeometry.frame(in: display, layout: layout,
                        zoneID: layout.columns, gap: gap, scale: scale)
                    let bottomLeft = try GridGeometry.frame(in: display, layout: layout,
                        zoneID: layout.columns + 1, gap: gap, scale: scale)
                    let bottomRight = try GridGeometry.frame(in: display, layout: layout,
                        zoneID: layout.columns * 2, gap: gap, scale: scale)
                    #expect(top == topLeft.union(topRight))
                    #expect(bottom == bottomLeft.union(bottomRight))
                    #expect(top.minY - bottom.maxY == gapInPoints)
                    #expect(abs(top.height - bottom.height) <= 1 / scale)
                    if let referenceTop { #expect(top == referenceTop) }
                    if let referenceBottom { #expect(bottom == referenceBottom) }
                    referenceTop = top
                    referenceBottom = bottom
                    for frame in [top, bottom] {
                        #expect(display.contains(frame))
                        #expect(frame.minX - (display.minX * scale).rounded(.up) / scale == gapInPoints)
                        #expect((display.maxX * scale).rounded(.down) / scale - frame.maxX == gapInPoints)
                        for boundary in [frame.minX, frame.maxX, frame.minY, frame.maxY] {
                            #expect(boundary * scale == (boundary * scale).rounded())
                        }
                    }
                    #expect((display.maxY * scale).rounded(.down) / scale - top.maxY == gapInPoints)
                    #expect(bottom.minY - (display.minY * scale).rounded(.up) / scale == gapInPoints)
                }
            }
        }
    }
}

@Test func screenFramesDoNotRequireEnoughWidthForEveryGridColumn() throws {
    let narrow = CGRect(x: -10, y: -20, width: 17, height: 30)
    let maximized = try GridGeometry.frame(in: narrow, layout: .fourByTwo,
        target: .maximized, gap: 8, scale: 1)
    let top = try GridGeometry.frame(in: narrow, layout: .fourByTwo,
        target: .screenTop, gap: 8, scale: 1)
    let bottom = try GridGeometry.frame(in: narrow, layout: .fourByTwo,
        target: .screenBottom, gap: 8, scale: 1)
    #expect(maximized == narrow)
    #expect(top == CGRect(x: -2, y: -1, width: 1, height: 3))
    #expect(bottom == CGRect(x: -2, y: -12, width: 1, height: 3))
}

@Test func screenFramesRejectInvalidInputsAndInsufficientPixels() {
    let valid = screenPlacementDisplays[0]
    for target in screenTargets {
        #expect(throws: GridGeometryError.invalidVisibleFrame) {
            try GridGeometry.frame(in: .zero, layout: .threeByTwo, target: target, gap: 8, scale: 2)
        }
        for gap: CGFloat in [-1, .nan, .infinity] {
            #expect(throws: GridGeometryError.invalidGap) {
                try GridGeometry.frame(in: valid, layout: .threeByTwo, target: target, gap: gap, scale: 2)
            }
        }
        for scale: CGFloat in [0, -1, .nan, .infinity] {
            #expect(throws: GridGeometryError.invalidScale) {
                try GridGeometry.frame(in: valid, layout: .threeByTwo, target: target, gap: 8, scale: scale)
            }
        }
        #expect(throws: GridGeometryError.insufficientSpace) {
            try GridGeometry.frame(in: CGRect(x: 0, y: 0, width: 0.2, height: 0.2),
                layout: .threeByTwo, target: target, gap: 0, scale: 1)
        }
        #expect(throws: GridGeometryError.unsupportedCoordinateRange) {
            try GridGeometry.frame(in: CGRect(x: 1e100, y: 0, width: 1e100, height: 100),
                layout: .threeByTwo, target: target, gap: 0, scale: 1)
        }
    }
    for target: PlacementTarget in [.screenTop, .screenBottom] {
        #expect(throws: GridGeometryError.insufficientSpace) {
            try GridGeometry.frame(in: valid, layout: .twoByTwo, target: target, gap: 1000, scale: 1)
        }
    }
}

private func screenState(_ layouts: [LayoutPreset], target: PlacementTarget = .maximized) throws -> GridNavigation {
    let display = screenPlacementDisplays[0]
    let frame = try GridGeometry.frame(in: display, layout: .threeByTwo, target: target, gap: 8, scale: 2)
    return GridNavigation(layouts: layouts, windowFrame: frame, visibleFrame: display, gap: 8, scale: 2)
}

@Test(arguments: screenPlacementSelections)
func screenStatesExitIntoNearestDirectionalColumnAndKeepHeight(_ layouts: [LayoutPreset]) throws {
    let entryLayout: LayoutPreset = layouts.contains(.fourByTwo) ? .fourByTwo
        : layouts.contains(.twoByTwo) ? .twoByTwo : .threeByTwo
    let leftColumn = entryLayout == .fourByTwo ? 2 : 1
    let rightColumn = entryLayout == .twoByTwo ? 2 : 3
    for target in screenTargets {
        for (direction, column): (GridDirection, Int) in [(.left, leftColumn), (.right, rightColumn)] {
            var state = try screenState(layouts, target: target)
            let moved = state.move(direction)
            #expect(moved)
            let entryTarget: PlacementTarget = switch target {
            case .screenTop: .zone(column)
            case .screenBottom: .zone(entryLayout.columns + column)
            default: .column(column)
            }
            #expect(state.selectedPlacement == GridPlacement(layout: entryLayout, target: entryTarget))
            let firstEntry = state.selectedPlacement
            // Traversing a full candidate cycle returns to the grid entry,
            // without inserting a screen-width candidate into that cycle.
            for _ in 0..<layouts.map(\.columns).reduce(0, +) {
                state.move(direction)
                #expect(!screenTargets.contains(state.selectedTarget))
            }
            #expect(state.selectedPlacement == firstEntry)
        }
    }
}

@Test(arguments: screenPlacementSelections)
func screenVerticalNavigationClampsAndKeepsPreviewGrid(_ layouts: [LayoutPreset]) throws {
    var state = try screenState(layouts)
    let preview = state.layout
    #expect(state.highlightedZoneIDs == Array(1...(preview.columns * 2)))
    let movedUp = state.move(.up)
    #expect(movedUp)
    #expect(state.selectedTarget == .screenTop)
    #expect(state.highlightedZoneIDs == Array(1...preview.columns))
    let stoppedTop = state.move(.up)
    #expect(!stoppedTop)
    state.move(.down)
    #expect(state.selectedTarget == .maximized)
    state.move(.down)
    #expect(state.selectedTarget == .screenBottom)
    #expect(state.highlightedZoneIDs == Array((preview.columns + 1)...(preview.columns * 2)))
    let stoppedBottom = state.move(.down)
    #expect(!stoppedBottom)
    state.move(.up)
    #expect(state.selectedTarget == .maximized)
    #expect(state.layout == preview)
}

@Test(arguments: screenPlacementSelections)
func screenFramesAreRecognizedAcrossGridSelectionsGapAndScale(_ layouts: [LayoutPreset]) throws {
    let previewLayout: LayoutPreset = layouts.contains(.threeByTwo) ? .threeByTwo
        : layouts.contains(.fourByTwo) ? .fourByTwo : .twoByTwo
    let previewColumn = previewLayout == .twoByTwo ? 1 : 2
    for display in screenPlacementDisplays {
        for gap: CGFloat in [0, 4, 8, 12] {
            for scale: CGFloat in [1, 2] {
                for target in screenTargets {
                    let frame = try GridGeometry.frame(in: display, layout: .twoByTwo,
                        target: target, gap: gap, scale: scale)
                    let state = GridNavigation(layouts: layouts, windowFrame: frame,
                        visibleFrame: display, gap: gap, scale: scale)
                    #expect(state.selectedTarget == target)
                    #expect(state.layout == previewLayout)
                    #expect(state.column == previewColumn)
                    let reordered = GridNavigation(layouts: layouts.reversed() + layouts,
                        windowFrame: frame, visibleFrame: display, gap: gap, scale: scale)
                    #expect(state == reordered)
                }
            }
        }
    }
}

@Test(arguments: screenPlacementSelections)
func maximizingResetsHeightAndOriginalWindowCenterWithoutToggling(_ layouts: [LayoutPreset]) throws {
    let display = screenPlacementDisplays[0]
    var state = GridNavigation(layouts: layouts,
        windowFrame: CGRect(x: display.maxX - 80, y: 100, width: 60, height: 100), visibleFrame: display)
    state.move(.up)
    let changed = state.maximize()
    #expect(changed)
    let reference = try screenState(layouts)
    #expect(state == reference)
    let changedAgain = state.maximize()
    #expect(!changedAgain)
    #expect(state == reference)
    // Initial arbitrary-window horizontal targets must not survive maximize.
    state.move(.left)
    var centered = reference
    centered.move(.left)
    #expect(state == centered)
    state.maximize()
    state.move(.down)
    let resetHalf = state.maximize()
    #expect(resetHalf)
    #expect(state == reference)
}

@Test func manuallyChangedScreenFramesRestartFromWindowCenterAndFullGridHeight() throws {
    let display = screenPlacementDisplays[0]
    for target in screenTargets {
        let frame = try GridGeometry.frame(in: display, layout: .threeByTwo,
            target: target, gap: 8, scale: 2)
        let altered = frame.insetBy(dx: 0.01, dy: 0.01)
        var state = GridNavigation(layouts: [.twoByTwo, .threeByTwo],
            windowFrame: altered, visibleFrame: display, gap: 8, scale: 2)
        #expect(state.selectedPlacement == GridPlacement(layout: .threeByTwo, target: .column(2)))
        state.move(.left)
        #expect(state.selectedPlacement == GridPlacement(layout: .twoByTwo, target: .column(1)))
    }
}
