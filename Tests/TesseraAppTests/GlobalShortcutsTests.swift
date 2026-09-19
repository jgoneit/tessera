import Carbon
import Foundation
import Testing
import TesseraCore
@testable import TesseraApp

@Suite("Directional global shortcut registry and input")
@MainActor
struct GlobalShortcutsTests {
    @Test("Every configured physical chord maps to its placement action")
    func everyActionMapping() throws {
        let harness = try Harness.registered()
        #expect(harness.backend.bindings.count == 5)
        for action in PlacementAction.allCases {
            let shortcut = try #require(DirectionalShortcuts.default[action])
            harness.emit(shortcut, .pressed)
            harness.emit(shortcut, .released)
        }
        #expect(harness.observer.actions == PlacementAction.allCases)
    }

    @Test("Maximize requires release and interrupts an active horizontal repeat")
    func maximizeIsOneShot() throws {
        let harness = try Harness.registered()
        harness.emit(.defaultLeft, .pressed)
        harness.clock.advance(by: 0.51)
        harness.emit(.defaultMaximize, .pressed)
        for _ in 0..<20 { harness.emit(.defaultMaximize, .pressed) }
        harness.clock.advance(by: 2)
        #expect(harness.observer.actions == [.direction(.left), .direction(.left), .maximize])
        harness.emit(.defaultMaximize, .released)
        harness.emit(.defaultMaximize, .pressed)
        #expect(harness.observer.actions.last == .maximize)
        #expect(harness.observer.actions.count == 4)
    }

    @Test("An unassigned Maximize keeps four direction registrations")
    func optionalMaximize() throws {
        let harness = try Harness.registered()
        var bindings = DirectionalShortcuts.default
        bindings.maximize = nil
        try harness.registry.register(bindings)
        #expect(harness.backend.bindings.count == 4)
        #expect(!harness.registry.contains(.defaultMaximize))
        harness.emit(.defaultLeft, .pressed)
        #expect(harness.observer.actions == [.direction(.left)])
    }

    @Test("A new Maximize conflict migrates with every existing direction usable")
    func firstStartupMaximizeConflict() throws {
        let harness = Harness()
        harness.backend.rejected.insert(.defaultMaximize)
        let result = try harness.registry.registerAtStartup(.default, allowMaximizeFallback: true)
        #expect(result.bindings.maximize == nil)
        #expect(result.warning != nil)
        #expect(harness.backend.bindings.count == 4)
        for direction in GridDirection.allCases {
            let shortcut = result.bindings[direction]
            #expect(shortcut == DirectionalShortcuts.default[direction])
            harness.emit(shortcut, .pressed)
            harness.emit(shortcut, .released)
        }
        #expect(harness.observer.actions == GridDirection.allCases.map(PlacementAction.direction))
    }

    @Test("Later Maximize conflicts reject the whole edit and preserve the old set")
    func laterMaximizeConflictDoesNotFallback() throws {
        let harness = try Harness.registered()
        let original = harness.backend.bindings
        var replacement = DirectionalShortcuts.default
        replacement.left = Shortcut(keyCode: 0, modifiers: UInt32(controlKey))
        replacement.maximize = Shortcut(keyCode: 1, modifiers: UInt32(controlKey))
        harness.backend.rejected.insert(try #require(replacement.maximize))
        #expect(throws: (any Error).self) {
            try harness.registry.registerAtStartup(replacement, allowMaximizeFallback: false)
        }
        #expect(harness.backend.bindings == original)
        harness.emit(.defaultMaximize, .pressed)
        #expect(harness.observer.actions == [.maximize])
    }

