import AppKit
import Combine
import OSLog
import SwiftUI
import TesseraCore

@MainActor
final class ZoneSelectionModel: ObservableObject {
    @Published private(set) var state: DirectNavigationState
    var navigation: GridNavigation { state.navigation }
    var layout: LayoutPreset { navigation.layout }
    var zoneCount: Int { layout.zones.count }
    @Published var status = L10n.text("Use arrow keys to move the window.")

    init(navigation: GridNavigation) { self.state = DirectNavigationState(navigation: navigation) }
    init(state: DirectNavigationState) { self.state = state }
    func record(actualFrame: CGRect) { state.record(actualFrame: actualFrame) }

    func placement(forZone number: Int) -> GridPlacement? {
        guard (1...zoneCount).contains(number) else { return nil }
        return GridPlacement(layout: layout, target: .zone(number))
    }

    func move(_ direction: GridDirection, isRepeat: Bool = false) -> GridPlacement? {
        // A vertical press advances one step through top, full, and bottom.
        // Holding Left/Right still traverses columns continuously.
        if isRepeat && (direction == .up || direction == .down) { return nil }
        var next = state
        guard let target = next.move(direction) else { return nil }
        state = next
        status = L10n.format("Arranging %@…", target.label)
        return target
    }
}

extension GridPlacement {
    var label: String { localizedLabel() }

    func localizedLabel(language: AppLanguage? = nil) -> String {
        L10n.format("%@ · %@", layout.title, target.localizedLabel(language: language), language: language)
    }
}

extension PlacementTarget {
    var label: String { localizedLabel() }

    func localizedLabel(language: AppLanguage? = nil) -> String {
        switch self {
        case .zone(let id): L10n.format("Zone %d", id, language: language)
        case .column(let index): L10n.format("Column %d · full height", index, language: language)
        }
    }
}

@MainActor
private final class ZonePanel: NSPanel {
    private let log = Logger(subsystem: "io.github.jgoneit.tessera", category: "selector")
    var onSelect: ((Int) -> Void)?
    var onMove: ((GridDirection, Bool) -> Void)?
    var onFinish: (() -> Void)?
    var onCancel: (() -> Void)?
    var isRegisteredShortcut: ((Shortcut) -> Bool)?
    var zoneCount: () -> Int = { 0 }
    static func isSelectionKey(_ keyCode: UInt16) -> Bool {
        [53, 36, 76, 123, 124, 125, 126, 18, 19, 20, 21, 23, 22, 26, 28,
         25, 29, 83, 84, 85, 86, 87, 88, 89, 91, 92, 82].contains(keyCode)
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            // Registered combinations are delivered by Carbon, including when
            // the nonactivating panel is key. Consume any duplicate local route.
            if isRegisteredShortcut?(Shortcut(event: event)) == true { return }
            if Self.isSelectionKey(event.keyCode) {
                log.notice("Panel selection key: code=\(event.keyCode) repeat=\(event.isARepeat)")
            }
            switch event.keyCode {
            case 53, 36, 76:
                if !event.isARepeat { onFinish?() }
                return
            case 123: onMove?(.left, event.isARepeat); return
            case 124: onMove?(.right, event.isARepeat); return
            case 125: onMove?(.down, event.isARepeat); return
            case 126: onMove?(.up, event.isARepeat); return
            default: break
            }
            let numbers: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8,
                25: 9, 29: 0, 83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8, 92: 9, 82: 0]
            if let number = numbers[event.keyCode] {
                if number > 0 && number <= zoneCount() && !event.isARepeat { onSelect?(number) }
                return
            }
        }
        super.sendEvent(event)
    }

    override func resignKey() {
        super.resignKey()
        if isVisible {
            log.notice("Selector cancellation: resignKey")
            onCancel?()
        }
    }
}

@MainActor
final class OverlayController {
    private let log = Logger(subsystem: "io.github.jgoneit.tessera", category: "selector")
    private var panel: ZonePanel?
    private var model: ZoneSelectionModel?
    private var feedback: NSPanel?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var keyMonitor: Any?
    private var onOutsideClick: (() -> Void)?
    private var feedbackTask: Task<Void, Never>?

