import AppKit
import Testing
@testable import TesseraApp

@Suite("Settings and update window presence")
struct AppPresentationTests {
    @Test("Closing either window preserves app switching while the other remains open")
    func independentWindows() {
        var state = AppPresentation()
        #expect(state.activationPolicy == .accessory)
        state.settingsOpen = true
        #expect(state.activationPolicy == .regular)
        state.updateOpen = true
        state.settingsOpen = false
        #expect(state.activationPolicy == .regular)
        state.settingsOpen = true
        state.updateOpen = false
        #expect(state.activationPolicy == .regular)
        state.settingsOpen = false
        #expect(state.activationPolicy == .accessory)
    }
}