    @Test("An existing direction conflict cannot be hidden by Maximize fallback")
    func directionConflictDoesNotFallback() {
        let harness = Harness()
        harness.backend.rejected.insert(.defaultLeft)
        #expect(throws: (any Error).self) {
            try harness.registry.registerAtStartup(.default, allowMaximizeFallback: true)
        }
        #expect(harness.backend.bindings.isEmpty)
    }

    @Test("A direction and Maximize can exchange physical keys atomically")
    func exchangeWithMaximize() throws {
        let harness = try Harness.registered()
        let original = harness.backend.bindings
        var replacement = DirectionalShortcuts.default
        replacement.left = .defaultMaximize
        replacement.maximize = .defaultLeft
        try harness.registry.register(replacement)
        #expect(harness.backend.bindings == original)
        #expect(harness.backend.attempts.count == 5)
        harness.emit(.defaultLeft, .pressed)
        harness.emit(.defaultMaximize, .pressed)
        #expect(harness.observer.actions == [.maximize, .direction(.left)])
    }

    @Test("Recording a registered Maximize chord forwards the key without placing")
    func recordingMaximizeKeepsPhysicalChord() throws {
        let harness = try Harness.registered()
        harness.registry.setRecording(true)
        harness.emit(.defaultMaximize, .pressed)
        harness.clock.advance(by: 2)
        #expect(harness.observer.recorded == [.defaultMaximize])
        #expect(harness.observer.actions.isEmpty)
        #expect(harness.backend.bindings.count == 5)
    }

    @Test("Invalid or duplicate bindings never reach the registration backend")
    func validatesBeforeRegistration() throws {
        let harness = Harness()
        var duplicate = DirectionalShortcuts.default
        duplicate.down = duplicate.up
        #expect(duplicate.validationMessage != nil)
        #expect(throws: (any Error).self) { try harness.registry.register(duplicate) }
        duplicate = .default
        duplicate.maximize = duplicate.left
        #expect(throws: (any Error).self) { try harness.registry.register(duplicate) }
        var invalid = DirectionalShortcuts.default
        invalid.left = Shortcut(keyCode: 123, modifiers: 0)
        #expect(throws: (any Error).self) { try harness.registry.register(invalid) }
        #expect(harness.backend.attempts.isEmpty)
    }

    @Test("Registration errors identify the failing direction")
    func conflictIdentifiesDirection() throws {
        let harness = try Harness.registered()
        var replacement = DirectionalShortcuts.default
        replacement.right = Shortcut(keyCode: 0, modifiers: UInt32(controlKey))
        harness.backend.rejected.insert(replacement.right)
        do {
            try harness.registry.register(replacement)
            Issue.record("Expected the conflicting shortcut to fail")
        } catch ShortcutRegistrationError.binding(let direction, let message) {
            #expect(direction == .direction(.right))
            #expect(message == L10n.text("Another app is using this shortcut. Choose another combination."))
            #expect(ShortcutRegistrationError.binding(direction, message).localizedDescription.hasPrefix(L10n.text("Right") + ":"))
        }
        var duplicate = DirectionalShortcuts.default
        duplicate.down = duplicate.up
        #expect(duplicate.validationMessage == L10n.format("%@: %@", L10n.text("Down"), L10n.format("This shortcut is already assigned to %@.", L10n.text("Up"))))
    }

    @Test("A failed batch leaves every previous registration and action intact")
    func batchFailurePreservesPreviousBindings() throws {
        let harness = try Harness.registered()
        let old = harness.backend.bindings
        var replacement = DirectionalShortcuts.default
        replacement.left = Shortcut(keyCode: 0, modifiers: UInt32(controlKey))
        replacement.right = Shortcut(keyCode: 1, modifiers: UInt32(controlKey))
        harness.backend.rejected.insert(replacement.right)
        #expect(throws: (any Error).self) { try harness.registry.register(replacement) }
        #expect(harness.backend.bindings == old)
        #expect(!harness.registry.contains(replacement.left))
        harness.emit(.defaultLeft, .pressed)
        #expect(harness.observer.actions == [.direction(.left)])
    }

    @Test("Exchanging directions reuses the physical registrations")
    func exchangingBindingsDoesNotReregister() throws {
        let harness = try Harness.registered()
        let original = harness.backend.bindings
        var replacement = DirectionalShortcuts.default
        replacement.left = .defaultRight
        replacement.right = .defaultLeft
        try harness.registry.register(replacement)
        #expect(harness.backend.bindings == original)
        #expect(harness.backend.attempts.count == 5)
        harness.emit(.defaultLeft, .pressed)
        #expect(harness.observer.actions == [.direction(.right)])
    }

    @Test("Stale events for removed registrations cannot invoke a new action")
    func removedIDIsIgnored() throws {
        let harness = try Harness.registered()
        let oldID = try #require(harness.backend.id(for: .defaultLeft))
        var replacement = DirectionalShortcuts.default
        replacement.left = Shortcut(keyCode: 0, modifiers: UInt32(controlKey))
        try harness.registry.register(replacement)
        harness.backend.onEvent?(RegisteredShortcutEvent(id: oldID, phase: .pressed, timestamp: harness.clock.now))
        #expect(harness.observer.actions.isEmpty)
        #expect(!harness.registry.contains(.defaultLeft))
        #expect(harness.registry.contains(replacement.left))
    }

    @Test("Repeated vertical pressed events execute only once until release", arguments: [GridDirection.up, .down])
    func verticalPressIsOneStep(direction: GridDirection) throws {
        let harness = try Harness.registered()
        let shortcut = DirectionalShortcuts.default[direction]
        for _ in 0..<20 { harness.emit(shortcut, .pressed) }
        harness.clock.advance(by: 10)
        #expect(harness.observer.actions == [.direction(direction)])
        harness.emit(shortcut, .released)
        harness.emit(shortcut, .pressed)
        #expect(harness.observer.actions == [.direction(direction), .direction(direction)])
    }

    @Test("Horizontal repeat uses the clock and ignores Carbon duplicate presses")
    func horizontalRepeatUsesSystemTiming() throws {
        let harness = try Harness.registered()
        harness.emit(.defaultLeft, .pressed)
        for _ in 0..<20 { harness.emit(.defaultLeft, .pressed) }
        harness.clock.advance(by: 0.49)
        #expect(harness.observer.actions == [.direction(.left)])
        harness.clock.advance(by: 0.02)
        #expect(harness.observer.actions == [.direction(.left), .direction(.left)])
        harness.clock.advance(by: 0.10)
        #expect(harness.observer.actions == [.direction(.left), .direction(.left), .direction(.left)])
        harness.emit(.defaultLeft, .released)
        harness.clock.advance(by: 2)
        #expect(harness.observer.actions.count == 3)
    }

    @Test("Releasing a modifier stops horizontal repetition without a Carbon release")
    func modifierReleaseStopsRepeat() throws {
        let harness = try Harness.registered()
        harness.emit(.defaultRight, .pressed)
        harness.modifiers.value = UInt32(controlKey)
        harness.clock.advance(by: 1)
        #expect(harness.observer.actions == [.direction(.right)])
        harness.modifiers.value = UInt32(controlKey | optionKey)
        harness.emit(.defaultRight, .pressed)
        harness.clock.advance(by: 1)
        #expect(harness.observer.actions == [.direction(.right)])
        harness.emit(.defaultRight, .released)
        harness.emit(.defaultRight, .pressed)
        #expect(harness.observer.actions == [.direction(.right), .direction(.right)])
    }

    @Test("Only the most recently pressed direction can repeat")
    func latestDirectionOwnsRepeat() throws {
        let harness = try Harness.registered()
        harness.emit(.defaultLeft, .pressed)
        harness.clock.advance(by: 0.2)
        harness.emit(.defaultRight, .pressed)
        harness.emit(.defaultLeft, .released)
        harness.clock.advance(by: 0.51)
        #expect(harness.observer.actions == [.direction(.left), .direction(.right), .direction(.right)])
        harness.emit(DirectionalShortcuts.default.up, .pressed)
        harness.clock.advance(by: 1)
        #expect(harness.observer.actions == [.direction(.left), .direction(.right), .direction(.right), .direction(.up)])
    }

    @Test("Cancellation suppresses a held key until release")
    func cancellationCannotRestartHeldInput() throws {
        let harness = try Harness.registered()
        harness.emit(.defaultLeft, .pressed)
        harness.registry.cancelInput()
        harness.clock.advance(by: 0.1)
        for _ in 0..<20 { harness.emit(.defaultLeft, .pressed) }
        harness.clock.advance(by: 2)
        #expect(harness.observer.actions == [.direction(.left)])
        harness.emit(.defaultLeft, .released)
        harness.emit(.defaultLeft, .pressed)
        #expect(harness.observer.actions == [.direction(.left), .direction(.left)])
    }

    @Test("A press queued before cancellation stays suppressed through later repeats")
    func queuedPressBeforeCancellationIsSuppressed() throws {
        let harness = try Harness.registered()
        let queuedTime = harness.clock.now
        harness.clock.advance(by: 0.1)
        harness.registry.cancelInput()
        harness.emit(.defaultLeft, .pressed, timestamp: queuedTime)
        harness.clock.advance(by: 0.1)
        harness.emit(.defaultLeft, .pressed)
        harness.clock.advance(by: 1)
        #expect(harness.observer.actions.isEmpty)
        harness.emit(.defaultLeft, .released)
        harness.emit(.defaultLeft, .pressed)
        #expect(harness.observer.actions == [.direction(.left)])
    }

    @Test("An event queued before reassignment cannot execute the new direction")
    func reassignmentRejectsQueuedOldMapping() throws {
        let harness = try Harness.registered()
        let queuedTime = harness.clock.now
        harness.clock.advance(by: 0.1)
        var replacement = DirectionalShortcuts.default
        replacement.left = .defaultRight
        replacement.right = .defaultLeft
        try harness.registry.register(replacement)
        harness.emit(.defaultLeft, .pressed, timestamp: queuedTime)
        harness.emit(.defaultLeft, .pressed)
        #expect(harness.observer.actions.isEmpty)
        harness.emit(.defaultLeft, .released)
        harness.emit(.defaultLeft, .pressed)
        #expect(harness.observer.actions == [.direction(.right)])
    }

    @Test("Recording keeps reservations and forwards one existing chord without moving")
    func recordingKeepsRegistrations() throws {
        let harness = try Harness.registered()
        let original = harness.backend.bindings
        harness.registry.setRecording(true)
        harness.emit(.defaultLeft, .pressed)
        harness.emit(.defaultLeft, .pressed)
        harness.emit(.defaultRight, .pressed)
        harness.clock.advance(by: 1)
        #expect(harness.backend.bindings == original)
        #expect(harness.backend.releases.isEmpty)
        #expect(harness.observer.recorded == [.defaultLeft])
        #expect(harness.observer.actions.isEmpty)
        harness.registry.setRecording(false)
        harness.emit(.defaultLeft, .pressed)
        #expect(harness.observer.actions.isEmpty)
        harness.emit(.defaultLeft, .released)
        harness.emit(.defaultLeft, .pressed)
        #expect(harness.observer.actions == [.direction(.left)])
    }

    @Test("Synchronous cancellation by the first action prevents scheduling a repeat")
    func cancellationInsideActionStopsRepeat() throws {
        let harness = try Harness.registered()
        harness.registry.onTrigger = { [weak registry = harness.registry, observer = harness.observer] direction in
            observer.actions.append(direction)
            registry?.cancelInput()
        }
        harness.emit(.defaultRight, .pressed)
        harness.clock.advance(by: 2)
        #expect(harness.observer.actions == [.direction(.right)])
    }

    @Test("Failed cleanup stays inert and is retried on the next registry operation")
    func failedCleanupIsTracked() throws {
        let harness = try Harness.registered()
        let oldID = try #require(harness.backend.id(for: .defaultLeft))
        harness.backend.failedReleases.insert(oldID)
        var replacement = DirectionalShortcuts.default
        replacement.left = Shortcut(keyCode: 0, modifiers: UInt32(controlKey))
        try harness.registry.register(replacement)
        #expect(!harness.observer.errors.isEmpty)
        #expect(harness.backend.bindings[oldID] != nil)
        harness.backend.onEvent?(RegisteredShortcutEvent(id: oldID, phase: .pressed, timestamp: harness.clock.now))
        #expect(harness.observer.actions.isEmpty)
        harness.backend.failedReleases.remove(oldID)
        try harness.registry.register(replacement)
        #expect(harness.backend.bindings[oldID] == nil)
    }

    @Test("Unregister ends repetition and makes queued callbacks inert")
    func unregisterStopsEverything() throws {
        let harness = try Harness.registered()
        let id = try #require(harness.backend.id(for: .defaultLeft))
        harness.emit(.defaultLeft, .pressed)
        harness.registry.unregister()
        harness.clock.advance(by: 2)
        harness.backend.onEvent?(RegisteredShortcutEvent(id: id, phase: .pressed, timestamp: harness.clock.now))
        #expect(harness.observer.actions == [.direction(.left)])
        #expect(harness.backend.bindings.isEmpty)
    }

    @Test("A stale release cannot stop a newer press")
    func staleReleaseDoesNotStopCurrentRepeat() throws {
        let harness = try Harness.registered()
        let previousTime = harness.clock.now
        harness.clock.advance(by: 0.1)
        harness.emit(.defaultLeft, .pressed)
        harness.emit(.defaultLeft, .released, timestamp: previousTime)
        harness.clock.advance(by: 0.51)
        #expect(harness.observer.actions == [.direction(.left), .direction(.left)])
    }

    @Test("Reapplying unchanged bindings does not interrupt a held key")
    func unchangedConfigurationIsNoOp() throws {
        let harness = try Harness.registered()
        harness.emit(.defaultLeft, .pressed)
        try harness.registry.register(.default)
        harness.clock.advance(by: 0.51)
        #expect(harness.observer.actions == [.direction(.left), .direction(.left)])
        #expect(harness.backend.attempts.count == 5)
    }
}

