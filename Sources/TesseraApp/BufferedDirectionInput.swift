import TesseraCore

/// Keeps every logical input while target resolution is suspended. Window writes
/// have their own latest-pending queue; input ordering must not be coalesced here.
@MainActor
final class BufferedDirectionInput {
    typealias Apply = @MainActor (GridDirection) -> Void
    private let prepare: @MainActor () async -> Apply?
    private let onIdle: @MainActor () -> Void
    private var pending: [GridDirection] = []
    private var task: Task<Void, Never>?
    private var generation = 0
    var isPreparing: Bool { task != nil }

    init(prepare: @escaping @MainActor () async -> Apply?, onIdle: @escaping @MainActor () -> Void) {
        self.prepare = prepare
        self.onIdle = onIdle
    }

    func submit(_ direction: GridDirection) {
        pending.append(direction)
        guard task == nil else { return }
        let generation = generation
        task = Task {
            let apply = await prepare()
            guard self.generation == generation, !Task.isCancelled else { return }
            let inputs = pending
            pending.removeAll()
            if let apply { inputs.forEach(apply) }
            task = nil
            onIdle()
        }
    }

    func cancel() {
        generation &+= 1
        task?.cancel()
        task = nil
        pending.removeAll()
    }
}
