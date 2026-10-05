import CoreGraphics
import Testing
import TesseraCore
@testable import TesseraApp

@Suite("Multi-display placement")
struct MultiDisplayPlacementTests {
    private let screens = [
        DisplayGeometry(id: 1, frame: CGRect(x: -1600, y: -200, width: 1600, height: 1000),
            visibleFrame: CGRect(x: -1600, y: -170, width: 1600, height: 940), scale: 1),
        DisplayGeometry(id: 2, frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 30, width: 1440, height: 840), scale: 2),
        DisplayGeometry(id: 3, frame: CGRect(x: 1440, y: -300, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 1440, y: -270, width: 1880, height: 1020), scale: 1),
    ]

    private func frame(_ placement: GridPlacement, on display: DisplayGeometry, gap: CGFloat = 8) throws -> CGRect {
        try GridGeometry.frame(in: display.visibleFrame, layout: placement.layout,
            target: placement.target, gap: gap, scale: display.scale)
    }

    @Test("Navigation through destination resolution reaches the bounded window writer",
          arguments: Array(1...7))
    func horizontalCrossingUsesDestinationGeometry(_ mask: Int) throws {
        let layouts = LayoutPreset.allCases.enumerated().compactMap { index, layout in
            mask & (1 << index) != 0 ? layout : nil
        }
        let edgeLayout = try #require(layouts.max { $0.columns < $1.columns })
        let snapshot = ScreenSnapshot(displays: screens, primaryTop: 900)
        // Both adjacent transitions and the two outer-boundary wraps must reach
        // the destination writer, with its own scale, work area and coordinates.
        for (source, direction, destinationID) in [
            (screens[1], GridDirection.left, UInt32(1)),
            (screens[1], .right, 3),
            (screens[0], .left, 3),
            (screens[2], .right, 1),
        ] {
            let originColumn = direction == .left ? 1 : edgeLayout.columns
            let destinationColumn = direction == .left ? edgeLayout.columns : 1
            for gap: CGFloat in [0, 8, 12] {
                for row in 0...2 {
                    func target(_ column: Int) -> PlacementTarget {
                        row == 0 ? .column(column) : .zone(column + (row == 2 ? edgeLayout.columns : 0))
                    }
                    let initial = try frame(GridPlacement(layout: edgeLayout, target: target(originColumn)), on: source, gap: gap)
                    var state = DirectNavigationState(layouts: layouts, windowFrame: initial,
                        display: source, displays: screens, gap: gap)
                    let step = state.move(direction)
                    let request = try #require(step)
                    let destination = try #require(snapshot.display(for: request, captured: snapshot))
                    #expect(destination.id == destinationID)
                    #expect(request.target == target(destinationColumn))
                    #expect(request.layout == edgeLayout)
                    let desired = CoordinateSpace.flip(try frame(request, on: destination, gap: gap), primaryTop: 900)
                    let visible = CoordinateSpace.flip(destination.visibleFrame, primaryTop: 900)
                    var actual = CoordinateSpace.flip(initial, primaryTop: 900)
                    var writes = 0
                    let result = WindowPlacement.perform(frame: desired, visibleFrame: visible,
                        readFrame: { actual }, validate: {},
                        setSize: { actual.size = $0; writes += 1 },
                        setPosition: { actual.origin = $0; writes += 1 })
                    #expect(result.outcome == .applied)
                    #expect(result.actualFrame == desired)
                    #expect(writes >= 2)
                    state.record(actualFrame: actual)
                    #expect(state.matchesLastConfirmed(actual))
                    #expect(state.selectedPlacement == request)
                    #expect(state.move(direction == .left ? .right : .left)?.displayID == source.id)
                }
            }
        }
    }

    @Test func crossesThreeDisplaysAndKeepsLatestLogicalDestination() throws {
        let initial = try frame(GridPlacement(layout: .twoByTwo, target: .column(2)), on: screens[0])
        var state = DirectNavigationState(layouts: [.twoByTwo], windowFrame: initial,
            display: screens[0], displays: screens)
        let secondStep = state.move(.right)
        let second = try #require(secondStep)
        #expect(second == GridPlacement(layout: .twoByTwo, target: .column(1), displayID: 2))
        #expect(state.move(.right)?.displayID == 2)
        let thirdStep = state.move(.right)
        let third = try #require(thirdStep)
        #expect(third == GridPlacement(layout: .twoByTwo, target: .column(1), displayID: 3))
        // A constrained or late readback on the previous screen cannot rewind input.
        state.record(actualFrame: CGRect(x: 0, y: 30, width: 1100, height: 900))
        #expect(state.selectedPlacement == third)
        #expect(state.move(.right) == GridPlacement(layout: .twoByTwo, target: .column(2), displayID: 3))
        #expect(state.move(.right) == GridPlacement(layout: .twoByTwo, target: .column(1), displayID: 1))
        #expect(state.move(.left) == GridPlacement(layout: .twoByTwo, target: .column(2), displayID: 3))
    }

    @Test("The outer edges loop across two or three displays", arguments: [2, 3])
    func completeHorizontalLoop(_ count: Int) throws {
        let displays = Array(screens.prefix(count))
        let orderedColumns: [(LayoutPreset, Int)] = [
            (.fourByTwo, 1), (.threeByTwo, 1), (.twoByTwo, 1), (.fourByTwo, 2),
            (.threeByTwo, 2), (.fourByTwo, 3), (.twoByTwo, 2), (.threeByTwo, 3), (.fourByTwo, 4),
        ]
        for direction in [GridDirection.left, .right] {
            for height in 0...2 {
                let cycle = displays.flatMap { display in
                    orderedColumns.map { layout, column in
                        GridPlacement(layout: layout, target: height == 0 ? .column(column)
                            : .zone(column + (height == 2 ? layout.columns : 0)), displayID: display.id)
                    }
                }
                let initial = cycle[0]
                var state = DirectNavigationState(layouts: LayoutPreset.allCases,
                    windowFrame: try frame(initial, on: displays[0]), display: displays[0],
                    displays: displays.reversed())
                for step in 1...cycle.count {
                    let index = direction == .right ? step % cycle.count : (cycle.count - step) % cycle.count
                    #expect(state.move(direction) == cycle[index])
                }
                #expect(state.selectedPlacement == initial)
            }
        }
    }

    @Test("Vertical crossing retains column and screen-wide state", arguments: [GridDirection.up, .down])
    func verticalTransitions(_ direction: GridDirection) throws {
        let source = screens[1]
        let y: CGFloat = direction == .up ? 900 : -1200
        let neighbor = DisplayGeometry(id: 4, frame: CGRect(x: -200, y: y, width: 1800, height: 1200),
            visibleFrame: CGRect(x: -200, y: y + 24, width: 1800, height: 1152), scale: 1)
        for layout in LayoutPreset.allCases {
            for screenWide in [false, true] {
                let initialTarget: PlacementTarget = screenWide ? .maximized : .column(2)
                let initial = try frame(GridPlacement(layout: layout, target: initialTarget), on: source)
                var state = DirectNavigationState(layouts: [layout], windowFrame: initial,
                    display: source, displays: [source, neighbor])
                #expect(state.move(direction)?.displayID == source.id)
                let step = state.move(direction)
                let moved = try #require(step)
                let expected: PlacementTarget = screenWide
                    ? (direction == .up ? .screenBottom : .screenTop)
                    : .zone(direction == .up ? layout.columns + 2 : 2)
                #expect(moved == GridPlacement(layout: layout, target: expected, displayID: neighbor.id))
                let opposite: GridDirection = direction == .up ? .down : .up
                #expect(state.move(opposite)?.displayID == source.id)
                #expect(state.move(direction)?.displayID == neighbor.id)
                #expect(state.move(direction)?.target == initialTarget)
                #expect(state.move(direction)?.displayID == neighbor.id)
                #expect(state.move(direction) == nil) // no further vertical neighbor
                #expect(state.maximize().displayID == neighbor.id)
            }
        }
    }

    @Test func arbitraryEdgeAndMaximizeDoNotSkipLocalCandidates() throws {
        let source = screens[1]
        var state = DirectNavigationState(layouts: LayoutPreset.allCases,
            windowFrame: CGRect(x: 1400, y: 200, width: 30, height: 100), display: source, displays: screens)
        #expect(state.move(.right)?.displayID == 3)
        #expect(state.maximize().displayID == 3)
        #expect(state.move(.left)?.displayID == 3) // maximum enters a local column first
        #expect(state.move(.right)?.displayID == 3)
        let initial = try frame(GridPlacement(layout: .threeByTwo, target: .column(1)), on: source)
        var single = DirectNavigationState(layouts: [.threeByTwo], windowFrame: initial,
            display: source, displays: [source])
        #expect(single.move(.left) == GridPlacement(layout: .threeByTwo, target: .column(3), displayID: source.id))
        #expect(single.move(.up)?.target == .zone(3))
        #expect(single.move(.up) == nil)
    }

    @Test @MainActor func selectorNumbersAndMaximizeKeepTheDestination() throws {
        let initial = try frame(GridPlacement(layout: .fourByTwo, target: .column(4)), on: screens[1])
        let model = ZoneSelectionModel(state: DirectNavigationState(layouts: LayoutPreset.allCases,
            windowFrame: initial, display: screens[1], displays: screens))
        let moved = try #require(model.move(.right, isRepeat: true))
        #expect(moved.displayID == 3)
        #expect(model.state.display == screens[2])
        let click = try #require(model.placement(forZone: 8))
        #expect(click == GridPlacement(layout: .fourByTwo, target: .zone(8), displayID: 3))
        #expect(model.move(.left)?.displayID == 2)
        #expect(click.displayID == 3) // already rendered requests retain their screen
        #expect(model.maximize().displayID == 2)
        #expect(model.move(.up, isRepeat: true) == nil)
    }

    @Test @MainActor func selectorWrapKeepsTheOppositeDisplayForNumbersAndMaximize() throws {
        let initial = try frame(GridPlacement(layout: .threeByTwo, target: .zone(1)), on: screens[0])
        let model = ZoneSelectionModel(state: DirectNavigationState(layouts: [.twoByTwo, .threeByTwo],
            windowFrame: initial, display: screens[0], displays: [screens[0], screens[1]]))
        #expect(model.move(.left) == GridPlacement(layout: .threeByTwo, target: .zone(3), displayID: 2))
        #expect(model.state.display == screens[1])
        #expect(model.placement(forZone: 6) == GridPlacement(layout: .threeByTwo, target: .zone(6), displayID: 2))
        #expect(model.maximize().displayID == 2)
    }

    @Test func topologyChangesRejectQueuedDestinations() {
        let captured = ScreenSnapshot(displays: screens, primaryTop: 900)
        let request = GridPlacement(layout: .threeByTwo, target: .column(1), displayID: 3)
        let reordered = ScreenSnapshot(displays: screens.reversed(), primaryTop: 900)
        #expect(reordered.display(for: request, captured: captured) == screens[2])
        #expect(captured.display(for: GridPlacement(layout: .threeByTwo, target: .column(1)), captured: captured) == nil)
        #expect(captured.display(for: GridPlacement(layout: .threeByTwo, target: .column(1), displayID: 99), captured: captured) == nil)
        let removed = ScreenSnapshot(displays: Array(screens.prefix(2)), primaryTop: 900)
        #expect(removed.display(for: request, captured: captured) == nil)
        let newPrimary = ScreenSnapshot(displays: screens, primaryTop: 1080)
        #expect(newPrimary.display(for: request, captured: captured) == nil)
        for kind in 0...2 {
            var changed = screens
            let old = screens[2]
            changed[2] = DisplayGeometry(id: old.id,
                frame: kind == 0 ? old.frame.offsetBy(dx: 20, dy: 0) : old.frame,
                visibleFrame: kind == 1 ? old.visibleFrame.insetBy(dx: 20, dy: 10) : old.visibleFrame,
                scale: kind == 2 ? 2 : old.scale)
            #expect(ScreenSnapshot(displays: changed, primaryTop: 900).display(for: request, captured: captured) == nil)
        }
    }

    @Test("A stale source-display limit is retried once after the destination move",
          arguments: [false, true])
    func sourceDisplayConstraintGetsOneRetry(_ permanentConstraint: Bool) {
        let desired = CGRect(x: -1706, y: 30, width: 1706, height: 2130)
        let visible = CGRect(x: -5120, y: 30, width: 5120, height: 2130)
        var actual = CGRect(x: 0, y: 33, width: 594, height: 949)
        var sizes = 0
        var positions = 0
        let result = WindowPlacement.perform(frame: desired, visibleFrame: visible, retrySizeAfterMove: true,
            readFrame: { actual }, validate: {},
            setSize: { size in
                sizes += 1
                actual.size = CGSize(width: size.width,
                    height: sizes == 1 || permanentConstraint ? min(size.height, 952) : size.height)
            }, setPosition: { actual.origin = $0; positions += 1 })
        #expect(sizes == 2)
        #expect(positions == 3)
        #expect(result.outcome == (permanentConstraint ? .constrained : .applied))
        #expect(result.actualFrame == (permanentConstraint
            ? CGRect(x: -1706, y: 30, width: 1706, height: 952) : desired))
    }

    @Test("Cancellation before the cross-display retry stops additional writes")
    func retryRevalidatesBeforeWriting() {
        let desired = CGRect(x: -1706, y: 30, width: 1706, height: 2130)
        let visible = CGRect(x: -5120, y: 30, width: 5120, height: 2130)
        var actual = CGRect(x: 0, y: 33, width: 594, height: 949)
        var sizes = 0
        var positions = 0
        let result = WindowPlacement.perform(frame: desired, visibleFrame: visible, retrySizeAfterMove: true,
            readFrame: { actual }, validate: { if positions == 2 { throw CancellationError() } },
            setSize: { actual.size = CGSize(width: $0.width, height: 952); sizes += 1 },
            setPosition: { actual.origin = $0; positions += 1 })
        #expect(sizes == 1)
        #expect(positions == 2)
        #expect(result.outcome == .failed)
        #expect(result.actualFrame == actual)
    }
}
