import Foundation

/// `AXEnhancedUserInterface` is an undocumented application attribute that
/// assistive clients turn on. While it is on, Brave animates frame changes: a
/// size write reads back at once, but the following position write reapplies
/// the size from before that write, so a window moved right can extend past
/// the display edge (issue #11). Placement suspends the attribute for the
/// affected application only and restores it after the final readback.
enum EnhancedUserInterface {
    static let attribute = "AXEnhancedUserInterface"

    /// The applications whose placements suspend the attribute: Brave release
    /// and its dot-suffixed channels such as `com.brave.Browser.beta`. Every
    /// other application, including other Chromium browsers, keeps its exact
    /// current placement behavior.
    static func requiresSuspension(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        let brave = "com.brave.Browser"
        return bundleIdentifier == brave || bundleIdentifier.hasPrefix(brave + ".")
    }

    /// Runs `body` with the attribute off when `enabled` and the attribute is
    /// currently on; otherwise nothing is read or written. An AX setter error
    /// is ambiguous — the value can still have changed — so once the attribute
    /// was on, restoration is always attempted, even after a failed suspension,
    /// and a failed restoration is retried once. `write` reports success.
    static func withSuspended<Result>(
        when enabled: Bool,
        read: () -> Bool?,
        write: (Bool) -> Bool,
        body: () -> Result
    ) -> Result {
        guard enabled, read() == true else { return body() }
        _ = write(false)
        defer { if !write(true) { _ = write(true) } }
        return body()
    }
}