private extension Shortcut {
    static var defaultLeft: Shortcut { DirectionalShortcuts.default.left }
    static var defaultRight: Shortcut { DirectionalShortcuts.default.right }
}

@MainActor
private final class Harness {
    let backend = FakeShortcutBackend()
    let clock = FakeShortcutClock()
    let modifiers = ModifierState()
    let observer = InputObserver()
    let registry: GlobalShortcuts

    init() {
        registry = GlobalShortcuts(backend: backend, clock: clock, currentModifiers: { [modifiers] in modifiers.value })
        registry.onTrigger = { [observer] in observer.actions.append($0) }
        registry.onRecord = { [observer] in observer.recorded.append($0) }
        registry.onError = { [observer] in observer.errors.append($0) }
    }

    static func registered() throws -> Harness {
        let result = Harness()
        try result.registry.register(.default)
        result.clock.advance(by: 0.1)
        return result
    }

    func emit(_ shortcut: Shortcut, _ phase: ShortcutEventPhase, timestamp: TimeInterval? = nil) {
        guard let id = backend.id(for: shortcut) else {
            Issue.record("Expected the shortcut to be registered")
            return
        }
        backend.onEvent?(RegisteredShortcutEvent(id: id, phase: phase, timestamp: timestamp ?? clock.now))
    }
}

