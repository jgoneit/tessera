import AppKit
@preconcurrency import ApplicationServices
import Combine
import OSLog
import SwiftUI
import TesseraCore

@MainActor
final class AppCoordinator: NSObject, ObservableObject, NSMenuDelegate, NSWindowDelegate {
    let preferences: Preferences
    let shortcutRecorder = ShortcutRecordingBridge()
    @Published private(set) var permissionGranted = false
    @Published private(set) var statusMessage: String
    @Published private(set) var shortcutError: String?
    @Published private(set) var shortcutsActive = false
    @Published private(set) var isWorking = false

    private let windows = WindowSystem()
    private let shortcuts = GlobalShortcuts()
    private let overlay = OverlayController()
    private let log = Logger(subsystem: "io.github.jgoneit.tessera", category: "arrangement")
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var preferenceObservers: Set<AnyCancellable> = []
    private var directMouseMonitors: [Any] = []
    private var directMonitorID: UUID?
    private var requestID = UUID()
    private var capturingPID: pid_t?
    private var selectorCapture: Task<Void, Never>?
    private var deferredActions: [PlacementAction] = []
    private var recordingShortcut = false
    private var session: SelectionSession?
    private var placementQueue: PlacementQueue?
    private var selectorIsOpen = false
    private var menuCapture: MenuCapture?
    private var directMenuCapture: MenuCapture?
    private var stopping = false
    private lazy var placementInput = BufferedPlacementInput(
        prepare: { [weak self] in await self?.preparePlacementBatch() },
        onIdle: { [weak self] in self?.updateBusyState() })

    init(preferences: Preferences = Preferences()) {
        self.preferences = preferences
        self.statusMessage = L10n.text("Use a directional shortcut to arrange your active window.",
            language: preferences.language)
        super.init()
    }

    private enum Mode { case direct, selector }
    @MainActor private final class SelectionSession {
        let id = UUID()
        let target: WindowTarget
        let display: DisplayGeometry
        let primaryTop: CGFloat
        let layouts: [LayoutPreset]
        let gap: Int
        let appName: String
        let mode: Mode
        let model: ZoneSelectionModel
        var latestRequested: GridPlacement?

        init(target: WindowTarget, display: DisplayGeometry, primaryTop: CGFloat,
             layouts: [LayoutPreset], gap: Int, appName: String, mode: Mode) {
            self.target = target
            self.display = display
            self.primaryTop = primaryTop
            self.layouts = layouts
            self.gap = gap
            self.appName = appName
            self.mode = mode
            var state = DirectNavigationState(layouts: layouts,
                windowFrame: CoordinateSpace.flip(target.frame, primaryTop: primaryTop),
                visibleFrame: display.visibleFrame, gap: CGFloat(gap), scale: display.scale)
            state.record(actualFrame: target.frame)
            model = ZoneSelectionModel(state: state)
        }
    }

    private struct MenuCapture {
        let id: UUID
        let pid: pid_t
        let appName: String
        let task: Task<WindowTarget, Error>
    }

