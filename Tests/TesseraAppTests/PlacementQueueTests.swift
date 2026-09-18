import CoreGraphics
import Testing
import TesseraCore
@testable import TesseraApp

@Suite("Serial placement queue", .timeLimit(.minutes(1)))
@MainActor
struct PlacementQueueTests {
    @Test("Only one operation runs and rapid requests retain the latest pending target")
    func serialAndLatestOnly() async {
        let executor = DelayedPlacementExecutor()
        let observer = QueueObserver()
        let queue = makeQueue(executor: executor, observer: observer)

        queue.submit(placement(.zone(1)))
        await executor.waitForStarts(1)
        queue.submit(placement(.zone(2)))
        queue.submit(placement(.zone(3)))
        queue.submit(placement(.column(2)))
        #expect(executor.started == [placement(.zone(1))])

        executor.completeNext(.applied)
        await executor.waitForStarts(2)
        #expect(executor.started == [placement(.zone(1)), placement(.column(2))])
        #expect(executor.maximumConcurrent == 1)
        queue.finish()
        executor.completeNext(.constrained)
        await observer.waitForFinish()

        #expect(executor.writes == [placement(.zone(1)), placement(.column(2))])
        #expect(observer.results.map { $0.1.outcome } == [.applied, .constrained])
        #expect(observer.finishCount == 1)
    }

    @Test("A delayed request retains its submitted grid even after the selection changes")
    func delayedRequestsKeepTheirOwnLayout() async throws {
        let executor = DelayedPlacementExecutor()
        let observer = QueueObserver()
        let queue = makeQueue(executor: executor, observer: observer)
        let first = placement(.column(2), layout: .threeByTwo)
        var currentSelection = first
        queue.submit(currentSelection)
        await executor.waitForStarts(1)

        currentSelection = placement(.column(2), layout: .fourByTwo)
        let submitted = currentSelection
        queue.submit(currentSelection)
        // Later UI state must not reinterpret the already queued column id.
        currentSelection = placement(.column(2), layout: .twoByTwo)
        queue.finish()
        executor.completeNext(.applied)
        await executor.waitForStarts(2)
        #expect(executor.started == [first, submitted])
        #expect(executor.started.last != currentSelection)

        let delivered = try #require(executor.started.last)
        let frame = try GridGeometry.frame(in: CGRect(x: 0, y: 0, width: 1200, height: 800),
            layout: delivered.layout, target: delivered.target, gap: 8, scale: 1)
        #expect(frame.width == 290)
        executor.completeNext(.constrained)
        await observer.waitForFinish()
        #expect(executor.writes == [first, submitted])
        #expect(observer.results.map { $0.0 } == [first, submitted])
        #expect(executor.maximumConcurrent == 1)
        #expect(observer.finishCount == 1)
    }

    @Test("A held vertical key keeps full height pending while another placement is suspended",
          arguments: [GridDirection.up, .down])
    func heldVerticalKeyDoesNotCoalesceAwayFullHeight(direction: GridDirection) async {
        let executor = DelayedPlacementExecutor()
        let observer = QueueObserver()
        let queue = makeQueue(executor: executor, observer: observer)
        let model = makeSelectionModel(startingFor: direction)
        let originalHalf = model.navigation.selectedPlacement
        queue.submit(originalHalf)
        await executor.waitForStarts(1)

        if let target = model.move(direction, isRepeat: false) { queue.submit(target) }
        for _ in 0..<20 {
            if let target = model.move(direction, isRepeat: true) { queue.submit(target) }
        }
        queue.finish()
        #expect(model.navigation.selectedTarget == .column(2))
        executor.completeNext(.applied)
        await executor.waitForStarts(2)
        #expect(executor.started == [originalHalf, placement(.column(2))])
        executor.completeNext(.applied)
        await observer.waitForFinish()

        #expect(executor.writes == [originalHalf, placement(.column(2))])
        #expect(executor.maximumConcurrent == 1)
        #expect(observer.finishCount == 1)
    }

    @Test("Two distinct vertical presses still replace pending work with the latest destination",
          arguments: [GridDirection.up, .down])
    func freshVerticalPressesPreserveLatestOnlyQueue(direction: GridDirection) async {
        let executor = DelayedPlacementExecutor()
        let observer = QueueObserver()
        let queue = makeQueue(executor: executor, observer: observer)
        let model = makeSelectionModel(startingFor: direction)
        let originalHalf = model.navigation.selectedPlacement
        queue.submit(originalHalf)
        await executor.waitForStarts(1)

        if let target = model.move(direction, isRepeat: false) { queue.submit(target) }
        #expect(model.navigation.selectedTarget == .column(2))
        if let target = model.move(direction, isRepeat: false) { queue.submit(target) }
        let oppositeHalf = placement(.zone(direction == .up ? 2 : 5))
        #expect(model.navigation.selectedPlacement == oppositeHalf)
        queue.finish()
        executor.completeNext(.applied)
        await executor.waitForStarts(2)
        #expect(executor.started == [originalHalf, oppositeHalf])
        executor.completeNext(.applied)
        await observer.waitForFinish()

        #expect(executor.writes == [originalHalf, oppositeHalf])
        #expect(executor.maximumConcurrent == 1)
        #expect(observer.finishCount == 1)
    }

