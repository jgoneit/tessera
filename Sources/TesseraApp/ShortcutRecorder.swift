import AppKit
import SwiftUI

/// Shares the active recorder with the registered Carbon hot-key handler.
/// Registrations stay installed while recording; their callbacks update a draft.
@MainActor
final class ShortcutRecordingBridge {
    var onRecordingChanged: ((Bool) -> Void)?
    private weak var activeRecorder: ShortcutRecorderButton?

    func receiveRegistered(_ shortcut: Shortcut) {
        activeRecorder?.receiveRegistered(shortcut)
    }

    func cancelRecording() {
        activeRecorder?.finishRecording()
    }

    func beginRecording(_ recorder: ShortcutRecorderButton) {
        guard activeRecorder !== recorder else { return }
        activeRecorder?.finishRecording()
        if recorder.isRecording { recorder.finishRecording() }
        recorder.bridge = self
        activeRecorder = recorder
        recorder.activateRecording()
        onRecordingChanged?(true)
    }

    fileprivate func finishedRecording(_ recorder: ShortcutRecorderButton) {
        guard activeRecorder === recorder else { return }
        activeRecorder = nil
        onRecordingChanged?(false)
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let current: Shortcut?
    let label: String
    let bridge: ShortcutRecordingBridge
    let onRecord: (Shortcut) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        updateNSView(button, context: context)
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        if button.bridge !== bridge { button.finishRecording() }
        button.current = current
        button.bridge = bridge
        button.onRecord = onRecord
        button.setAccessibilityLabel(label)
        button.refreshTitle()
    }

    static func dismantleNSView(_ button: ShortcutRecorderButton, coordinator: ()) {
        button.finishRecording()
    }
}

@MainActor
final class ShortcutRecorderButton: NSButton {
    var current: Shortcut? = .default
    var onRecord: ((Shortcut) -> Void)?
    weak var bridge: ShortcutRecordingBridge?
    private(set) var isRecording = false
    private var windowObservers: [NSObjectProtocol] = []

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(startRecording)
        setAccessibilityLabel(L10n.text("Direction shortcut"))
        refreshTitle()
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    func refreshTitle() {
        title = isRecording ? L10n.text("Press shortcut…") : (current?.displayString ?? L10n.text("Not assigned"))
        toolTip = isRecording
            ? L10n.text("Press a key with Command, Control, or Option. Escape cancels.")
            : L10n.text("Record a window shortcut, then use Apply Shortcuts to save all five.")
    }

    @objc private func startRecording() {
        guard !isRecording else { finishRecording(); return }
        guard window?.makeFirstResponder(self) == true else { return }
        bridge?.beginRecording(self)
    }

    fileprivate func activateRecording() {
        isRecording = true
        refreshTitle()
    }

    func finishRecording() {
        guard isRecording else { return }
        isRecording = false
        refreshTitle()
        bridge?.finishedRecording(self)
    }

    override func resignFirstResponder() -> Bool {
        finishRecording()
        return super.resignFirstResponder()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }
        windowObservers.removeAll()
        finishRecording()
        if let newWindow {
            for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
                let observer = NotificationCenter.default.addObserver(
                    forName: name, object: newWindow, queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.finishRecording() }
                }
                windowObservers.append(observer)
            }
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }
        record(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        record(event)
        return true
    }

    fileprivate func receiveRegistered(_ shortcut: Shortcut) {
        guard isRecording else { return }
        accept(shortcut)
    }

    private func record(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        if event.keyCode == 53 {
            finishRecording()
            return
        }
        accept(Shortcut(event: event))
    }

    private func accept(_ candidate: Shortcut) {
        if let message = candidate.validationMessage {
            title = L10n.text("Try another shortcut…")
            toolTip = message
            return
        }
        finishRecording()
        onRecord?(candidate)
    }
}
