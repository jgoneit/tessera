import CoreGraphics
import Testing
import TesseraCore
@testable import TesseraApp

@Suite("Direct arrangement navigation")
struct DirectNavigationStateTests {
    private let display = CGRect(x: -1512.5, y: 40.25, width: 1512, height: 944)
    private let primaryTop: CGFloat = 1080

    private func arbitraryWindow(inColumn column: Int, layout: LayoutPreset) -> CGRect {
        let center = display.minX + display.width * (CGFloat(column) - 0.5) / CGFloat(layout.columns)
        return CGRect(x: center - 120, y: display.minY + 130, width: 240, height: 350)
    }

    private func placement(_ target: PlacementTarget, layout: LayoutPreset = .threeByTwo) -> GridPlacement {
        GridPlacement(layout: layout, target: target)
    }

    private func state(_ layout: LayoutPreset, column: Int = 2) -> DirectNavigationState {
        DirectNavigationState(
            layout: layout, windowFrame: arbitraryWindow(inColumn: column, layout: layout),
            visibleFrame: display, gap: 8, scale: 2
        )
    }

    @Test("Initialization does not invent AX history", arguments: LayoutPreset.allCases)
    func initialCaptureIsExplicit(_ layout: LayoutPreset) {
        var state = state(layout)
        let capturedAX = CoordinateSpace.flip(arbitraryWindow(inColumn: 2, layout: layout), primaryTop: primaryTop)
        #expect(state.navigation.selectedTarget == .column(2))
        #expect(state.lastConfirmedFrame == nil)
        #expect(!state.matchesLastConfirmed(capturedAX))

        state.record(actualFrame: capturedAX)
        #expect(state.matchesLastConfirmed(capturedAX))
        #expect(state.navigation.selectedTarget == .column(2))
    }

    @Test("Existing selector navigation can be adopted without inventing readback history")
    func existingNavigationIsPreserved() {
        var navigation = GridNavigation(layout: .threeByTwo,
            windowFrame: arbitraryWindow(inColumn: 2, layout: .threeByTwo), visibleFrame: display)
        navigation.move(.down)
        var state = DirectNavigationState(navigation: navigation)
        #expect(state.navigation == navigation)
        #expect(state.lastConfirmedFrame == nil)
        #expect(state.move(.up) == placement(.column(2)))
    }

    @Test("Constrained AX readback preserves accepted top full bottom steps", arguments: LayoutPreset.allCases)
    func constrainedReadbackPreservesLogicalSteps(_ layout: LayoutPreset) {
        var state = state(layout)
        // An application can keep exactly the same actual frame for different
        // requests because of its minimum size or its own resize policy.
        let constrainedAX = CGRect(x: -990.5, y: 180.5, width: 650, height: 700)

        #expect(state.move(.up) == placement(.zone(2), layout: layout))
        state.record(actualFrame: constrainedAX)
        #expect(state.navigation.selectedTarget == .zone(2))
        #expect(state.matchesLastConfirmed(constrainedAX))

        #expect(state.move(.down) == placement(.column(2), layout: layout))
        state.record(actualFrame: constrainedAX)
        #expect(state.navigation.selectedTarget == .column(2))

        #expect(state.move(.down) == placement(.zone(layout.columns + 2), layout: layout))
        state.record(actualFrame: constrainedAX)
        #expect(state.move(.down) == nil)
        #expect(state.move(.up) == placement(.column(2), layout: layout))
        #expect(state.matchesLastConfirmed(constrainedAX))
    }

    @Test("Readback of an earlier request does not undo newer accepted navigation")
    func earlierCompletionDoesNotResetLatestStep() {
        var state = state(.threeByTwo)
        #expect(state.move(.up) == placement(.zone(2)))
        #expect(state.move(.down) == placement(.column(2)))
        #expect(state.move(.down) == placement(.zone(5)))

        let earlierAX = CGRect(x: -1000, y: 120, width: 600, height: 650)
        state.record(actualFrame: earlierAX)
        #expect(state.navigation.selectedTarget == .zone(5))
        #expect(state.move(.up) == placement(.column(2)))
        #expect(state.lastConfirmedFrame == earlierAX)
    }

