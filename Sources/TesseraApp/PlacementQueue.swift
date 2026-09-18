import TesseraCore

/// Serializes window writes while retaining only the latest unstarted request.
/// Each request carries the layout selected when it was submitted.
@MainActor
final class PlacementQueue {
    typealias Operation = @MainActor (GridPlacement) async -> PlacementResult
    typealias ResultHandler = @MainActor (GridPlacement, PlacementResult) -> Void
    typealias FinishHandler = @MainActor () -> Void

    private let operation: Operation
    private let onResult: ResultHandler
    private let onFinished: FinishHandler
    private let onIdle: FinishHandler
    private var task: Task<Void, Never>?
    private var pending: GridPlacement?
    private var isAccepting = true
    private var hasFinished = false
    private(set) var isCancelled = false
    var isBusy: Bool { task != nil }

    init(operation: @escaping Operation,
         onResult: @escaping ResultHandler,
         onFinished: @escaping FinishHandler,
         onIdle: @escaping FinishHandler = {}) {
        self.operation = operation
        self.onResult = onResult
        self.onFinished = onFinished
        self.onIdle = onIdle
    }

    func submit(_ target: GridPlacement) {
        guard isAccepting, !hasFinished else { return }
        if task != nil {
            pending = target
            return
        }
        // Keep the queue alive until cleanup, even if its owner releases it
        // immediately after cancellation. drain clears this handle on every exit.
        task = Task {
            await self.drain(startingWith: target)
        }
    }

    /// Stops accepting requests, but lets the current and latest pending ones finish.
    func finish() {
        guard !hasFinished else { return }
        isAccepting = false
        if task == nil { finishOnce() }
    }

    /// Drops unstarted work and lets a cancellation-aware operation stop before its next write.
    func cancel() {
        guard !hasFinished else { return }
        isCancelled = true
        isAccepting = false
        pending = nil
        task?.cancel()
        if task == nil { finishOnce() }
    }

    private func drain(startingWith first: GridPlacement) async {
        var next: GridPlacement? = first
        while let target = next {
            guard !isCancelled, !Task.isCancelled else { break }
            let result = await operation(target)
            if result.outcome == .failed || result.outcome == .unavailable {
                isAccepting = false
                pending = nil
            }

            // A failed or partially applied write must remain visible even if
            // cancellation arrived while the operation was suspended.
            onResult(target, result)
            guard !isCancelled, !Task.isCancelled else {
                pending = nil
                break
            }
            next = pending
            pending = nil
        }
        task = nil
        if !isAccepting { finishOnce() }
        else { onIdle() }
    }

    private func finishOnce() {
        guard !hasFinished else { return }
        hasFinished = true
        onFinished()
    }
}
