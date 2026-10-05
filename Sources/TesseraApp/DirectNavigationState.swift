import CoreGraphics
import TesseraCore

/// Logical navigation and AX readback for one direct arrangement target.
/// The caller resets this value when the target or its geometry context changes.
struct DirectNavigationState: Sendable {
    private(set) var navigation: GridNavigation
    private(set) var display: DisplayGeometry?
    private var displays: [DisplayGeometry] = []
    /// AX top-left coordinates; never used to infer a new logical height after placement.
    private(set) var lastConfirmedFrame: CGRect?

    init(navigation: GridNavigation) {
        self.navigation = navigation
        lastConfirmedFrame = nil
    }

    init(layouts: [LayoutPreset], windowFrame: CGRect, display: DisplayGeometry,
         displays: [DisplayGeometry], gap: CGFloat = 8) {
        self.init(layouts: layouts, windowFrame: windowFrame, visibleFrame: display.visibleFrame,
            gap: gap, scale: display.scale)
        self.display = display
        self.displays = displays
    }

    var selectedPlacement: GridPlacement {
        GridPlacement(layout: navigation.layout, target: navigation.selectedTarget, displayID: display?.id)
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
        let destination = navigation.isAtEdge(toward: direction)
            ? display.flatMap { DisplaySelection.navigationDestination(of: $0, toward: direction, in: displays) } : nil
        guard navigation.move(direction, crossingDisplayBoundary: destination != nil) else { return nil }
        if let destination { display = destination }
        return selectedPlacement
    }

    /// Reapply maximize even if already selected; an app may have adjusted its size.
    mutating func maximize() -> GridPlacement {
        navigation.maximize()
        return selectedPlacement
    }

    mutating func apply(_ action: PlacementAction) -> GridPlacement? {
        switch action {
        case .direction(let direction): move(direction)
        case .maximize: maximize()
        }
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
