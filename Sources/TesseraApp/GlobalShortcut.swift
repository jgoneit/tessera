import AppKit
import Carbon
import OSLog
import TesseraCore

struct Shortcut: Codable, Hashable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32

    static let `default` = Shortcut(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(controlKey | optionKey)
    )

    static let defaultMaximize = Shortcut(
        keyCode: UInt32(kVK_Return),
        modifiers: UInt32(controlKey | optionKey)
    )

    static let allowedModifiers = UInt32(cmdKey | controlKey | optionKey | shiftKey)

    var displayString: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + (Self.keyNames[keyCode].map { L10n.text($0) } ?? L10n.format("Key %ld", Int(keyCode)))
    }

    var validationMessage: String? {
        guard Self.keyNames[keyCode] != nil else {
            return L10n.text("Choose a letter, number, punctuation, navigation, or function key.")
        }
        guard modifiers & ~Self.allowedModifiers == 0 else {
            return L10n.text("Use only Command, Control, Option, and Shift modifiers.")
        }
        guard modifiers & UInt32(cmdKey | controlKey | optionKey) != 0 else {
            return L10n.text("Include Command, Control, or Option in the shortcut.")
        }
        return nil
    }

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(event: NSEvent) {
        keyCode = UInt32(event.keyCode)
        let flags = event.modifierFlags
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        modifiers = result
    }

    // Virtual key codes keep the binding stable when the input source changes.
    // Labels describe the corresponding key on a standard ANSI keyboard.
    private static let keyNames: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "−", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space",
        50: "`", 51: "Delete", 64: "F17", 65: "Keypad .", 67: "Keypad ×",
        69: "Keypad +", 71: "Clear", 75: "Keypad /", 76: "Keypad Enter",
        78: "Keypad −", 79: "F18", 80: "F19", 81: "Keypad =", 82: "Keypad 0",
        83: "Keypad 1", 84: "Keypad 2", 85: "Keypad 3", 86: "Keypad 4",
        87: "Keypad 5", 88: "Keypad 6", 89: "Keypad 7", 90: "F20",
        91: "Keypad 8", 92: "Keypad 9", 96: "F5", 97: "F6", 98: "F7",
        99: "F3", 100: "F8", 101: "F9", 103: "F11", 105: "F13",
        106: "F16", 107: "F14", 109: "F10", 111: "F12", 113: "F15",
        115: "Home", 116: "Page Up", 117: "Forward Delete", 118: "F4",
        119: "End", 120: "F2", 121: "Page Down", 122: "F1",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
}

enum PlacementAction: CaseIterable, Equatable, Sendable {
    case direction(GridDirection)
    case maximize

    static let allCases: [PlacementAction] = GridDirection.allCases.map(PlacementAction.direction) + [.maximize]

    var displayName: String {
        switch self {
        case .direction(.left): L10n.text("Left")
        case .direction(.right): L10n.text("Right")
        case .direction(.up): L10n.text("Up")
        case .direction(.down): L10n.text("Down")
        case .maximize: L10n.text("Maximize")
        }
    }

    var repeatsHorizontally: Bool {
        self == .direction(.left) || self == .direction(.right)
    }
}

enum ShortcutRegistrationError: LocalizedError {
    case invalid(String)
    case systemConflict
    case alreadyRegistered
    case carbon(OSStatus)
    case binding(PlacementAction, String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        case .systemConflict: return L10n.text("This shortcut is already used by macOS. Choose another combination.")
        case .alreadyRegistered: return L10n.text("Another app is using this shortcut. Choose another combination.")
        case .carbon(let status): return L10n.format("The shortcut could not be registered (error %ld).", Int(status))
        case .binding(let action, let message):
            return L10n.format("%@: %@", action.displayName, message)
        }
    }
}

struct DirectionalShortcuts: Codable, Equatable, Sendable {
    var left: Shortcut
    var right: Shortcut
    var up: Shortcut
    var down: Shortcut
    var maximize: Shortcut?

    init(left: Shortcut, right: Shortcut, up: Shortcut, down: Shortcut,
         maximize: Shortcut? = .defaultMaximize) {
        self.left = left
        self.right = right
        self.up = up
        self.down = down
        self.maximize = maximize
    }

    static let `default` = DirectionalShortcuts(
        left: Shortcut(keyCode: 123, modifiers: UInt32(controlKey | optionKey)),
        right: Shortcut(keyCode: 124, modifiers: UInt32(controlKey | optionKey)),
        up: Shortcut(keyCode: 126, modifiers: UInt32(controlKey | optionKey)),
        down: Shortcut(keyCode: 125, modifiers: UInt32(controlKey | optionKey))
    )

