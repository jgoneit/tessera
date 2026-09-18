import CoreGraphics
import TesseraCore

/// Logical navigation and AX readback for one direct arrangement target.
/// The caller resets this value when the target or its geometry context changes.
struct DirectNavigationState: Sendable {
    private(set) var navigation: GridNavigation
    /// AX top-left coordinates; never used to infer a new logical height after placement.
    private(set) var lastConfirmedFrame: CGRect?

    init(navigation: GridNavigation) {
        self.navigation = navigation
        lastConfirmedFrame = nil
    }

    /// Both input rectangles use AppKit's bottom-left coordinate space. The
    /// caller may separately record the initial AX frame before the first move.
    init(
        layout: LayoutPreset,
        windowFrame: CGRect,
        visibleFrame: CGRect,
        gap: CGFloat = 8,
        scale: CGFloat = 1
    ) {
        self.init(layouts: [layout], windowFrame: windowFrame,
            visibleFrame: visibleFrame, gap: gap, scale: scale)
    }

    init(
        layouts: [LayoutPreset],
        windowFrame: CGRect,
        visibleFrame: CGRect,
        gap: CGFloat = 8,
        scale: CGFloat = 1
    ) {
        self.init(navigation: GridNavigation(
            layouts: layouts, windowFrame: windowFrame, visibleFrame: visibleFrame,
            gap: gap, scale: scale
        ))
    }

    mutating func move(_ direction: GridDirection) -> GridPlacement? {
        guard navigation.move(direction) else { return nil }
        return navigation.selectedPlacement
    }

    /// App constraints update the observed frame while preserving accepted steps.
    mutating func record(actualFrame: CGRect) {
        lastConfirmedFrame = actualFrame
    }

    func matchesLastConfirmed(_ frame: CGRect) -> Bool {
        guard let lastConfirmedFrame else { return false }
        return PlacementResult.matchesRequestedFrame(frame, lastConfirmedFrame)
    }
}