    @Test("Manual moves and resizes are detected on all four AX edges")
    func manualGeometryChangeIsDetected() {
        var state = state(.fourByTwo)
        let confirmed = CGRect(x: -1511.5, y: 22.5, width: 377.5, height: 470.5)
        state.record(actualFrame: confirmed)
        let changes = [
            confirmed.offsetBy(dx: 0.25, dy: 0),
            confirmed.offsetBy(dx: 0, dy: -0.25),
            CGRect(origin: confirmed.origin, size: CGSize(width: confirmed.width + 0.25, height: confirmed.height)),
            CGRect(origin: confirmed.origin, size: CGSize(width: confirmed.width, height: confirmed.height - 0.25)),
            CGRect(x: confirmed.minX + 0.00075, y: confirmed.minY,
                width: confirmed.width + 0.00075, height: confirmed.height),
            CGRect(x: confirmed.minX, y: confirmed.minY + 0.00075,
                width: confirmed.width, height: confirmed.height + 0.00075),
        ]
        for changed in changes { #expect(!state.matchesLastConfirmed(changed)) }

        let noise = CGRect(x: confirmed.minX + 0.0002, y: confirmed.minY - 0.0002,
            width: confirmed.width + 0.0003, height: confirmed.height - 0.0003)
        #expect(state.matchesLastConfirmed(noise))
        #expect(state.lastConfirmedFrame == confirmed)
    }

    @Test("A manual resize resets from the new frame without old navigation history", arguments: LayoutPreset.allCases)
    func manualResizeStartsFreshNavigation(_ layout: LayoutPreset) {
        var previous = state(layout)
        #expect(previous.move(.up) == placement(.zone(2), layout: layout))
        let confirmedAX = CGRect(x: -1000, y: 100, width: 600, height: 650)
        previous.record(actualFrame: confirmedAX)

        let manualAppKit = arbitraryWindow(inColumn: layout.columns, layout: layout)
        let manualAX = CoordinateSpace.flip(manualAppKit, primaryTop: primaryTop)
        #expect(!previous.matchesLastConfirmed(manualAX))
        var reset = DirectNavigationState(layout: layout, windowFrame: manualAppKit,
            visibleFrame: display, gap: 8, scale: 2)
        #expect(reset.lastConfirmedFrame == nil)
        #expect(reset.navigation.selectedTarget == .column(layout.columns))
        reset.record(actualFrame: manualAX)
        #expect(reset.move(.down) == placement(.zone(layout.columns * 2), layout: layout))
        #expect(previous.navigation.selectedTarget == .zone(2))
        #expect(previous.lastConfirmedFrame == confirmedAX)
    }

    @Test("A different window gets independent history even with an identical frame")
    func newWindowDoesNotInheritHistory() {
        var previous = state(.threeByTwo)
        let sameAX = CoordinateSpace.flip(arbitraryWindow(inColumn: 2, layout: .threeByTwo), primaryTop: primaryTop)
        previous.record(actualFrame: sameAX)
        #expect(previous.move(.down) == placement(.zone(5)))

        var replacement = state(.threeByTwo)
        #expect(replacement.lastConfirmedFrame == nil)
        #expect(!replacement.matchesLastConfirmed(sameAX))
        #expect(replacement.navigation.selectedTarget == .column(2))
        replacement.record(actualFrame: sameAX)
        #expect(replacement.move(.up) == placement(.zone(2)))
        #expect(previous.navigation.selectedTarget == .zone(5))
    }

    @Test("Fresh direct state recognizes AppKit half geometry and records AX separately", arguments: LayoutPreset.allCases)
    func initialHalfAndReadbackUseSeparateCoordinateSpaces(_ layout: LayoutPreset) throws {
        for zone in [2, layout.columns + 2] {
            let appKitFrame = try GridGeometry.frame(in: display, layout: layout, zoneID: zone, gap: 12, scale: 2)
            let axFrame = CoordinateSpace.flip(appKitFrame, primaryTop: primaryTop)
            var state = DirectNavigationState(layout: layout, windowFrame: appKitFrame,
                visibleFrame: display, gap: 12, scale: 2)
            #expect(state.navigation.selectedTarget == .zone(zone))
            state.record(actualFrame: axFrame)
            #expect(state.matchesLastConfirmed(axFrame))
            #expect(!state.matchesLastConfirmed(appKitFrame))
            #expect(state.move(zone <= layout.columns ? .down : .up) == placement(.column(2), layout: layout))
        }
    }

    @Test("Constrained readback preserves navigation when neighboring candidates change width")
    func constrainedHistorySurvivesGridWidthChanges() throws {
        let initial = try GridGeometry.frame(in: display, layout: .threeByTwo,
            target: .column(2), gap: 8, scale: 2)
        var state = DirectNavigationState(layouts: [.threeByTwo, .fourByTwo],
            windowFrame: initial, visibleFrame: display, gap: 8, scale: 2)
        let constrainedAX = CGRect(x: -990.5, y: 180.5, width: 800, height: 700)
        #expect(state.move(.up) == placement(.zone(2)))
        state.record(actualFrame: constrainedAX)
        #expect(state.move(.right) == placement(.zone(3), layout: .fourByTwo))
        state.record(actualFrame: constrainedAX)
        #expect(state.navigation.layout == .fourByTwo)
        #expect(state.navigation.selectedPlacement == placement(.zone(3), layout: .fourByTwo))
        #expect(state.matchesLastConfirmed(constrainedAX))

        #expect(state.move(.down) == placement(.column(3), layout: .fourByTwo))
        state.record(actualFrame: constrainedAX)
        #expect(state.move(.right) == placement(.column(3)))
        #expect(state.navigation.layout == .threeByTwo)
        #expect(state.lastConfirmedFrame == constrainedAX)
    }

    @Test("A completion from the prior grid cannot replace the latest selected grid")
    func earlierGridCompletionPreservesLatestSelection() throws {
        let initial = try GridGeometry.frame(in: display, layout: .threeByTwo,
            target: .column(2), gap: 8, scale: 2)
        var state = DirectNavigationState(layouts: [.threeByTwo, .fourByTwo],
            windowFrame: initial, visibleFrame: display, gap: 8, scale: 2)
        #expect(state.move(.up) == placement(.zone(2)))
        #expect(state.move(.right) == placement(.zone(3), layout: .fourByTwo))
        let priorGridFrame = try GridGeometry.frame(in: display, layout: .threeByTwo,
            target: .zone(2), gap: 8, scale: 2)
        state.record(actualFrame: CoordinateSpace.flip(priorGridFrame, primaryTop: primaryTop))
        #expect(state.navigation.selectedPlacement == placement(.zone(3), layout: .fourByTwo))
        #expect(state.move(.down) == placement(.column(3), layout: .fourByTwo))
    }

    @Test("Resetting after a manual resize recognizes the new grid without carrying old history")
    func resizedWindowStartsFromItsNewGrid() throws {
        let initial = try GridGeometry.frame(in: display, layout: .threeByTwo,
            target: .column(2), gap: 12, scale: 2)
        var previous = DirectNavigationState(layouts: [.threeByTwo, .fourByTwo],
            windowFrame: initial, visibleFrame: display, gap: 12, scale: 2)
        #expect(previous.move(.up) == placement(.zone(2)))
        let confirmedAX = CGRect(x: -990.5, y: 180.5, width: 800, height: 700)
        previous.record(actualFrame: confirmedAX)

        let resizedAppKit = try GridGeometry.frame(in: display, layout: .fourByTwo,
            target: .column(1), gap: 12, scale: 2)
        let resizedAX = CoordinateSpace.flip(resizedAppKit, primaryTop: primaryTop)
        #expect(!previous.matchesLastConfirmed(resizedAX))
        var fresh = DirectNavigationState(layouts: [.threeByTwo, .fourByTwo],
            windowFrame: resizedAppKit, visibleFrame: display, gap: 12, scale: 2)
        #expect(fresh.navigation.selectedPlacement == placement(.column(1), layout: .fourByTwo))
        #expect(fresh.lastConfirmedFrame == nil)
        fresh.record(actualFrame: resizedAX)
        #expect(fresh.move(.down) == placement(.zone(5), layout: .fourByTwo))
        #expect(previous.navigation.selectedPlacement == placement(.zone(2)))
        #expect(previous.lastConfirmedFrame == confirmedAX)
    }
}