    subscript(_ direction: GridDirection) -> Shortcut {
        get {
            switch direction {
            case .left: left
            case .right: right
            case .up: up
            case .down: down
            }
        }
        set {
            switch direction {
            case .left: left = newValue
            case .right: right = newValue
            case .up: up = newValue
            case .down: down = newValue
            }
        }
    }

    subscript(_ action: PlacementAction) -> Shortcut? {
        get {
            switch action {
            case .direction(let direction): self[direction]
            case .maximize: maximize
            }
        }
        set {
            switch action {
            case .direction(let direction):
                if let newValue { self[direction] = newValue }
            case .maximize: maximize = newValue
            }
        }
    }

    var validationMessage: String? { validationError?.errorDescription }

    var validationError: ShortcutRegistrationError? {
        var seen: [Shortcut: PlacementAction] = [:]
        for action in PlacementAction.allCases {
            guard let shortcut = self[action] else { continue }
            if let message = shortcut.validationMessage { return .binding(action, message) }
            if let previous = seen[shortcut] {
                return .binding(action, L10n.format("This shortcut is already assigned to %@.", previous.displayName))
            }
            seen[shortcut] = action
        }
        return nil
    }
}

enum ShortcutEventPhase: Equatable, Sendable { case pressed, released }

struct RegisteredShortcutEvent: Sendable {
    let id: UInt32
    let phase: ShortcutEventPhase
    let timestamp: TimeInterval
}

@MainActor
protocol ShortcutRegistrationBackend: AnyObject {
    var onEvent: ((RegisteredShortcutEvent) -> Void)? { get set }
    func register(_ shortcut: Shortcut, id: UInt32) throws
    func unregister(id: UInt32) throws
}

private let tesseraHotKeySignature: OSType = 0x54535352
private let shortcutLogger = Logger(subsystem: "io.github.jgoneit.tessera", category: "shortcut")

// Copy the Carbon payload before returning, then use a single FIFO dispatch
// queue for both phases. Independent unstructured Tasks could reorder them.
private func tesseraHotKeyHandler(
    _ next: EventHandlerCallRef?, _ event: EventRef?, _ context: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    let phase: ShortcutEventPhase
    switch GetEventKind(event) {
    case UInt32(kEventHotKeyPressed): phase = .pressed
    case UInt32(kEventHotKeyReleased): phase = .released
    default: return OSStatus(eventNotHandledErr)
    }
    var identifier = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
    guard status == noErr, identifier.signature == tesseraHotKeySignature else {
        shortcutLogger.error("Carbon hotkey payload rejected: status=\(status, privacy: .public)")
        return OSStatus(eventNotHandledErr)
    }
    let payload = RegisteredShortcutEvent(id: identifier.id, phase: phase, timestamp: GetEventTime(event))
    DispatchQueue.main.async { CarbonShortcutBackend.deliver(payload) }
    return noErr
}

@MainActor
final class CarbonShortcutBackend: ShortcutRegistrationBackend {
    var onEvent: ((RegisteredShortcutEvent) -> Void)?
    private var references: [UInt32: EventHotKeyRef] = [:]
    private static var eventHandler: EventHandlerRef?
    private static var owners: [UInt32: WeakOwner] = [:]

    private final class WeakOwner {
        weak var owner: CarbonShortcutBackend?
        init(_ owner: CarbonShortcutBackend) { self.owner = owner }
    }

    func register(_ shortcut: Shortcut, id: UInt32) throws {
        try Self.checkSystemConflict(shortcut)
        try Self.installEventHandlerIfNeeded()
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
            EventHotKeyID(signature: tesseraHotKeySignature, id: id),
            GetEventDispatcherTarget(), OptionBits(kEventHotKeyExclusive), &reference)
        guard status == noErr, let reference else {
            if status == eventHotKeyExistsErr { throw ShortcutRegistrationError.alreadyRegistered }
            throw ShortcutRegistrationError.carbon(status)
        }
        references[id] = reference
        Self.owners[id] = WeakOwner(self)
        shortcutLogger.notice("Hotkey registered: id=\(id, privacy: .public) keyCode=\(shortcut.keyCode, privacy: .public) modifiers=\(shortcut.modifiers, privacy: .public)")
    }

    func unregister(id: UInt32) throws {
        guard let reference = references[id] else { return }
        let status = UnregisterEventHotKey(reference)
        guard status == noErr else { throw ShortcutRegistrationError.carbon(status) }
        references.removeValue(forKey: id)
        Self.owners.removeValue(forKey: id)
    }

    fileprivate static func deliver(_ event: RegisteredShortcutEvent) {
        guard let owner = owners[event.id]?.owner else { return }
        owner.onEvent?(event)
    }

    private static func installEventHandlerIfNeeded() throws {
        guard eventHandler == nil else { return }
        let types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let status = types.withUnsafeBufferPointer {
            InstallEventHandler(GetEventDispatcherTarget(), tesseraHotKeyHandler,
                $0.count, $0.baseAddress, nil, &eventHandler)
        }
        guard status == noErr else { throw ShortcutRegistrationError.carbon(status) }
    }

    private static func checkSystemConflict(_ shortcut: Shortcut) throws {
        var copiedKeys: Unmanaged<CFArray>?
        let status = CopySymbolicHotKeys(&copiedKeys)
        guard status == noErr else { throw ShortcutRegistrationError.carbon(status) }
        guard let keys = copiedKeys?.takeRetainedValue() as? [[String: Any]] else { return }
        for key in keys {
            guard let enabled = key[kHISymbolicHotKeyEnabled as String] as? NSNumber,
                  enabled.boolValue,
                  let keyCode = key[kHISymbolicHotKeyCode as String] as? NSNumber,
                  let modifiers = key[kHISymbolicHotKeyModifiers as String] as? NSNumber else { continue }
            if keyCode.uint32Value == shortcut.keyCode,
               modifiers.uint32Value & Shortcut.allowedModifiers == shortcut.modifiers {
                throw ShortcutRegistrationError.systemConflict
            }
        }
    }
}