    func start() {
        NSApp.applicationIconImage = AppIcon.image
        applyAppearance(preferences.theme)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "Tessera"
        item.button?.image = AppIcon.menuImage
        item.button?.title = ""
        item.button?.imagePosition = .imageOnly
        item.button?.setAccessibilityLabel("Tessera")
        item.button?.toolTip = L10n.text("Tessera — Arrange your active window")
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu
        statusItem = item
        // @Published sends synchronously before assigning. Invalidate captured
        // work before a new grid set or gap can be used by any pending write.
        preferences.$enabledLayouts.dropFirst().sink { [weak self] _ in
            self?.cancelSelection(reason: "enabled grids changed")
            self?.discardMenuCapture()
        }.store(in: &preferenceObservers)
        preferences.$gap.dropFirst().sink { [weak self] _ in
            self?.cancelSelection(reason: "gap changed")
            self?.discardMenuCapture()
        }.store(in: &preferenceObservers)
        preferences.$theme.dropFirst().sink { [weak self] theme in
            self?.shortcutRecorder.cancelRecording()
            self?.applyAppearance(theme)
        }.store(in: &preferenceObservers)
        preferences.$language.dropFirst().sink { [weak self] _ in
            self?.shortcutRecorder.cancelRecording()
            // @Published fires before persistence. Render on the next main-actor
            // turn so AppKit and SwiftUI resolve the same saved language.
            Task { @MainActor [weak self] in self?.refreshLocalizedPresentation() }
        }.store(in: &preferenceObservers)
        shortcuts.onTrigger = { [weak self] in self?.handleAction($0) }
        shortcuts.onRecord = { [weak self] in self?.shortcutRecorder.receiveRegistered($0) }
        shortcuts.onError = { [weak self] message in
            self?.shortcutError = message
        }
        shortcutRecorder.onRecordingChanged = { [weak self] recording in
            guard let self else { return }
            self.recordingShortcut = recording
            if recording { self.cancelSelection(reason: "shortcut recording") }
            self.shortcuts.setRecording(recording)
        }
        refreshPermission()
        registerSavedShortcuts()
        rebuildMenu(menu)
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.refreshPermission() } })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.cancelSelection(reason: "display changed")
                self?.statusMessage = L10n.text("Displays changed. The next shortcut uses the current window and display.")
            }
        })
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { [weak self] notification in
            let pid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            Task { @MainActor in
                guard let self, let pid,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                if let expected = self.session?.target.pid ?? self.capturingPID, expected != pid {
                    self.cancelSelection(reason: "another app activated")
                }
            }
        })
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.cancelSelection(reason: "session inactive") }
            })
        }
        if !permissionGranted || !shortcutsActive || shortcutError != nil { showSettings() }
    }

    func stop() {
        stopping = true
        cancelSelection(reason: "quit")
        discardMenuCapture()
        shortcuts.unregister()
        observers.forEach(NotificationCenter.default.removeObserver)
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        preferenceObservers.removeAll()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }

    func menuWillOpen(_ menu: NSMenu) {
        if session?.mode == .direct || placementInput.isPreparing { cancelSelection(reason: "menu opened") }
        refreshPermission()
        rebuildMenu(menu)
        discardMenuCapture()
        guard permissionGranted, !isWorking, let app = externalFrontmostApplication() else { return }
        let pid = app.processIdentifier
        menuCapture = MenuCapture(id: UUID(), pid: pid, appName: app.localizedName ?? L10n.text("Window"),
            task: Task { try await windows.capture(pid: pid) })
    }

    func menuDidClose(_ menu: NSMenu) {
        guard let id = menuCapture?.id else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, self.menuCapture?.id == id else { return }
            self.discardMenuCapture()
        }
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let title = NSMenuItem(title: "Tessera", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        let layoutMenu = NSMenu()
        for layout in LayoutPreset.allCases {
            let item = NSMenuItem(title: layout.title, action: #selector(selectLayout(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = layout.rawValue
            let enabled = preferences.enabledLayouts.contains(layout)
            item.state = enabled ? .on : .off
            item.isEnabled = !enabled || preferences.enabledLayouts.count > 1
            layoutMenu.addItem(item)
        }
        let layout = NSMenuItem(title: L10n.text("Layout"), action: nil, keyEquivalent: "")
        layout.submenu = layoutMenu
        menu.addItem(layout)
        menu.addItem(.separator())
        let arrange = NSMenuItem(title: L10n.text("Arrange Window…"), action: #selector(arrangeFromMenu), keyEquivalent: "")
        arrange.target = self
        arrange.isEnabled = !isWorking
        menu.addItem(arrange)
        let maximizeTitle = preferences.directionalShortcuts.maximize.map {
            L10n.format("%@: %@", L10n.text("Maximize"), $0.displayString)
        } ?? L10n.text("Maximize")
        let maximize = NSMenuItem(title: maximizeTitle, action: #selector(maximizeFromMenu), keyEquivalent: "")
        maximize.target = self
        maximize.isEnabled = !isWorking
        menu.addItem(maximize)
        for (name, direction) in [("Left", GridDirection.left), ("Right", .right), ("Up", .up), ("Down", .down)] {
            let item = NSMenuItem(title: L10n.format("%@: %@", L10n.text(name), preferences.directionalShortcuts[direction].displayString), action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        let message = permissionGranted ? (shortcutError ?? statusMessage) : L10n.text("Accessibility permission required")
        let status = NSMenuItem(title: String(message.prefix(90)), action: nil, keyEquivalent: "")
        status.toolTip = message
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: L10n.text("Settings…"), action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: L10n.text("Quit Tessera"), action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func selectLayout(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let layout = LayoutPreset(rawValue: raw) else { return }
        preferences.setLayout(layout, enabled: !preferences.enabledLayouts.contains(layout))
    }
    @objc private func openSettingsFromMenu() { showSettings() }
    @objc private func quitApp() { NSApp.terminate(nil) }
    @objc private func arrangeFromMenu() {
        let capture = menuCapture
        menuCapture = nil
        if let capture { beginSelector(pid: capture.pid, appName: capture.appName, captured: capture.task) }
        else if let app = externalFrontmostApplication() {
            beginSelector(pid: app.processIdentifier, appName: app.localizedName ?? L10n.text("Window"))
        } else { showFeedback(L10n.text("Select another app's window first.")) }
    }

    @objc private func maximizeFromMenu() {
        let capture = menuCapture
        menuCapture = nil
        cancelSelection(reason: "maximize from menu")
        directMenuCapture = capture
        handleAction(.maximize)
    }

    private func externalFrontmostApplication() -> NSRunningApplication? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return app
    }

    private func handleAction(_ action: PlacementAction) {
        guard !recordingShortcut, !stopping else { return }
        if action == .maximize { overlay.cancelDirectionalRepeat() }
        refreshPermission()
        guard permissionGranted else { cancelSelection(reason: "permission required"); showSettings(); return }
        if let selection = session, selection.mode == .selector {
            if selectorIsOpen { apply(action, in: selection) }
            else { deferredActions.append(action) }
            return
        }
        if selectorCapture != nil { deferredActions.append(action); return }
        isWorking = true
        watchDirectClicks()
        placementInput.submit(action)
    }

    private func preparePlacementBatch() async -> BufferedPlacementInput.Apply? {
        let generation = requestID
        guard let app = externalFrontmostApplication() else {
            cancelSelection(reason: "no active window")
            showFeedback(L10n.text("Select another app's window first."))
            return nil
        }
        let pid = app.processIdentifier
        capturingPID = pid
        defer { if requestID == generation { capturingPID = nil } }
        let previous = session
        let wasBusy = placementQueue?.isBusy == true
        var resolved: WindowTarget?
        do {
            let captured = directMenuCapture
            directMenuCapture = nil
            let target: WindowTarget
            if let captured { target = try await captured.task.value }
            else { target = try await windows.resolveFocusedTarget(pid: pid, reusing: previous?.target) }
            resolved = target
            try Task.checkCancellation()
            guard requestID == generation, target.pid == pid,
                  externalFrontmostApplication()?.processIdentifier == pid else {
                throw WindowSystemError.targetChanged
            }
            let screens = ScreenCatalog.snapshot()
            let frame = CoordinateSpace.flip(target.frame, primaryTop: screens.primaryTop)
            guard let display = DisplaySelection.bestDisplay(for: frame, in: screens.displays) else {
                throw WindowSystemError.invalidGeometry
            }
            let selection: SelectionSession
            if let previous, session === previous, previous.mode == .direct,
               previous.target.token == target.token, previous.display == display,
               previous.primaryTop == screens.primaryTop, previous.layouts == preferences.enabledLayouts,
               previous.gap == preferences.gap,
               wasBusy || previous.model.state.matchesLastConfirmed(target.frame) {
                selection = previous
            } else {
                if previous != nil { shortcuts.cancelInput() }
                selection = SelectionSession(target: target, display: display, primaryTop: screens.primaryTop,
                    layouts: preferences.enabledLayouts, gap: preferences.gap, appName: app.localizedName ?? L10n.text("Window"), mode: .direct)
                install(selection)
            }
            return { [weak self, weak selection] action in
                guard let self, let selection, self.session === selection else { return }
                self.apply(action, in: selection)
            }
        } catch {
            if let resolved, resolved.token != session?.target.token { await windows.discard(target: resolved) }
            guard requestID == generation else { return nil }
            cancelSelection(reason: "target resolution failed")
            if !(error is CancellationError) { showFeedback(UserFacingError.message(error)) }
            refreshPermission()
            return nil
        }
    }

    private func beginSelector(pid: pid_t, appName: String, captured: Task<WindowTarget, Error>? = nil) {
        cancelSelection(reason: "open selector")
        refreshPermission()
        guard permissionGranted else {
            if let captured { Task { if let target = try? await captured.value { await windows.discard(target: target) } } }
            showSettings()
            return
        }
        let generation = requestID
        capturingPID = pid
        isWorking = true
        selectorCapture = Task { [weak self] in
            guard let self else { return }
            var resolved: WindowTarget?
            do {
                let target: WindowTarget
                if let captured { target = try await captured.value }
                else { target = try await windows.capture(pid: pid) }
                resolved = target
                try Task.checkCancellation()
                guard requestID == generation, externalFrontmostApplication()?.processIdentifier == pid else {
                    throw WindowSystemError.targetChanged
                }
                let screens = ScreenCatalog.snapshot()
                let frame = CoordinateSpace.flip(target.frame, primaryTop: screens.primaryTop)
                guard let display = DisplaySelection.bestDisplay(for: frame, in: screens.displays),
                      let screen = ScreenCatalog.screen(id: display.id) else { throw WindowSystemError.invalidGeometry }
                let selection = SelectionSession(target: target, display: display, primaryTop: screens.primaryTop,
                    layouts: preferences.enabledLayouts, gap: preferences.gap, appName: appName, mode: .selector)
                install(selection)
                selectorIsOpen = true
                selectorCapture = nil
                capturingPID = nil
                overlay.show(model: selection.model, screen: screen, appName: appName,
                    isRegisteredShortcut: { [weak self] in self?.shortcuts.contains($0) == true },
                    maximizeShortcut: preferences.directionalShortcuts.maximize?.displayString,
                    onMaximize: { [weak self] in
                        guard let self, self.session === selection else { return }
                        self.shortcuts.cancelInput()
                        self.overlay.cancelDirectionalRepeat()
                        self.apply(.maximize, in: selection)
                    },
                    onSelect: { [weak self] target, closes in self?.select(target, close: closes, selection: selection) },
                    onFinish: { [weak self] in self?.finishSelection(selection) },
                    onCancel: { [weak self] in
                        guard let self, self.session === selection else { return }
                        self.cancelSelection(reason: "selector dismissed")
                    })
                let buffered = deferredActions
                deferredActions.removeAll()
                buffered.forEach { apply($0, in: selection) }
            } catch {
                if let resolved { await windows.discard(target: resolved) }
                guard requestID == generation else { return }
                selectorCapture = nil
                capturingPID = nil
                deferredActions.removeAll()
                isWorking = false
                shortcuts.cancelInput()
                if !(error is CancellationError) { showFeedback(UserFacingError.message(error)) }
            }
        }
    }

    private func install(_ selection: SelectionSession) {
        let previousQueue = placementQueue
        // Transfer ownership before cancellation cleanup when a manual resize
        // starts new navigation on the same retained AX window token.
        session = selection
        placementQueue = PlacementQueue(
            operation: { [weak self] destination in
                guard let self else {
                    return PlacementResult(outcome: .unavailable, message: L10n.text("Arrangement ended."), actualFrame: nil)
                }
                return await self.performPlacement(destination, selection: selection)
            },
            onResult: { [weak self] destination, result in
                self?.receivedPlacement(result, destination: destination, selection: selection)
            },
            onFinished: { [weak self] in self?.releaseSelection(selection) },
            onIdle: { [weak self] in self?.updateBusyState() })
        previousQueue?.cancel()
    }

    private func apply(_ action: PlacementAction, in selection: SelectionSession) {
        guard session === selection else { return }
        let target: GridPlacement?
        switch action {
        case .direction(let direction): target = selection.model.move(direction)
        case .maximize: target = selection.model.maximize()
        }
        if let target { select(target, close: false, selection: selection) }
    }

    private func select(_ destination: GridPlacement, close: Bool, selection: SelectionSession) {
        guard session === selection, let placementQueue,
              selection.mode == .direct || selectorIsOpen else { return }
        log.notice("Placement requested: \(destination.label, privacy: .public)")
        selection.latestRequested = destination
        statusMessage = L10n.format("Arranging %@…", destination.label)
        selection.model.status = statusMessage
        isWorking = true
        placementQueue.submit(destination)
        if close { finishSelection(selection) }
    }

    private func finishSelection(_ selection: SelectionSession) {
        guard session === selection, selectorIsOpen else { return }
        selectorIsOpen = false
        shortcuts.cancelInput()
        overlay.hideForFinish()
        if selection.latestRequested == nil { statusMessage = L10n.text("Selection closed. The window was not changed.") }
        placementQueue?.finish()
    }

    private func performPlacement(_ destination: GridPlacement, selection: SelectionSession) async -> PlacementResult {
        do {
            try Task.checkCancellation()
            guard session === selection, externalFrontmostApplication()?.processIdentifier == selection.target.pid else {
                throw WindowSystemError.targetChanged
            }
            let currentFrame = try await windows.currentFrame(of: selection.target)
            try Task.checkCancellation()
            guard session === selection, externalFrontmostApplication()?.processIdentifier == selection.target.pid else {
                throw WindowSystemError.targetChanged
            }
            let screens = ScreenCatalog.snapshot()
            let frame = CoordinateSpace.flip(currentFrame, primaryTop: screens.primaryTop)
            guard let display = DisplaySelection.bestDisplay(for: frame, in: screens.displays),
                  display == selection.display, screens.primaryTop == selection.primaryTop,
                  preferences.enabledLayouts == selection.layouts,
                  selection.layouts.contains(destination.layout), preferences.gap == selection.gap else {
                throw WindowSystemError.targetChanged
            }
            let desired = try GridGeometry.frame(in: display.visibleFrame, layout: destination.layout,
                target: destination.target, gap: CGFloat(selection.gap), scale: display.scale)
            try Task.checkCancellation()
            return await windows.place(target: selection.target,
                frame: CoordinateSpace.flip(desired, primaryTop: screens.primaryTop),
                visibleFrame: CoordinateSpace.flip(display.visibleFrame, primaryTop: screens.primaryTop))
        } catch {
            return PlacementResult(outcome: .unavailable,
                message: error is CancellationError ? L10n.text("Placement cancelled before resizing.") : UserFacingError.message(error),
                actualFrame: nil)
        }
    }

    private func receivedPlacement(_ result: PlacementResult, destination: GridPlacement, selection: SelectionSession) {
        log.notice("Placement result: \(destination.label, privacy: .public) — \(result.message, privacy: .public)")
        guard session === selection else {
            if result.outcome == .failed, !stopping { showFeedback(result.message, screenID: selection.display.id) }
            return
        }
        if let actual = result.actualFrame { selection.model.record(actualFrame: actual) }
        switch result.outcome {
        case .failed, .unavailable:
            let report = result.outcome == .failed || placementQueue?.isCancelled != true
            cancelSelection(reason: "placement failed")
            if report { showFeedback(result.message, screenID: selection.display.id) }
            refreshPermission()
        case .applied, .constrained:
            guard placementQueue?.isCancelled != true, selection.latestRequested == destination else { return }
            let message = result.outcome == .applied
                ? L10n.format("%@ → %@", selection.appName, destination.label)
                : L10n.format("%@ · %@", destination.label, result.message)
            statusMessage = message
            selection.model.status = message
            if !selectorIsOpen {
                showFeedback(message, screenID: selection.display.id,
                    duration: result.feedbackDuration)
            }
        }
    }

    private func releaseSelection(_ completed: SelectionSession) {
        let isCurrent = session === completed
        if isCurrent || session?.target.token != completed.target.token {
            Task { await windows.discard(target: completed.target) }
        }
        guard isCurrent else { return }
        placementQueue = nil
        session = nil
        selectorIsOpen = false
        overlay.dismiss()
        stopWatchingDirectClicks()
        let buffered = deferredActions
        deferredActions.removeAll()
        updateBusyState()
        buffered.forEach(handleAction)
    }

    private func updateBusyState() {
        isWorking = selectorIsOpen || selectorCapture != nil || placementInput.isPreparing || placementQueue?.isBusy == true
        if !isWorking, session == nil { stopWatchingDirectClicks() }
    }

    private func cancelSelection(reason: String = "new action") {
        requestID = UUID()
        placementInput.cancel()
        if let captured = directMenuCapture {
            directMenuCapture = nil
            Task { if let target = try? await captured.task.value { await windows.discard(target: target) } }
        }
        selectorCapture?.cancel()
        selectorCapture = nil
        capturingPID = nil
        deferredActions.removeAll()
        shortcuts.cancelInput()
        selectorIsOpen = false
        overlay.dismiss()
        stopWatchingDirectClicks()
        let previous = placementQueue
        session = nil
        placementQueue = nil
        previous?.cancel()
        isWorking = false
        log.notice("Arrangement cancelled: \(reason, privacy: .public)")
    }

    private func watchDirectClicks() {
        guard directMouseMonitors.isEmpty else { return }
        let monitorID = UUID()
        directMonitorID = monitorID
        let cancel: @MainActor () -> Void = { [weak self] in
            guard let self, self.directMonitorID == monitorID else { return }
            self.cancelSelection(reason: "outside click")
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { event in
            cancel()
            return event
        }) { directMouseMonitors.append(local) }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { _ in
            Task { @MainActor in cancel() }
        }) { directMouseMonitors.append(global) }
    }

    private func stopWatchingDirectClicks() {
        directMonitorID = nil
        directMouseMonitors.forEach(NSEvent.removeMonitor)
        directMouseMonitors.removeAll()
    }

    private func discardMenuCapture() {
        guard let old = menuCapture else { return }
        menuCapture = nil
        Task { if let target = try? await old.task.value { await windows.discard(target: target) } }
    }

    private func showFeedback(_ message: String, screenID: UInt32? = nil, duration: Duration = .seconds(4)) {
        statusMessage = message
        let screen = screenID.flatMap { ScreenCatalog.screen(id: $0) } ?? NSScreen.main ?? NSScreen.screens.first
        if let screen { overlay.showFeedback(message, screen: screen, duration: duration) }
    }

    func refreshPermission() { permissionGranted = WindowSystem.isTrusted() }
    func openAccessibilitySettings() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        refreshPermission()
    }

    func showSettings() {
        cancelSelection(reason: "settings opened")
        refreshPermission()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 800),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = L10n.text("Tessera Settings")
            window.contentMinSize = NSSize(width: 640, height: 620)
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.setFrameAutosaveName("TesseraSettings")
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.collectionBehavior = [.managed, .fullScreenPrimary]
            window.contentView = NSHostingView(rootView: SettingsView(coordinator: self, preferences: preferences))
            window.center()
            settingsWindow = window
        }
        // A real settings window participates in Mission Control and app switching.
        // Pickers and feedback never promote the menu-bar app to regular mode.
        NSApp.setActivationPolicy(.regular)
        if settingsWindow?.isMiniaturized == true { settingsWindow?.deminiaturize(nil) }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
        shortcutRecorder.cancelRecording()
        NSApp.setActivationPolicy(.accessory)
    }

    private func applyAppearance(_ theme: AppTheme) {
        switch theme {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func refreshLocalizedPresentation() {
        statusMessage = L10n.text("Use a directional shortcut to arrange your active window.")
        if shortcutError != nil {
            shortcutError = L10n.text("Apply shortcuts again to see the current status.")
        }
        settingsWindow?.title = L10n.text("Tessera Settings")
        statusItem?.button?.toolTip = L10n.text("Tessera — Arrange your active window")
        if let menu = statusItem?.menu { rebuildMenu(menu) }
    }

    private func registerSavedShortcuts() {
        shortcutError = nil
        let migrationNotice = preferences.shortcutMigrationNotice
        do {
            let registered = try shortcuts.registerAtStartup(preferences.directionalShortcuts,
                allowMaximizeFallback: preferences.maximizeMigrationPending)
            preferences.setDirectionalShortcuts(registered.bindings)
            shortcutError = registered.warning ?? migrationNotice
            shortcutsActive = true
        } catch { shortcutError = UserFacingError.message(error); shortcutsActive = false }
    }

    func applyShortcuts(_ bindings: DirectionalShortcuts) {
        cancelSelection(reason: "shortcuts changed")
        shortcutError = nil
        do {
            try shortcuts.register(bindings)
            preferences.setDirectionalShortcuts(bindings)
            shortcutsActive = true
            statusMessage = L10n.text("Window shortcuts applied.")
        } catch { shortcutError = UserFacingError.message(error) }
    }
}
