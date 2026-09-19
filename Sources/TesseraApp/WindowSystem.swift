import ApplicationServices
import Foundation
import OSLog
import TesseraCore

/// Sendable metadata only; the Accessibility reference never leaves its actor.
struct WindowTarget: Sendable {
    let token: UUID
    let pid: pid_t
    /// The most recently captured or resolved outer frame in AX global screen points.
    let frame: CGRect
}

struct PlacementResult: Sendable {
    enum Outcome: Sendable, Equatable {
        case applied
        case constrained
        case unavailable
        case failed
    }

    enum ConstraintReason: Sendable, Equatable {
        case sizeAdjusted
        case positionMismatch
        case outsideVisibleArea
    }

    let outcome: Outcome
    let message: String
    let actualFrame: CGRect?
    let constraintReason: ConstraintReason?

    init(outcome: Outcome, message: String, actualFrame: CGRect?, constraintReason: ConstraintReason? = nil) {
        self.outcome = outcome
        self.message = message
        self.actualFrame = actualFrame
        self.constraintReason = constraintReason
    }

    var feedbackDuration: Duration {
        outcome == .applied || (outcome == .constrained && constraintReason == .sizeAdjusted)
            ? .seconds(1) : .seconds(4)
    }

    /// Only floating-point noise counts as an exact placement. Pixel-sized
    /// adjustments remain constrained, including accumulated far-edge changes.
    static func matchesRequestedFrame(_ actual: CGRect, _ requested: CGRect) -> Bool {
        let epsilon: CGFloat = 0.001
        return abs(actual.minX - requested.minX) <= epsilon
            && abs(actual.minY - requested.minY) <= epsilon
            && abs(actual.maxX - requested.maxX) <= epsilon
            && abs(actual.maxY - requested.maxY) <= epsilon
    }
}

enum WindowSystemError: Error, LocalizedError, Sendable {
    case permissionRequired
    case noFocusedWindow
    case unsupportedWindow(String)
    case targetChanged
    case targetUnavailable
    case invalidGeometry
    case accessibility(operation: String, code: Int32)

    var errorDescription: String? {
        switch self {
        case .permissionRequired:
            L10n.text("Allow Tessera in System Settings → Privacy & Security → Accessibility.")
        case .noFocusedWindow:
            L10n.text("Activate a normal application window, then arrange it again.")
        case .unsupportedWindow(let reason):
            L10n.text(reason)
        case .targetChanged:
            L10n.text("The active window changed. Open the zone selector again.")
        case .targetUnavailable:
            L10n.text("The selected window is no longer available.")
        case .invalidGeometry:
            L10n.text("The window or display has an invalid frame.")
        case .accessibility(let operation, let code):
            L10n.format("Could not %@ through Accessibility (%ld).", L10n.text(operation), Int(code))
        }
    }
}