@MainActor
private final class ModifierState { var value = UInt32(controlKey | optionKey) }

@MainActor
private final class InputObserver {
    var actions: [PlacementAction] = []
    var recorded: [Shortcut] = []
    var errors: [String] = []
}

@MainActor
private final class FakeShortcutBackend: ShortcutRegistrationBackend {
    var onEvent: ((RegisteredShortcutEvent) -> Void)?
    var bindings: [UInt32: Shortcut] = [:]
    var attempts: [Shortcut] = []
    var releases: [UInt32] = []
    var rejected: Set<Shortcut> = []
    var failedReleases: Set<UInt32> = []

    func register(_ shortcut: Shortcut, id: UInt32) throws {
        attempts.append(shortcut)
        guard !rejected.contains(shortcut), !bindings.values.contains(shortcut) else {
            throw ShortcutRegistrationError.alreadyRegistered
        }
        bindings[id] = shortcut
    }

    func unregister(id: UInt32) throws {
        releases.append(id)
        if failedReleases.contains(id) { throw ShortcutRegistrationError.carbon(-1) }
        bindings.removeValue(forKey: id)
    }

    func id(for shortcut: Shortcut) -> UInt32? { bindings.first { $0.value == shortcut }?.key }
}

@MainActor
private final class FakeShortcutClock: ShortcutRepeatClock {
    var now: TimeInterval = 10
    var repeatDelay: TimeInterval = 0.5
    var repeatInterval: TimeInterval = 0.1
    private var entries: [Entry] = []

    private final class Token: ShortcutScheduledTask {
        var cancelled = false
        func cancel() { cancelled = true }
    }
    private struct Entry {
        let due: TimeInterval
        let token: Token
        let action: @MainActor () -> Void
    }

    func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) -> any ShortcutScheduledTask {
        let token = Token()
        entries.append(Entry(due: now + delay, token: token, action: action))
        return token
    }

    func advance(by interval: TimeInterval) {
        let end = now + interval
        while let index = entries.indices.filter({ !entries[$0].token.cancelled && entries[$0].due <= end })
            .min(by: { entries[$0].due < entries[$1].due }) {
            let entry = entries.remove(at: index)
            now = entry.due
            entry.action()
        }
        entries.removeAll { $0.token.cancelled }
        now = end
    }
}
