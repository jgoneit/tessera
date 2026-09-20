import AppKit

/// Settings and an explicit update session independently keep the app discoverable.
struct AppPresentation {
    var settingsOpen = false
    var updateOpen = false

    var activationPolicy: NSApplication.ActivationPolicy {
        settingsOpen || updateOpen ? .regular : .accessory
    }
}