/// Synchronous AX IPC runs on this actor's executor, never on the UI main actor.
/// References are retained for an arrangement session until the caller explicitly discards them.
actor WindowSystem {
    private struct Session {
        let pid: pid_t
        let application: AXUIElement
        let window: AXUIElement
    }

    private var sessions: [UUID: Session] = [:]
    private let messagingTimeout: Float = 0.5
    private let log = Logger(subsystem: "io.github.jgoneit.tessera", category: "window")

    nonisolated static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func capture(pid: pid_t) throws -> WindowTarget {
        try resolveFocusedTarget(pid: pid, reusing: nil)
    }

    /// Reads the application's current focused window on every request. Reuse is
    /// based on AX identity, never just the application's pid or the window frame.
    /// The caller still owns disposal of any previous, different target.
    func resolveFocusedTarget(pid: pid_t, reusing target: WindowTarget?) throws -> WindowTarget {
        try Task.checkCancellation()
        guard Self.isTrusted() else { throw WindowSystemError.permissionRequired }
        guard pid > 0, pid != ProcessInfo.processInfo.processIdentifier else {
            throw WindowSystemError.noFocusedWindow
        }

        let application = AXUIElementCreateApplication(pid)
        try configureTimeout(for: application)
        guard let window = try focusedWindow(of: application) else {
            throw WindowSystemError.noFocusedWindow
        }
        try configureTimeout(for: window)
        try validate(window)
        let frame = try readFrame(of: window)
        try Task.checkCancellation()
        if let target, target.pid == pid,
           let previous = sessions[target.token], previous.pid == pid,
           CFEqual(previous.window, window) {
            sessions[target.token] = Session(pid: pid, application: application, window: window)
            return WindowTarget(token: target.token, pid: pid, frame: frame)
        }
        let token = UUID()
        sessions[token] = Session(pid: pid, application: application, window: window)
        return WindowTarget(token: token, pid: pid, frame: frame)
    }

    func discard(target: WindowTarget) {
        sessions.removeValue(forKey: target.token)
    }

    func currentFrame(of target: WindowTarget) throws -> CGRect {
        guard Self.isTrusted() else { throw WindowSystemError.permissionRequired }
        guard let session = sessions[target.token], session.pid == target.pid else {
            throw WindowSystemError.targetUnavailable
        }
        try validate(session.window)
        return try readFrame(of: session.window)
    }

    func place(target: WindowTarget, frame: CGRect, visibleFrame: CGRect) -> PlacementResult {
        guard let session = sessions[target.token], session.pid == target.pid else {
            return PlacementResult(outcome: .unavailable,
                message: WindowSystemError.targetUnavailable.localizedDescription, actualFrame: nil)
        }
        // The transaction stays synchronous on this actor; AX references never
        // escape. Every attempted write revalidates cancellation, focus and trust.
        return WindowPlacement.perform(frame: frame, visibleFrame: visibleFrame,
            readFrame: { try self.readFrame(of: session.window) },
            validate: { try self.validateForMutation(session) },
            setSize: { try self.setSize($0, of: session.window) },
            setPosition: { try self.setPosition($0, of: session.window) },
            trace: { stage, observed in
                self.log.notice("AX frame \(stage, privacy: .public): pid=\(session.pid) x=\(Double(observed.minX)) y=\(Double(observed.minY)) width=\(Double(observed.width)) height=\(Double(observed.height))")
            })
    }

    private func configureTimeout(for element: AXUIElement) throws {
        let error = AXUIElementSetMessagingTimeout(element, messagingTimeout)
        guard error == .success else { throw axError(error, operation: "set the response timeout") }
    }

    private func validateForMutation(_ session: Session) throws {
        try Task.checkCancellation()
        guard Self.isTrusted() else { throw WindowSystemError.permissionRequired }
        try validate(session.window)
        guard let focused = try focusedWindow(of: session.application) else {
            throw WindowSystemError.targetUnavailable
        }
        guard CFEqual(focused, session.window) else { throw WindowSystemError.targetChanged }
        // An inactive app can retain its own focused-window attribute. Reject an
        // explicit loss of frontmost status too; absent optional support still
        // relies on the coordinator's application check and cancellation.
        if try boolAttribute(kAXFrontmostAttribute, of: session.application) == false {
            throw WindowSystemError.targetChanged
        }
        // AX reads can block. Recheck cancellation and trust after those reads,
        // immediately before the caller performs its one attribute write.
        try Task.checkCancellation()
        guard Self.isTrusted() else { throw WindowSystemError.permissionRequired }
    }

    private func validate(_ window: AXUIElement) throws {
        guard try stringAttribute(kAXRoleAttribute, of: window) == kAXWindowRole,
              try stringAttribute(kAXSubroleAttribute, of: window) == kAXStandardWindowSubrole else {
            throw WindowSystemError.unsupportedWindow("This is not a standard application window.")
        }
        if try boolAttribute(kAXMinimizedAttribute, of: window) == true {
            throw WindowSystemError.unsupportedWindow("Restore the minimized window before arranging it.")
        }
        if try boolAttribute(kAXModalAttribute, of: window) == true {
            throw WindowSystemError.unsupportedWindow("Modal dialogs cannot be arranged.")
        }
        // Optional capability only: there is no public kAXFullScreenAttribute constant.
        // An absent value is not proof of windowed state; no fullscreen/Space actions run.
        if try boolAttribute("AXFullScreen", of: window) == true {
            throw WindowSystemError.unsupportedWindow("Leave full screen before arranging this window.")
        }
        for attribute in [kAXPositionAttribute, kAXSizeAttribute] {
            var settable = DarwinBoolean(false)
            let error = AXUIElementIsAttributeSettable(window, attribute as CFString, &settable)
            guard error == .success else { throw axError(error, operation: "check window support") }
            guard settable.boolValue else {
                throw WindowSystemError.unsupportedWindow("This window does not allow both moving and resizing.")
            }
        }
    }

    private func focusedWindow(of application: AXUIElement) throws -> AXUIElement? {
        guard let value = try attribute(kAXFocusedWindowAttribute, of: application) else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            throw WindowSystemError.noFocusedWindow
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func attribute(_ name: String, of element: AXUIElement) throws -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        switch error {
        case .success:
            return value
        case .attributeUnsupported, .noValue:
            return nil
        case .invalidUIElement:
            throw WindowSystemError.targetUnavailable
        default:
            throw axError(error, operation: "read the window")
        }
    }

    private func stringAttribute(_ name: String, of element: AXUIElement) throws -> String? {
        guard let value = try attribute(name, of: element) else { return nil }
        guard CFGetTypeID(value) == CFStringGetTypeID() else {
            throw WindowSystemError.unsupportedWindow("The application returned an unsupported window attribute.")
        }
        return value as? String
    }

    private func boolAttribute(_ name: String, of element: AXUIElement) throws -> Bool? {
        guard let value = try attribute(name, of: element) else { return nil }
        guard CFGetTypeID(value) == CFBooleanGetTypeID() else {
            throw WindowSystemError.unsupportedWindow("The application returned an unsupported window attribute.")
        }
        return CFBooleanGetValue(unsafeDowncast(value, to: CFBoolean.self))
    }

    private func readFrame(of window: AXUIElement) throws -> CGRect {
        var origin = CGPoint.zero
        var size = CGSize.zero
        let position = try geometryAttribute(kAXPositionAttribute, of: window, type: .cgPoint)
        let dimensions = try geometryAttribute(kAXSizeAttribute, of: window, type: .cgSize)
        guard AXValueGetValue(position, .cgPoint, &origin), AXValueGetValue(dimensions, .cgSize, &size) else {
            throw WindowSystemError.invalidGeometry
        }
        let frame = CGRect(origin: origin, size: size)
        guard isValid(frame) else { throw WindowSystemError.invalidGeometry }
        return frame
    }

    private func geometryAttribute(_ name: String, of element: AXUIElement, type: AXValueType) throws -> AXValue {
        guard let value = try attribute(name, of: element), CFGetTypeID(value) == AXValueGetTypeID() else {
            throw WindowSystemError.invalidGeometry
        }
        let geometry = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(geometry) == type else { throw WindowSystemError.invalidGeometry }
        return geometry
    }

    private func setSize(_ size: CGSize, of window: AXUIElement) throws {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { throw WindowSystemError.invalidGeometry }
        let error = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
        guard error == .success else { throw axError(error, operation: "resize the window") }
    }

    private func setPosition(_ origin: CGPoint, of window: AXUIElement) throws {
        var origin = origin
        guard let value = AXValueCreate(.cgPoint, &origin) else { throw WindowSystemError.invalidGeometry }
        let error = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        guard error == .success else { throw axError(error, operation: "move the window") }
    }

    private func axError(_ error: AXError, operation: String) -> WindowSystemError {
        if error == .apiDisabled { return .permissionRequired }
        if error == .invalidUIElement { return .targetUnavailable }
        return .accessibility(operation: operation, code: error.rawValue)
    }

    private func isValid(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite && frame.origin.y.isFinite && frame.size.width.isFinite && frame.size.height.isFinite
            && frame.size.width > 0 && frame.size.height > 0 && frame.maxX.isFinite && frame.maxY.isFinite
    }

}