    func show(model: ZoneSelectionModel, screen: NSScreen, appName: String,
              isRegisteredShortcut: @escaping (Shortcut) -> Bool,
              onSelect: @escaping (GridPlacement, Bool) -> Void,
              onFinish: @escaping () -> Void, onCancel: @escaping () -> Void) {
        dismiss()
        clearFeedback()
        let available = screen.visibleFrame
        let previewScale = min(620.0 / available.width, 0.60,
            max(0.1, (available.height - 180) / available.height))
        let gridWidth = available.width * previewScale
        let gridHeight = available.height * previewScale
        let width = gridWidth + 40
        let height = gridHeight + 154
        let frame = CGRect(x: available.midX - width / 2, y: available.midY - height / 2, width: width, height: height)
        let window = ZonePanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = L10n.text("Tessera Zone Selector")
        window.isFloatingPanel = true
        window.becomesKeyOnlyIfNeeded = false
        window.hidesOnDeactivate = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.zoneCount = { [weak model] in model?.zoneCount ?? 0 }
        self.model = model
        window.isRegisteredShortcut = isRegisteredShortcut
        window.onSelect = { number in
            if let placement = model.placement(forZone: number) { onSelect(placement, true) }
        }
        window.onMove = { [weak self] direction, isRepeat in
            if let target = model.move(direction, isRepeat: isRepeat) { onSelect(target, false) }
            else if let self {
                self.log.notice("Selection unchanged: repeat=\(isRepeat) target=\(model.navigation.selectedPlacement.label, privacy: .public)")
            }
        }
        window.onFinish = onFinish
        window.onCancel = onCancel
        let hosting = NSHostingView(rootView: ZoneSelectorView(model: model,
            appName: appName, displayName: screen.localizedName,
            gridSize: CGSize(width: gridWidth, height: gridHeight),
            onSelect: { onSelect($0, true) }))
        window.contentView = hosting
        let measuredHeight = ceil(hosting.fittingSize.height)
        window.setFrame(CGRect(x: available.midX - width / 2, y: available.midY - measuredHeight / 2,
            width: width, height: measuredHeight), display: false)
        panel = window
        onOutsideClick = onCancel
        // Observe only selector control keys while this panel is open. Never
        // record typed characters or keys delivered outside the selector session.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
            guard let self, let window, self.panel === window, window.isVisible,
                  ZonePanel.isSelectionKey(event.keyCode) else { return event }
            self.log.notice("Local selection key: code=\(event.keyCode) repeat=\(event.isARepeat) modifiers=\(event.modifierFlags.rawValue) eventWindow=\(event.windowNumber) keyWindow=\(NSApp.keyWindow?.windowNumber ?? -1) panelWindow=\(window.windowNumber) panelKey=\(window.isKeyWindow) appActive=\(NSApp.isActive)")
            return event
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self, weak window] event in
            if let self, let window, self.panel === window, event.window !== window {
                self.log.notice("Selector cancellation: localOutsideClick")
                self.onOutsideClick?()
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self, weak window] _ in
            Task { @MainActor in
                guard let self, let window, self.panel === window else { return }
                self.log.notice("Selector cancellation: globalOutsideClick")
                self.onOutsideClick?()
            }
        }
        window.makeKeyAndOrderFront(nil)
        log.notice("Zone selector presented: visible=\(window.isVisible) key=\(window.isKeyWindow)")
    }

    func updateStatus(_ message: String) { model?.status = message }

    /// Hides keyboard UI while keeping outside-click cancellation active during drain.
    func hideForFinish() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel?.onCancel = nil
        panel?.onFinish = nil
        panel?.onMove = nil
        panel?.onSelect = nil
        panel?.zoneCount = { 0 }
        panel?.isRegisteredShortcut = nil
        panel?.orderOut(nil)
    }

    func dismiss() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        onOutsideClick = nil
        hideForFinish()
        panel = nil
        model = nil
    }

    func showFeedback(_ message: String, screen: NSScreen, duration: Duration = .seconds(4)) {
        clearFeedback()
        let width = min(420.0, screen.visibleFrame.width - 32)
        let view = PlacementFeedbackView(message: message, width: width)
        let hosting = NSHostingView(rootView: view)
        let height = max(50, ceil(hosting.fittingSize.height))
        let frame = CGRect(x: screen.visibleFrame.midX - width / 2, y: screen.visibleFrame.maxY - height - 32,
            width: width, height: height)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = L10n.text("Tessera Status")
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.contentView = hosting
        panel.orderFrontRegardless()
        feedback = panel
        feedbackTask = Task { [weak self] in
            do { try await Task.sleep(for: duration) } catch { return }
            self?.clearFeedback()
        }
    }

    private func clearFeedback() {
        feedbackTask?.cancel()
        feedbackTask = nil
        feedback?.orderOut(nil)
        feedback = nil
    }
}

struct ZoneSelectorView: View {
    @ObservedObject var model: ZoneSelectionModel
    @Environment(\.colorSchemeContrast) private var contrast
    private var layout: LayoutPreset { model.layout }
    let appName: String
    let displayName: String
    let gridSize: CGSize
    let language: AppLanguage?
    let onSelect: (GridPlacement) -> Void

    init(model: ZoneSelectionModel, appName: String, displayName: String,
         gridSize: CGSize, language: AppLanguage? = nil, onSelect: @escaping (GridPlacement) -> Void) {
        self.model = model
        self.appName = appName
        self.displayName = displayName
        self.gridSize = gridSize
        self.language = language
        self.onSelect = onSelect
    }

