import CoreGraphics
import Testing
import TesseraCore
@testable import TesseraApp

@Suite("Buffered directional commands", .timeLimit(.minutes(1)))
@MainActor
struct BufferedPlacementInputTests {
    @Test("Every direction received during capture changes navigation in order")
    func retainsInitialDirections() async {
        let gate = DirectionPreparationGate()
        var destinations: [GridPlacement] = []
        var navigation = GridNavigation(layout: .threeByTwo,
            windowFrame: CGRect(x: 450, y: 200, width: 300, height: 200),
            visibleFrame: CGRect(x: 0, y: 0, width: 1200, height: 800))
        var idleCount = 0
        let input = BufferedPlacementInput(prepare: { await gate.prepare() }, onIdle: { idleCount += 1 })
        input.submit(.direction(.up))
        await gate.waitForCalls(1)
        input.submit(.direction(.right))
        input.submit(.direction(.right))
        input.submit(.direction(.down))
        #expect(destinations.isEmpty)
        gate.resolve { direction in
            if case .direction(let direction) = direction, navigation.move(direction) { destinations.append(navigation.selectedPlacement) }
        }
        await waitUntil { idleCount == 1 }
        #expect(destinations == [placement(.zone(2)), placement(.zone(3)), placement(.zone(1)), placement(.column(1))])
        #expect(!input.isPreparing)
    }

