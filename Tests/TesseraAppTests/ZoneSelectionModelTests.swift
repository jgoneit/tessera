import CoreGraphics
import Testing
import TesseraCore
@testable import TesseraApp

@Suite("Zone selection keyboard input")
@MainActor
struct ZoneSelectionModelTests {
    @Test("Holding a vertical key advances from a half to full height only once",
          arguments: LayoutPreset.allCases)
    func verticalHoldStopsAtFullColumn(layout: LayoutPreset) {
        for direction in [GridDirection.up, .down] {
            let model = makeModel(layout: layout)
            _ = model.move(direction == .up ? .down : .up)

            let first = model.move(direction, isRepeat: false)
            #expect(first == GridPlacement(layout: layout, target: .column(2)))
            let statusAfterPress = model.status
            for _ in 0..<20 {
                let repeated = model.move(direction, isRepeat: true)
                #expect(repeated == nil)
            }

            #expect(model.navigation.selectedTarget == .column(2))
            #expect(model.navigation.highlightedZoneIDs == [2, layout.columns + 2])
            #expect(model.status == statusAfterPress)
        }
    }

    @Test("A repeat arriving immediately after opening does not move the window",
          arguments: LayoutPreset.allCases)
    func repeatOnlyAtOpenDoesNothing(layout: LayoutPreset) {
        for direction in [GridDirection.up, .down] {
            let model = makeModel(layout: layout)
            let original = model.navigation
            let originalStatus = model.status
            for _ in 0..<20 {
                let repeated = model.move(direction, isRepeat: true)
                #expect(repeated == nil)
            }
            #expect(model.navigation == original)
            #expect(model.status == originalStatus)
        }
    }

    @Test("Releasing and pressing a vertical key again reaches the opposite half",
          arguments: LayoutPreset.allCases)
    func secondFreshVerticalPressMovesAgain(layout: LayoutPreset) {
        for direction in [GridDirection.up, .down] {
            let model = makeModel(layout: layout)
            _ = model.move(direction == .up ? .down : .up)
            let first = model.move(direction, isRepeat: false)
            #expect(first == GridPlacement(layout: layout, target: .column(2)))
            let repeated = model.move(direction, isRepeat: true)
            #expect(repeated == nil)

            let second = model.move(direction, isRepeat: false)
            let expected: PlacementTarget = .zone(direction == .up ? 2 : layout.columns + 2)
            #expect(second == GridPlacement(layout: layout, target: expected))
            #expect(model.navigation.selectedTarget == expected)
        }
    }

    @Test("Horizontal auto-repeat continues wrapping columns at every height",
          arguments: LayoutPreset.allCases)
    func horizontalRepeatStillWraps(layout: LayoutPreset) {
        for heightDirection: GridDirection? in [nil, .up, .down] {
            for direction in [GridDirection.left, .right] {
                let model = makeModel(layout: layout)
                if let heightDirection { _ = model.move(heightDirection) }
                var expectedColumn = 2
                for press in 0..<(layout.columns * 2) {
                    if direction == .left {
                        expectedColumn = expectedColumn == 1 ? layout.columns : expectedColumn - 1
                    } else {
                        expectedColumn = expectedColumn == layout.columns ? 1 : expectedColumn + 1
                    }
                    let target = model.move(direction, isRepeat: press > 0)
                    let expected: PlacementTarget
                    switch heightDirection {
                    case .up: expected = .zone(expectedColumn)
                    case .down: expected = .zone(layout.columns + expectedColumn)
                    default: expected = .column(expectedColumn)
                    }
                    #expect(target == GridPlacement(layout: layout, target: expected))
                    #expect(model.navigation.selectedTarget == expected)
                }
            }
        }
    }

    @Test("The visible grid, number range, highlights and label change together")
    func numbersFollowSpatialGridChanges() throws {
        let display = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let frame = try GridGeometry.frame(in: display, layout: .fourByTwo,
            target: .column(1), gap: 8, scale: 1)
        let model = ZoneSelectionModel(navigation: GridNavigation(
            layouts: [.twoByTwo, .threeByTwo, .fourByTwo],
            windowFrame: frame, visibleFrame: display))
        #expect(model.layout == .fourByTwo)
        #expect(model.zoneCount == 8)
        let priorClick = try #require(model.placement(forZone: 8))
        #expect(priorClick == GridPlacement(layout: .fourByTwo, target: .zone(8)))

        #expect(model.move(.right) == GridPlacement(layout: .threeByTwo, target: .column(1)))
        #expect(model.layout == .threeByTwo)
        #expect(model.zoneCount == 6)
        #expect(model.navigation.highlightedZoneIDs == [1, 4])
        #expect(model.placement(forZone: 7) == nil)
        #expect(model.status.contains("3×2"))

        #expect(model.move(.right) == GridPlacement(layout: .twoByTwo, target: .column(1)))
        #expect(model.zoneCount == 4)
        #expect(model.navigation.highlightedZoneIDs == [1, 3])
        #expect(model.placement(forZone: 5) == nil)
        #expect(model.placement(forZone: 0) == nil)
        #expect(model.placement(forZone: 4) == GridPlacement(layout: .twoByTwo, target: .zone(4)))
        #expect(priorClick.layout == .fourByTwo) // queued clicks keep their displayed grid
        #expect(model.move(.down) == GridPlacement(layout: .twoByTwo, target: .zone(3)))
        #expect(model.move(.right) == GridPlacement(layout: .fourByTwo, target: .zone(6)))
        #expect(model.zoneCount == 8)
        #expect(model.navigation.highlightedZoneIDs == [6])
    }

    @Test("Opening only previews; the first horizontal input uses the original window center")
    func previewDoesNotCommitInitialCandidate() {
        let model = ZoneSelectionModel(navigation: GridNavigation(
            layouts: [.twoByTwo, .threeByTwo],
            windowFrame: CGRect(x: 510, y: 100, width: 180, height: 300),
            visibleFrame: CGRect(x: 0, y: 0, width: 1200, height: 800)))
        #expect(model.navigation.selectedPlacement == GridPlacement(layout: .threeByTwo, target: .column(2)))
        #expect(model.state.lastConfirmedFrame == nil)
        #expect(model.move(.right) == GridPlacement(layout: .twoByTwo, target: .column(2)))
        #expect(model.move(.right) == GridPlacement(layout: .threeByTwo, target: .column(3)))
        #expect(model.move(.up) == GridPlacement(layout: .threeByTwo, target: .zone(3)))
        #expect(model.move(.left) == GridPlacement(layout: .twoByTwo, target: .zone(2)))
        #expect(model.move(.down) == GridPlacement(layout: .twoByTwo, target: .column(2)))
        #expect(model.move(.down, isRepeat: true) == nil)
        #expect(model.move(.down) == GridPlacement(layout: .twoByTwo, target: .zone(4)))
    }

    private func makeModel(layout: LayoutPreset) -> ZoneSelectionModel {
        let display = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let center = display.width * 1.5 / CGFloat(layout.columns)
        return ZoneSelectionModel(navigation: GridNavigation(
            layout: layout,
            windowFrame: CGRect(x: center - 100, y: 100, width: 200, height: 300),
            visibleFrame: display
        ))
    }
}