    var body: some View {
        // Every button carries the layout that produced its visible number.
        // Queued navigation cannot reinterpret an already displayed zone.
        let displayedLayout = layout
        let selectedTarget = model.navigation.selectedTarget
        let highlightedZones = model.navigation.highlightedZoneIDs
        let isFullHeight: Bool = if case .column = selectedTarget { true } else { false }
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(appName).font(.headline).lineLimit(1)
                    Label(displayName, systemImage: "display")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        .accessibilityLabel(L10n.format("Display: %@", displayName, language: language))
                }
                Spacer(minLength: 8)
                Text(displayedLayout.title)
                    .font(.callout.weight(.semibold)).monospacedDigit()
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                    .overlay(Capsule().strokeBorder(TesseraDesign.border, lineWidth: 1))
                    .accessibilityLabel(L10n.format("Layout: %@", displayedLayout.title, language: language))
            }
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(0..<displayedLayout.rows, id: \.self) { row in
                    GridRow {
                        ForEach(0..<displayedLayout.columns, id: \.self) { column in
                            let number = row * displayedLayout.columns + column + 1
                            ZoneButton(number: number,
                                selected: highlightedZones.contains(number),
                                partOfFullColumn: isFullHeight,
                                language: language,
                                onSelect: { onSelect(GridPlacement(layout: displayedLayout, target: .zone($0))) })
                        }
                    }
                }
            }
            .frame(width: gridSize.width, height: gridSize.height)
            .overlay {
                if case .column(let index) = selectedTarget {
                    let width = (gridSize.width - CGFloat(displayedLayout.columns - 1) * 6) / CGFloat(displayedLayout.columns)
                    RoundedRectangle(cornerRadius: 11)
                        .strokeBorder(contrast == .increased ? Color.primary : Color.accentColor,
                            lineWidth: contrast == .increased ? 3 : 2)
                        .frame(width: width, height: gridSize.height)
                        .frame(width: gridSize.width, alignment: .leading)
                        .offset(x: CGFloat(index - 1) * (width + 6))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(model.navigation.selectedPlacement.localizedLabel(language: language))
                        .font(.callout.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    Label(L10n.text(isFullHeight ? "Full height" : "Single zone", language: language),
                        systemImage: isFullHeight ? "arrow.up.and.down" : "square")
                        .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(model.status).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).frame(height: 28, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(spacing: 4) {
                HStack(spacing: 12) {
                    keyboardHint("← →", text: L10n.text("Columns", language: language))
                    keyboardHint("↑ ↓", text: L10n.text("Height", language: language))
                    Spacer(minLength: 0)
                    keyboardHint("↵ esc", text: L10n.text("Keep placement", language: language))
                }
                Text(L10n.format("1–%d or click a zone to place and close", displayedLayout.zones.count, language: language))
                    .font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .modifier(OverlaySurface())
    }

    private func keyboardHint(_ keys: String, text: String) -> some View {
        HStack(spacing: 5) {
            TesseraKeycap(keys)
            Text(text).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

struct PlacementFeedbackView: View {
    let message: String
    let width: CGFloat
    let language: AppLanguage?

    init(message: String, width: CGFloat, language: AppLanguage? = nil) {
        self.message = message
        self.width = width
        self.language = language
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            Text(message).font(.callout).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(width: width)
        .modifier(OverlaySurface())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.text("Arrangement status", language: language))
        .accessibilityValue(message)
    }
}

/// Use native material unless the user requests opaque surfaces. The outline
/// remains visible in both appearances and gains weight with increased contrast.
private struct OverlaySurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: TesseraDesign.radius, style: .continuous)
        content
            .background {
                if reduceTransparency || contrast == .increased {
                    shape.fill(TesseraDesign.canvas)
                } else {
                    shape.fill(.regularMaterial)
                }
            }
            .overlay(shape.strokeBorder(
                contrast == .increased ? Color.primary.opacity(0.55) : TesseraDesign.border,
                lineWidth: contrast == .increased ? 1.5 : 1))
            .transaction { if reduceMotion { $0.animation = nil } }
    }
}

// The deployment-compatible wrapper also works with CLT SDKs missing State macro plugins.
private typealias ViewState<Value> = SwiftUI.State<Value>

private struct ZoneButton: View {
    let number: Int
    let selected: Bool
    let partOfFullColumn: Bool
    let language: AppLanguage?
    let onSelect: (Int) -> Void
    @ViewState private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Button { onSelect(number) } label: {
            Text(String(number))
                .font(.system(size: 26, weight: selected ? .semibold : .medium, design: .rounded))
                .monospacedDigit().foregroundStyle(.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    ZStack {
                        shape.fill(Color(nsColor: .controlBackgroundColor))
                        shape.fill(Color.accentColor.opacity(selected ? (hovered ? 0.20 : 0.14) : (hovered ? 0.08 : 0)))
                    }
                }
                .overlay(shape.strokeBorder(borderColor, lineWidth: borderWidth))
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(contrast == .increased ? Color.primary : Color.accentColor)
                            .padding(9)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
        .accessibilityLabel(L10n.format("Zone %d", number, language: language))
        .accessibilityValue(L10n.text(selected ? "Selected" : "Not selected", language: language))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(L10n.text("Move the selected window to this zone and close the selector", language: language))
    }

    private var borderColor: Color {
        if selected && !partOfFullColumn { return contrast == .increased ? Color.primary : Color.accentColor }
        return contrast == .increased ? Color.primary.opacity(0.55) : TesseraDesign.border
    }

    private var borderWidth: CGFloat {
        if selected { return partOfFullColumn ? 1 : (contrast == .increased ? 3 : 2) }
        return contrast == .increased ? 1.5 : 1
    }
}
