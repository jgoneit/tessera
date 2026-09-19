import AppKit
import Carbon
import Testing
@testable import TesseraApp

@Suite("Shortcut recording bridge")
@MainActor
struct ShortcutRecordingTests {
    @Test("An unassigned recorder displays a label and accepts the registered Maximize chord")
    func unassignedRecorderAcceptsMaximize() {
        let bridge = ShortcutRecordingBridge()
        let button = ShortcutRecorderButton()
        button.current = nil
        button.refreshTitle()
        #expect(button.title == L10n.text("Not assigned"))
        var recorded: [Shortcut] = []
        button.onRecord = { recorded.append($0) }
        bridge.beginRecording(button)
        bridge.receiveRegistered(.defaultMaximize)
        #expect(recorded == [.defaultMaximize])
        #expect(button.current == nil)
        #expect(!button.isRecording)
    }

    @Test("Changing presentation preferences ends recording before another registered key arrives")
    func presentationChangeCancelsRecording() {
        let bridge = ShortcutRecordingBridge()
        let button = ShortcutRecorderButton()
        var recorded: [Shortcut] = []
        var changes: [Bool] = []
        button.onRecord = { recorded.append($0) }
        bridge.onRecordingChanged = { changes.append($0) }
        bridge.beginRecording(button)
        bridge.cancelRecording()
        bridge.cancelRecording()
        bridge.receiveRegistered(DirectionalShortcuts.default.right)
        #expect(!button.isRecording)
        #expect(recorded.isEmpty)
        #expect(changes == [true, false])
    }

    @Test("A registered key updates only the active draft and ends recording once")
    func registeredKeyUpdatesDraft() {
        let bridge = ShortcutRecordingBridge()
        let button = ShortcutRecorderButton()
        let saved = DirectionalShortcuts.default.left
        let candidate = DirectionalShortcuts.default.right
        button.current = saved
        var recorded: [Shortcut] = []
        var changes: [Bool] = []
        button.onRecord = { recorded.append($0) }
        bridge.onRecordingChanged = { changes.append($0) }
        bridge.beginRecording(button)
        #expect(button.isRecording)
        bridge.receiveRegistered(candidate)
        bridge.receiveRegistered(candidate)
        #expect(recorded == [candidate])
        #expect(button.current == saved)
        #expect(!button.isRecording)
        #expect(changes == [true, false])
    }

    @Test("Beginning another recorder cancels the first and routes exclusively to the second")
    func onlyOneRecorderIsActive() {
        let bridge = ShortcutRecordingBridge()
        let first = ShortcutRecorderButton()
        let second = ShortcutRecorderButton()
        var firstRecords: [Shortcut] = []
        var secondRecords: [Shortcut] = []
        first.onRecord = { firstRecords.append($0) }
        second.onRecord = { secondRecords.append($0) }
        bridge.beginRecording(first)
        bridge.beginRecording(second)
        #expect(!first.isRecording)
        #expect(second.isRecording)
        first.finishRecording()
        #expect(second.isRecording)
        bridge.receiveRegistered(DirectionalShortcuts.default.up)
        #expect(firstRecords.isEmpty)
        #expect(secondRecords == [DirectionalShortcuts.default.up])
        #expect(!second.isRecording)
    }

    @Test("Invalid input stays in recording without modifying the draft")
    func invalidCandidateKeepsRecording() {
        let bridge = ShortcutRecordingBridge()
        let button = ShortcutRecorderButton()
        var recorded: [Shortcut] = []
        button.onRecord = { recorded.append($0) }
        bridge.beginRecording(button)
        bridge.receiveRegistered(Shortcut(keyCode: UInt32(kVK_ANSI_G), modifiers: 0))
        #expect(button.isRecording)
        #expect(recorded.isEmpty)
        #expect(button.toolTip != nil)
        button.finishRecording()
        #expect(!button.isRecording)
    }

    @Test("Physical key events record independently of text input and ignore repeat")
    func physicalKeyRecording() throws {
        let bridge = ShortcutRecordingBridge()
        let button = ShortcutRecorderButton()
        var recorded: [Shortcut] = []
        button.onRecord = { recorded.append($0) }
        bridge.beginRecording(button)
        button.keyDown(with: try keyEvent(keyCode: kVK_ANSI_G, modifiers: [.command, .option], repeatKey: true))
        #expect(button.isRecording)
        #expect(recorded.isEmpty)
        button.keyDown(with: try keyEvent(keyCode: kVK_ANSI_G, modifiers: [.command, .option]))
        #expect(recorded == [Shortcut(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(cmdKey | optionKey))])
        #expect(!button.isRecording)
    }

    @Test("Escape and explicit cancellation leave the draft untouched")
    func cancellationDoesNotRecord() throws {
        let bridge = ShortcutRecordingBridge()
        let button = ShortcutRecorderButton()
        var recorded: [Shortcut] = []
        var changes: [Bool] = []
        button.onRecord = { recorded.append($0) }
        bridge.onRecordingChanged = { changes.append($0) }
        bridge.beginRecording(button)
        button.keyDown(with: try keyEvent(keyCode: kVK_Escape))
        #expect(!button.isRecording)
        bridge.beginRecording(button)
        button.finishRecording()
        button.finishRecording()
        #expect(recorded.isEmpty)
        #expect(changes == [true, false, true, false])
    }

    @Test("Moving a recorder out of its window cancels routing")
    func removalEndsRecording() {
        let bridge = ShortcutRecordingBridge()
        let button = ShortcutRecorderButton()
        var recorded: [Shortcut] = []
        button.onRecord = { recorded.append($0) }
        bridge.beginRecording(button)
        button.viewWillMove(toWindow: nil)
        bridge.receiveRegistered(DirectionalShortcuts.default.down)
        #expect(!button.isRecording)
        #expect(recorded.isEmpty)
    }

    private func keyEvent(keyCode: Int, modifiers: NSEvent.ModifierFlags = [], repeatKey: Bool = false) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "ㅎ", charactersIgnoringModifiers: "ㅎ",
            isARepeat: repeatKey, keyCode: UInt16(keyCode)
        ))
    }
}