@MainActor
final class GlobalShortcuts {
    var onTrigger: ((PlacementAction) -> Void)?
    var onRecord: ((Shortcut) -> Void)?
    var onError: ((String) -> Void)?

    private struct Registration {
        let id: UInt32
        let action: PlacementAction
        let validAfter: TimeInterval
    }
    private struct HeldKey { var suppressed: Bool }

    private let backend: any ShortcutRegistrationBackend
    private let clock: any ShortcutRepeatClock
    private let currentModifiers: () -> UInt32
    private var registrations: [Shortcut: Registration] = [:]
    private var shortcutsByID: [UInt32: Shortcut] = [:]
    private var retiredIDs: Set<UInt32> = []
    private var held: [UInt32: HeldKey] = [:]
    private var lastEventTimes: [UInt32: TimeInterval] = [:]
    private var inputBarrier: TimeInterval = -.infinity
    private var recording = false
    private var recorded = false
    private var repeatingID: UInt32?
    private var repeatGeneration: UInt64 = 0
    private var repeatTask: (any ShortcutScheduledTask)?
    private static var nextID: UInt32 = 0

    convenience init() {
        self.init(backend: CarbonShortcutBackend(), clock: SystemShortcutRepeatClock(), currentModifiers: {
            let flags = NSEvent.modifierFlags
            var value: UInt32 = 0
            if flags.contains(.command) { value |= UInt32(cmdKey) }
            if flags.contains(.control) { value |= UInt32(controlKey) }
            if flags.contains(.option) { value |= UInt32(optionKey) }
            if flags.contains(.shift) { value |= UInt32(shiftKey) }
            return value
        })
    }

    init(backend: any ShortcutRegistrationBackend, clock: any ShortcutRepeatClock,
         currentModifiers: @escaping () -> UInt32) {
        self.backend = backend
        self.clock = clock
        self.currentModifiers = currentModifiers
        backend.onEvent = { [weak self] in self?.receive($0) }
    }

    func contains(_ shortcut: Shortcut) -> Bool { registrations[shortcut] != nil }

    func register(_ bindings: DirectionalShortcuts) throws {
        if let error = bindings.validationError { throw error }
        retryRetiredRegistrations()
        let actions = PlacementAction.allCases.filter { bindings[$0] != nil }
        if registrations.count == actions.count,
           actions.allSatisfy({ action in
               bindings[action].map { registrations[$0]?.action == action } ?? false
           }) { return }
        var added: [Shortcut: UInt32] = [:]
        do {
            for action in actions {
                guard let shortcut = bindings[action] else { continue }
                guard registrations[shortcut] == nil else { continue }
                guard Self.nextID < UInt32.max else {
                    throw ShortcutRegistrationError.binding(action, L10n.text("Restart Tessera before changing more shortcuts."))
                }
                Self.nextID += 1
                let id = Self.nextID
                do { try backend.register(shortcut, id: id) }
                catch { throw ShortcutRegistrationError.binding(action, error.localizedDescription) }
                added[shortcut] = id
            }
        } catch {
            for id in added.values { retire(id) }
            throw error
        }

        cancelInput()
        let timestamp = clock.now
        var replacement: [Shortcut: Registration] = [:]
        for action in actions {
            guard let shortcut = bindings[action] else { continue }
            guard let id = registrations[shortcut]?.id ?? added[shortcut] else { continue }
            replacement[shortcut] = Registration(id: id, action: action, validAfter: timestamp)
        }
        let removedIDs = registrations.filter { replacement[$0.key] == nil }.map { $0.value.id }
        registrations = replacement
        shortcutsByID = Dictionary(uniqueKeysWithValues: replacement.map { ($0.value.id, $0.key) })
        for id in removedIDs {
            held.removeValue(forKey: id)
            lastEventTimes.removeValue(forKey: id)
            retire(id)
        }
    }