    @Test("Graceful finish drains the latest pending request and rejects new submissions")
    func gracefulFinish() async {
        let executor = DelayedPlacementExecutor()
        let observer = QueueObserver()
        let queue = makeQueue(executor: executor, observer: observer)

        queue.submit(placement(.zone(1)))
        await executor.waitForStarts(1)
        queue.submit(placement(.column(1), layout: .fourByTwo))
        queue.finish()
        queue.submit(placement(.zone(6)))
        #expect(observer.finishCount == 0)

        executor.completeNext(.applied)
        await executor.waitForStarts(2)
        #expect(executor.started == [placement(.zone(1)), placement(.column(1), layout: .fourByTwo)])
        executor.completeNext(.applied)
        await observer.waitForFinish()
        queue.finish()
        queue.cancel()
        queue.submit(placement(.zone(4)))

        #expect(executor.started == [placement(.zone(1)), placement(.column(1), layout: .fourByTwo)])
        #expect(observer.finishCount == 1)
        #expect(!queue.isCancelled)
    }

    @Test("Hard cancellation stops the next write and drops pending requests")
    func hardCancellation() async {
        let executor = DelayedPlacementExecutor()
        let observer = QueueObserver()
        let queue = makeQueue(executor: executor, observer: observer)

        queue.submit(placement(.zone(1)))
        await executor.waitForStarts(1)
        queue.submit(placement(.zone(2), layout: .fourByTwo))
        queue.cancel()
        queue.submit(placement(.column(1), layout: .twoByTwo))
        #expect(queue.isCancelled)
        #expect(observer.finishCount == 0)

        executor.completeNext(.applied)
        await observer.waitForFinish()
        queue.cancel()
        queue.finish()

        #expect(executor.started == [placement(.zone(1))])
        #expect(executor.writes.isEmpty)
        #expect(executor.cancellationObserved)
        #expect(observer.results.count == 1)
        #expect(observer.results.first?.1.outcome == .unavailable)
        #expect(observer.finishCount == 1)
    }

    @Test("An outside cancellation during graceful drain drops the remaining placement")
    func cancellationDuringGracefulDrain() async {
        let executor = DelayedPlacementExecutor()
        let observer = QueueObserver()
        let queue = makeQueue(executor: executor, observer: observer)

        queue.submit(placement(.zone(1)))
        await executor.waitForStarts(1)
        queue.submit(placement(.zone(2)))
        queue.submit(placement(.column(3), layout: .fourByTwo))
        queue.finish()
        #expect(observer.finishCount == 0)
        #expect(!queue.isCancelled)

        // The user leaves the selector while its current operation is suspended.
        queue.cancel()
        queue.submit(placement(.zone(6)))
        #expect(queue.isCancelled)
        #expect(observer.finishCount == 0)
        executor.completeNext(.applied)
        await observer.waitForFinish()
        queue.submit(placement(.column(1)))
        queue.finish()
        queue.cancel()

        #expect(executor.started == [placement(.zone(1))])
        #expect(executor.writes.isEmpty)
        #expect(executor.cancellationObserved)
        #expect(observer.results.map { $0.0 } == [placement(.zone(1))])
        #expect(observer.results.map { $0.1.outcome } == [.unavailable])
        #expect(observer.finishCount == 1)
    }

    @Test("A partial failure remains delivered after cancellation")
    func cancelledPartialFailureIsReported() async {
        let executor = DelayedPlacementExecutor(checkCancellationBeforeWrite: false)
        let observer = QueueObserver()
        let queue = makeQueue(executor: executor, observer: observer)

        queue.submit(placement(.zone(1)))
        await executor.waitForStarts(1)
        queue.submit(placement(.zone(2), layout: .fourByTwo))
        queue.cancel()
        executor.completeNext(.failed)
        await observer.waitForFinish()

        #expect(observer.results.count == 1)
        #expect(observer.results.first?.1.outcome == .failed)
        #expect(executor.started == [placement(.zone(1))])
        #expect(observer.finishCount == 1)
    }

    @Test("Cancellation before the operation starts performs no work")
    func cancelBeforeStart() async {
        let executor = DelayedPlacementExecutor()
        let observer = QueueObserver()
        let queue = makeQueue(executor: executor, observer: observer)

        queue.submit(placement(.zone(1)))
        queue.submit(placement(.zone(2), layout: .fourByTwo))
        queue.cancel()
        await observer.waitForFinish()

        #expect(executor.started.isEmpty)
        #expect(executor.writes.isEmpty)
        #expect(observer.results.isEmpty)
        #expect(observer.finishCount == 1)
    }

