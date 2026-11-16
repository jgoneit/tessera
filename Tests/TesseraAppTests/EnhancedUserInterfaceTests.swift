import CoreGraphics
import Testing
@testable import TesseraApp

@Suite("Brave enhanced user interface suspension", .timeLimit(.minutes(1)))
@MainActor
struct EnhancedUserInterfaceTests {
    // Issue #11: a 5120×2160 display at scale 1 with a 30 pt menu bar, AX space.
    private let visible = CGRect(x: 0, y: 30, width: 5120, height: 2130)
    private let twoByTwoColumnTwo = CGRect(x: 2560, y: 30, width: 2560, height: 2130)
    private let threeByTwoColumnThree = CGRect(x: 3414, y: 30, width: 1706, height: 2130)

    @Test("Brave and its release channels suspend the attribute during placement",
          arguments: ["com.brave.Browser", "com.brave.Browser.beta", "com.brave.Browser.nightly"])
    func braveRequiresSuspension(_ bundleIdentifier: String) {
        #expect(EnhancedUserInterface.requiresSuspension(bundleIdentifier: bundleIdentifier))
    }

    @Test("Other applications, including other Chromium browsers, keep their current behavior",
          arguments: [nil, "", "com.brave.BrowserHelper", "com.brave", "com.google.Chrome",
                      "com.microsoft.edgemac", "company.thebrowser.Browser", "com.apple.Safari"] as [String?])
    func otherApplicationsUnchanged(_ bundleIdentifier: String?) {
        #expect(!EnhancedUserInterface.requiresSuspension(bundleIdentifier: bundleIdentifier))
    }

    @Test("An enabled attribute is off for the whole body and restored afterwards")
    func suspendsAndRestores() {
        var events: [String] = []
        let result = EnhancedUserInterface.withSuspended(when: true,
            read: { events.append("read"); return true },
            write: { events.append("write(\($0))"); return true },
            body: { events.append("body"); return 42 })
        #expect(result == 42)
        #expect(events == ["read", "write(false)", "body", "write(true)"])
    }

    @Test("An off, absent or unreadable attribute is never written", arguments: [false, nil] as [Bool?])
    func leavesOtherStatesAlone(_ value: Bool?) {
        var events: [String] = []
        EnhancedUserInterface.withSuspended(when: true,
            read: { events.append("read"); return value },
            write: { events.append("write(\($0))"); return true },
            body: { events.append("body") })
        #expect(events == ["read", "body"])
    }

    @Test("A disabled suspension neither reads nor writes the attribute")
    func disabledSkipsAttribute() {
        var events: [String] = []
        EnhancedUserInterface.withSuspended(when: false,
            read: { events.append("read"); return true },
            write: { events.append("write(\($0))"); return true },
            body: { events.append("body") })
        #expect(events == ["body"])
    }

    @Test("A failed suspension still restores, and a failed restoration is retried once")
    func retriesFailedRestoration() {
        var events: [String] = []
        var failures = 2 // the suspension and the first restoration fail
        EnhancedUserInterface.withSuspended(when: true,
            read: { events.append("read"); return true },
            write: { events.append("write(\($0))"); failures -= 1; return failures < 0 },
            body: { events.append("body") })
        #expect(events == ["read", "write(false)", "body", "write(true)", "write(true)"])
    }

    @Test("Issue #11: Brave's move from 2×2 column 2 to 3×2 column 3 overflows without suspension")
    func reproducesIssue() {
        let window = AnimatedFrameWindow(frame: twoByTwoColumnTwo)
        let result = window.place(threeByTwoColumnThree, in: visible, suspending: false)
        #expect(result.outcome == .constrained)
        #expect(result.constraintReason == .outsideVisibleArea)
        #expect(result.actualFrame == CGRect(x: 3414, y: 30, width: 2560, height: 2130))
        #expect(window.attributeWrites.isEmpty)
    }

    @Test("Issue #11: suspension places the window exactly and restores the attribute")
    func fixesIssue() {
        let window = AnimatedFrameWindow(frame: twoByTwoColumnTwo)
        let result = window.place(threeByTwoColumnThree, in: visible, suspending: true)
        #expect(result.outcome == .applied)
        #expect(result.actualFrame == threeByTwoColumnThree)
        #expect(window.frame == threeByTwoColumnThree)
        #expect(window.attributeWrites == [false, true])
        #expect(window.enhancedUserInterface)
    }

    @Test("A failed placement still restores the attribute")
    func restoresAfterFailure() {
        let window = AnimatedFrameWindow(frame: twoByTwoColumnTwo)
        window.failingSize = true
        let result = window.place(threeByTwoColumnThree, in: visible, suspending: true)
        #expect(result.outcome == .failed)
        #expect(window.attributeWrites == [false, true])
        #expect(window.enhancedUserInterface)
    }
}

/// Reproduces the frames Brave reported in issue #11. While the attribute is
/// on, a size write reads back immediately but does not settle, and the next
/// position write reapplies the settled size. With the attribute off, every
/// write settles at once.
@MainActor
private final class AnimatedFrameWindow {
    enum Failure: Error { case injected }

    private(set) var frame: CGRect
    private(set) var enhancedUserInterface = true
    private(set) var attributeWrites: [Bool] = []
    var failingSize = false
    private var settledSize: CGSize

    init(frame: CGRect) {
        self.frame = frame
        settledSize = frame.size
    }

    func place(_ requested: CGRect, in visible: CGRect, suspending: Bool) -> PlacementResult {
        let transaction = {
            WindowPlacement.perform(frame: requested, visibleFrame: visible,
                readFrame: { self.frame }, validate: {},
                setSize: { try self.setSize($0) }, setPosition: { self.setPosition($0) })
        }
        return EnhancedUserInterface.withSuspended(when: suspending,
            read: { self.enhancedUserInterface },
            write: { self.attributeWrites.append($0); self.enhancedUserInterface = $0; return true },
            body: transaction)
    }

    private func setSize(_ size: CGSize) throws {
        if failingSize { throw Failure.injected }
        frame.size = size
        if !enhancedUserInterface { settledSize = size }
    }

    private func setPosition(_ origin: CGPoint) {
        frame.origin = origin
        if enhancedUserInterface { frame.size = settledSize } else { settledSize = frame.size }
    }
}
