import CoreGraphics
import AppKit
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

    @Test("Maximize keeps the selector active and arrows traverse screen height before returning to the grid")
    func maximizeThenNavigate() {
        let model = ZoneSelectionModel(navigation: GridNavigation(
            layouts: [.twoByTwo, .threeByTwo],
            windowFrame: CGRect(x: 510, y: 100, width: 180, height: 300),
            visibleFrame: CGRect(x: 0, y: 0, width: 1200, height: 800)))
        let displayedLayout = model.layout
        let first = model.maximize()
        #expect(first.target == .maximized)
        #expect(model.navigation.selectedTarget == .maximized)
        #expect(model.navigation.highlightedZoneIDs == Array(1...displayedLayout.zones.count))
        #expect(model.state.lastConfirmedFrame == nil)
        #expect(model.maximize() == first) // The request remains available for another one-shot press.
        #expect(model.move(.up)?.target == .screenTop)
        #expect(model.navigation.highlightedZoneIDs == Array(1...displayedLayout.columns))
        #expect(model.move(.down, isRepeat: true) == nil)
        #expect(model.navigation.selectedTarget == .screenTop)
        #expect(model.move(.down)?.target == .maximized)
        #expect(model.move(.down)?.target == .screenBottom)
        #expect(model.navigation.highlightedZoneIDs == Array((displayedLayout.columns + 1)...displayedLayout.zones.count))
        #expect(model.move(.down) == nil)
        #expect(model.move(.left) == GridPlacement(layout: .twoByTwo, target: .zone(3)))
        #expect(model.layout == .twoByTwo)
        #expect(model.zoneCount == 4)
    }

    @Test("Screen-wide states leave numbers and clicks bound to the displayed layout", arguments: LayoutPreset.allCases)
    func screenWideSelectionRetainsZoneTargets(layout: LayoutPreset) {
        let model = makeModel(layout: layout)
        _ = model.maximize()
        for direction: GridDirection? in [nil, .up, .down, .down] {
            if let direction { _ = model.move(direction) }
            #expect(model.zoneCount == layout.zones.count)
            #expect(model.placement(forZone: layout.zones.count)
                == GridPlacement(layout: layout, target: .zone(layout.zones.count)))
            #expect(model.placement(forZone: layout.zones.count + 1) == nil)
        }
    }

    @Test("Maximize suppresses held plain horizontal repeats until release or a fresh press")
    func maximizeStopsPlainHorizontalRepeat() {
        var input = SelectorHorizontalRepeat()
        func check(_ key: UInt16, repeat isRepeat: Bool, allowed: Bool) {
            let actual = input.permitsKeyDown(key, isRepeat: isRepeat)
            #expect(actual == allowed)
        }
        check(123, repeat: false, allowed: true)
        check(123, repeat: true, allowed: true)
        input.stop()
        check(123, repeat: true, allowed: false)
        check(124, repeat: true, allowed: false)
        check(125, repeat: true, allowed: true)
        check(36, repeat: false, allowed: true)
        check(123, repeat: true, allowed: false)
        input.keyUp(123)
        check(123, repeat: true, allowed: true)
        check(124, repeat: true, allowed: false)
        check(124, repeat: false, allowed: true)
        check(124, repeat: true, allowed: true)
    }

    @Test("The panel consumes registered maximize without closing and still closes for ordinary Enter or Esc")
    func registeredMaximizeDoesNotCloseSelector() throws {
        _ = NSApplication.shared
        let panel = ZonePanel(contentRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        var finishes = 0
        var moves: [GridDirection] = []
        panel.onFinish = { finishes += 1 }
        panel.onMove = { direction, _ in moves.append(direction) }
        panel.isRegisteredShortcut = { $0 == .defaultMaximize }
        func press(_ key: UInt16, modifiers: NSEvent.ModifierFlags = [], repeating: Bool = false) throws {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: modifiers, timestamp: 0, windowNumber: panel.windowNumber,
                context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: repeating, keyCode: key))
            panel.sendEvent(event)
        }
        try press(36, modifiers: [.control, .option])
        #expect(finishes == 0)
        #expect(moves.isEmpty)
        try press(36)
        #expect(finishes == 1)
        try press(36, repeating: true)
        #expect(finishes == 1)
        try press(76)
        try press(53)
        #expect(finishes == 3)

        try press(123)
        panel.cancelDirectionalRepeat()
        try press(123, repeating: true)
        #expect(moves == [.left])
        try press(123)
        #expect(moves == [.left, .left])
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