    @Test("Cancellation completes cleanup even if the owner releases the scheduled queue")
    func releasedOwnerStillCompletesCancellation() async {
        let executor = DelayedPlacementExecutor()
        let observer = QueueObserver()
        var queue: PlacementQueue? = makeQueue(executor: executor, observer: observer)
        weak var releasedQueue = queue
        queue?.submit(placement(.zone(1)))
        queue?.cancel()
        queue = nil

        await observer.waitForFinish()
        #expect(executor.started.isEmpty)
        #expect(observer.finishCount == 1)
        #expect(releasedQueue == nil)
    }

    @Test("Failure and unavailability stop the queue without running pending work",
          arguments: [PlacementResult.Outcome.failed, .unavailable])
    func failureStopsQueue(outcome: PlacementResult.Outcome) async {
        let executor = DelayedPlacementExecutor()
        let observer = QueueObserver()
        let queue = makeQueue(executor: executor, observer: observer)

        queue.submit(placement(.zone(1)))
        await executor.waitForStarts(1)
        queue.submit(placement(.zone(2), layout: .fourByTwo))
        executor.completeNext(outcome)
        await observer.waitForFinish()
        queue.submit(placement(.column(1), layout: .twoByTwo))

        #expect(executor.started == [placement(.zone(1))])
        #expect(observer.results.map { $0.1.outcome } == [outcome])
        #expect(observer.finishCount == 1)
    }

    @Test("Finishing or cancelling an idle queue completes exactly once")
    func idleCompletion() {
        for shouldCancel in [false, true] {
            let executor = DelayedPlacementExecutor()
            let observer = QueueObserver()
            let queue = makeQueue(executor: executor, observer: observer)
            if shouldCancel { queue.cancel() } else { queue.finish() }
            queue.finish()
            queue.cancel()
            queue.submit(placement(.zone(1)))

            #expect(observer.finishCount == 1)
            #expect(executor.started.isEmpty)
            #expect(queue.isCancelled == shouldCancel)
        }
    }

    private func placement(_ target: PlacementTarget, layout: LayoutPreset = .threeByTwo) -> GridPlacement {
        GridPlacement(layout: layout, target: target)
    }

    private func makeQueue(executor: DelayedPlacementExecutor, observer: QueueObserver) -> PlacementQueue {
        PlacementQueue(
            operation: { await executor.perform($0) },
            onResult: { observer.results.append(($0, $1)) },
            onFinished: { observer.finished() }
        )
    }

    private func makeSelectionModel(startingFor direction: GridDirection) -> ZoneSelectionModel {
        let model = ZoneSelectionModel(navigation: GridNavigation(
            layout: .threeByTwo,
            windowFrame: CGRect(x: 500, y: 100, width: 100, height: 300),
            visibleFrame: CGRect(x: 0, y: 0, width: 1200, height: 800)
        ))
        _ = model.move(direction == .up ? .down : .up)
        return model
    }
}

/// A suspended operation makes overlap and cancellation observable without timers or AX calls.
@MainActor
private final class DelayedPlacementExecutor {
    private let checkCancellationBeforeWrite: Bool
    private var activeCount = 0
    private var continuations: [CheckedContinuation<PlacementResult, Never>] = []
    private var startWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var started: [GridPlacement] = []
    private(set) var writes: [GridPlacement] = []
    private(set) var maximumConcurrent = 0
    private(set) var cancellationObserved = false

    init(checkCancellationBeforeWrite: Bool = true) {
        self.checkCancellationBeforeWrite = checkCancellationBeforeWrite
    }

    func perform(_ target: GridPlacement) async -> PlacementResult {
        activeCount += 1
        maximumConcurrent = max(maximumConcurrent, activeCount)
        started.append(target)
        defer { activeCount -= 1 }
        let result = await withCheckedContinuation { continuation in
            continuations.append(continuation)
            let ready = startWaiters.filter { started.count >= $0.0 }
            startWaiters.removeAll { started.count >= $0.0 }
            ready.forEach { $0.1.resume() }
        }
        if checkCancellationBeforeWrite, Task.isCancelled {
            cancellationObserved = true
            return PlacementResult(outcome: .unavailable, message: "Cancelled before writing.", actualFrame: nil)
        }
        writes.append(target)
        return result
    }

    func waitForStarts(_ count: Int) async {
        guard started.count < count else { return }
        await withCheckedContinuation { startWaiters.append((count, $0)) }
    }

    func completeNext(_ outcome: PlacementResult.Outcome) {
        precondition(!continuations.isEmpty)
        continuations.removeFirst().resume(returning:
            PlacementResult(outcome: outcome, message: "Delayed test result.", actualFrame: nil))
    }
}

@MainActor
private final class QueueObserver {
    var results: [(GridPlacement, PlacementResult)] = []
    private var finishWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var finishCount = 0

    func finished() {
        finishCount += 1
        let waiters = finishWaiters
        finishWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func waitForFinish() async {
        guard finishCount == 0 else { return }
        await withCheckedContinuation { finishWaiters.append($0) }
    }
}
