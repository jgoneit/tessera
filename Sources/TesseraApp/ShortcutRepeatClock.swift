import AppKit
import Carbon

@MainActor
protocol ShortcutScheduledTask: AnyObject {
    func cancel()
}

@MainActor
protocol ShortcutRepeatClock: AnyObject {
    var now: TimeInterval { get }
    var repeatDelay: TimeInterval { get }
    var repeatInterval: TimeInterval { get }
    func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) -> any ShortcutScheduledTask
}

@MainActor
final class SystemShortcutRepeatClock: ShortcutRepeatClock {
    var now: TimeInterval { GetCurrentEventTime() }
    var repeatDelay: TimeInterval { NSEvent.keyRepeatDelay }
    var repeatInterval: TimeInterval { NSEvent.keyRepeatInterval }

    func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) -> any ShortcutScheduledTask {
        ScheduledTask(delay: delay, action: action)
    }

    private final class ScheduledTask: ShortcutScheduledTask {
        private var task: Task<Void, Never>?

        init(delay: TimeInterval, action: @escaping @MainActor () -> Void) {
            task = Task { @MainActor in
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard !Task.isCancelled else { return }
                action()
            }
        }

        func cancel() { task?.cancel(); task = nil }
    }
}