    @Test("Buffered directions preserve order while crossing grids during one capture")
    func retainedDirectionsCrossGridWidths() async throws {
        let gate = DirectionPreparationGate()
        let display = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let initialFrame = try GridGeometry.frame(in: display, layout: .threeByTwo,
            target: .column(2), gap: 8, scale: 1)
        var state = DirectNavigationState(layouts: [.threeByTwo, .fourByTwo],
            windowFrame: initialFrame, visibleFrame: display)
        var destinations: [GridPlacement] = []
        var idleCount = 0
        let input = BufferedPlacementInput(prepare: { await gate.prepare() }, onIdle: { idleCount += 1 })
        input.submit(.direction(.up))
        await gate.waitForCalls(1)
        input.submit(.direction(.right))
        input.submit(.direction(.right))
        input.submit(.direction(.down))
        gate.resolve { direction in
            if let target = state.apply(direction) { destinations.append(target) }
        }
        await waitUntil { idleCount == 1 }
        #expect(destinations == [
            placement(.zone(2), layout: .threeByTwo),
            placement(.zone(3), layout: .fourByTwo),
            placement(.zone(3), layout: .threeByTwo),
            placement(.column(3), layout: .threeByTwo),
        ])
        #expect(!input.isPreparing)
    }

    @Test("Late capture completion after cancellation cannot apply or replace a newer capture")
    func cancellationSeparatesGenerations() async {
        let gate = DirectionPreparationGate()
        var directions: [PlacementAction] = []
        var idleCount = 0
        let input = BufferedPlacementInput(prepare: { await gate.prepare() }, onIdle: { idleCount += 1 })
        input.submit(.direction(.left))
        await gate.waitForCalls(1)
        input.submit(.direction(.up))
        input.cancel()
        input.submit(.direction(.down))
        await gate.waitForCalls(2)
        gate.resolve { directions.append($0) }
        for _ in 0..<10 { await Task.yield() }
        #expect(directions.isEmpty)
        #expect(input.isPreparing)
        #expect(idleCount == 0)
        gate.resolve { directions.append($0) }
        await waitUntil { idleCount == 1 }
        #expect(directions == [.direction(.down)])
    }

    @Test("A failed capture discards its inputs and the next press can start fresh")
    func failedPreparation() async {
        let gate = DirectionPreparationGate()
        var directions: [PlacementAction] = []
        var idleCount = 0
        let input = BufferedPlacementInput(prepare: { await gate.prepare() }, onIdle: { idleCount += 1 })
        input.submit(.direction(.up))
        input.submit(.direction(.left))
        await gate.waitForCalls(1)
        gate.resolve(nil)
        await waitUntil { idleCount == 1 }
        input.submit(.direction(.right))
        await gate.waitForCalls(2)
        gate.resolve { directions.append($0) }
        await waitUntil { idleCount == 2 }
        #expect(directions == [.direction(.right)])
    }

    @Test("Maximize and subsequent directions retain their capture order")
    func maximizeBeforeInitialDirections() async {
        let gate = DirectionPreparationGate()
        let display = CGRect(x: -1200, y: 25, width: 1200, height: 800)
        var state = DirectNavigationState(layouts: [.twoByTwo, .threeByTwo],
            windowFrame: CGRect(x: -1000, y: 200, width: 200, height: 200), visibleFrame: display)
        var destinations: [GridPlacement] = []
        var idleCount = 0
        let input = BufferedPlacementInput(prepare: { await gate.prepare() }, onIdle: { idleCount += 1 })
        input.submit(.maximize)
        await gate.waitForCalls(1)
        input.submit(.direction(.up))
        input.submit(.direction(.left))
        input.submit(.direction(.down))
        #expect(destinations.isEmpty)
        gate.resolve { action in
            if let target = state.apply(action) { destinations.append(target) }
        }
        await waitUntil { idleCount == 1 }
        #expect(destinations.map(\.target) == [.maximized, .screenTop, .zone(1), .column(1)])
        #expect(destinations[2].layout == .twoByTwo)
        #expect(destinations[3].layout == .twoByTwo)
    }

    @Test("Cancelling capture drops maximize together with directions")
    func cancelledMaximizeNeverApplies() async {
        let gate = DirectionPreparationGate()
        var applied: [PlacementAction] = []
        let input = BufferedPlacementInput(prepare: { await gate.prepare() }, onIdle: {})
        input.submit(.maximize)
        await gate.waitForCalls(1)
        input.submit(.direction(.left))
        input.cancel()
        gate.resolve { applied.append($0) }
        for _ in 0..<20 { await Task.yield() }
        #expect(applied.isEmpty)
        #expect(!input.isPreparing)
    }

    @Test("A direct placement queue remains usable between separate input bursts")
    func directQueueIdleLifetime() async {
        var writes: [GridPlacement] = []
        var idleCount = 0
        var finished = 0
        let queue = PlacementQueue(operation: { target in
            writes.append(target)
            return PlacementResult(outcome: .constrained, message: "App minimum", actualFrame: .zero)
        }, onResult: { _, _ in }, onFinished: { finished += 1 }, onIdle: { idleCount += 1 })
        queue.submit(placement(.zone(2)))
        await waitUntil { idleCount == 1 }
        #expect(!queue.isBusy)
        #expect(finished == 0)
        queue.submit(placement(.column(2), layout: .fourByTwo))
        await waitUntil { idleCount == 2 }
        #expect(writes == [placement(.zone(2)), placement(.column(2), layout: .fourByTwo)])
        queue.cancel()
        queue.submit(placement(.zone(3), layout: .twoByTwo))
        #expect(finished == 1)
        #expect(writes == [placement(.zone(2)), placement(.column(2), layout: .fourByTwo)])
    }

    private func placement(_ target: PlacementTarget, layout: LayoutPreset = .threeByTwo) -> GridPlacement {
        GridPlacement(layout: layout, target: target)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1000 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("Async state did not settle")
    }
}

@MainActor
private final class DirectionPreparationGate {
    private var continuations: [CheckedContinuation<BufferedPlacementInput.Apply?, Never>] = []
    private(set) var calls = 0
    func prepare() async -> BufferedPlacementInput.Apply? {
        calls += 1
        return await withCheckedContinuation { continuations.append($0) }
    }
    func resolve(_ apply: BufferedPlacementInput.Apply?) { continuations.removeFirst().resume(returning: apply) }
    func waitForCalls(_ count: Int) async {
        while calls < count { await Task.yield() }
    }
}