    /// Only the first migration may omit a conflicting new Maximize chord.
    /// Later edits use register(_:) so an unsuccessful batch keeps the old set.
    func registerAtStartup(_ bindings: DirectionalShortcuts, allowMaximizeFallback: Bool) throws
        -> (bindings: DirectionalShortcuts, warning: String?) {
        do {
            try register(bindings)
            return (bindings, nil)
        } catch ShortcutRegistrationError.binding(.maximize, let message) {
            guard allowMaximizeFallback, bindings.maximize != nil else {
                throw ShortcutRegistrationError.binding(.maximize, message)
            }
            var fallback = bindings
            fallback.maximize = nil
            try register(fallback)
            return (fallback, L10n.format("Maximize shortcut was not assigned. Your direction shortcuts are unchanged. %@", message))
        }
    }

    func unregister() {
        cancelInput()
        let ids = Array(shortcutsByID.keys)
        registrations.removeAll()
        shortcutsByID.removeAll()
        held.removeAll()
        lastEventTimes.removeAll()
        for id in ids { retire(id) }
        retryRetiredRegistrations()
    }

    func setRecording(_ value: Bool) {
        guard value != recording else { return }
        cancelInput()
        recording = value
        recorded = false
    }

    func cancelInput() {
        inputBarrier = clock.now
        for id in Array(held.keys) { held[id]?.suppressed = true }
        stopRepeat()
    }

    private func receive(_ event: RegisteredShortcutEvent) {
        guard let shortcut = shortcutsByID[event.id], let registration = registrations[shortcut] else { return }
        if let last = lastEventTimes[event.id], event.timestamp < last { return }
        lastEventTimes[event.id] = event.timestamp
        if event.phase == .released {
            held.removeValue(forKey: event.id)
            if repeatingID == event.id { stopRepeat() }
            return
        }
        guard held[event.id] == nil else { return }
        let suppressed = event.timestamp < max(inputBarrier, registration.validAfter)
        held[event.id] = HeldKey(suppressed: suppressed)
        guard !suppressed else { return }
        stopRepeat()
        if recording {
            guard !recorded else { return }
            recorded = true
            onRecord?(shortcut)
            return
        }
        let generation = repeatGeneration
        shortcutLogger.notice("Placement hotkey accepted: id=\(event.id, privacy: .public) action=\(String(describing: registration.action), privacy: .public)")
        onTrigger?(registration.action)
        guard generation == repeatGeneration, held[event.id]?.suppressed == false, !recording,
              registration.action.repeatsHorizontally,
              clock.repeatDelay.isFinite, clock.repeatDelay >= 0,
              clock.repeatInterval.isFinite, clock.repeatInterval > 0 else { return }
        repeatingID = event.id
        scheduleRepeat(id: event.id, generation: generation, after: clock.repeatDelay)
    }

    private func scheduleRepeat(id: UInt32, generation: UInt64, after delay: TimeInterval) {
        repeatTask = clock.schedule(after: delay) { [weak self] in
            guard let self, self.repeatGeneration == generation, self.repeatingID == id,
                  self.held[id]?.suppressed == false, !self.recording,
                  let shortcut = self.shortcutsByID[id], let registration = self.registrations[shortcut] else { return }
            // Read current modifiers outside the event stream. No event tap or
            // Input Monitoring permission is requested for repeat handling.
            guard self.currentModifiers() == shortcut.modifiers else {
                self.held[id]?.suppressed = true
                self.stopRepeat()
                return
            }
            self.onTrigger?(registration.action)
            guard self.repeatGeneration == generation, self.repeatingID == id else { return }
            self.scheduleRepeat(id: id, generation: generation, after: self.clock.repeatInterval)
        }
    }

    private func stopRepeat() {
        repeatGeneration &+= 1
        repeatTask?.cancel()
        repeatTask = nil
        repeatingID = nil
    }

    private func retire(_ id: UInt32) {
        do {
            try backend.unregister(id: id)
            retiredIDs.remove(id)
        } catch {
            retiredIDs.insert(id)
            onError?(L10n.format("A previous shortcut could not be released. Restart Tessera if it remains reserved. %@", error.localizedDescription))
        }
    }

    private func retryRetiredRegistrations() {
        for id in Array(retiredIDs) { retire(id) }
    }
}
