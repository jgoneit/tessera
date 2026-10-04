import AppKit
import TesseraCore

/// A current display snapshot in AppKit's global, bottom-left-origin point space.
struct ScreenSnapshot: Sendable {
    let displays: [DisplayGeometry]
    let primaryTop: CGFloat

    func matches(_ other: ScreenSnapshot) -> Bool {
        primaryTop == other.primaryTop
            && displays.sorted { $0.id < $1.id } == other.displays.sorted { $0.id < $1.id }
    }

    /// Resolve the immutable destination only against the captured topology.
    /// A disconnected display must never silently fall back to another one.
    func display(for destination: GridPlacement, captured: ScreenSnapshot) -> DisplayGeometry? {
        guard matches(captured), let id = destination.displayID else { return nil }
        return displays.first { $0.id == id }
    }
}

@MainActor
enum ScreenCatalog {
    static func snapshot() -> ScreenSnapshot {
        let screens = NSScreen.screens
        let primaryTop = screens.first?.frame.maxY ?? 0
        let displays = screens.compactMap { screen -> DisplayGeometry? in
            guard let id = displayID(for: screen) else { return nil }
            return DisplayGeometry(
                id: id,
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                scale: screen.backingScaleFactor
            )
        }
        return ScreenSnapshot(displays: displays, primaryTop: primaryTop)
    }

    static func screen(id: UInt32) -> NSScreen? {
        NSScreen.screens.first { displayID(for: $0) == id }
    }

    private static func displayID(for screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
