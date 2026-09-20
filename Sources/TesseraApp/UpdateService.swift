import Combine
import Foundation
import Sparkle

enum UpdateState: Equatable {
    case idle
    case checking
    case available(String)
    case upToDate
    case failed(String)
}

enum UpdateBackendEvent {
    case propertiesChanged
    case checking
    case available(String)
    case upToDate
    case failed(String)
    case presentationChanged(Bool)
    case finished
    case willInstall
}

@MainActor
protocol UpdateBackend: AnyObject {
    var onEvent: ((UpdateBackendEvent) -> Void)? { get set }
    var canCheck: Bool { get }
    var automaticChecksEnabled: Bool { get set }
    var lastCheckDate: Date? { get }
    func start() throws
    func checkForUpdates()
}

/// The app consumes this small observable model instead of depending on a
/// Sparkle controller. Construction is inert, including in offscreen previews.
@MainActor
final class UpdateService: ObservableObject {
    @Published private(set) var state: UpdateState = .idle
    @Published private(set) var canCheck = false
    @Published private(set) var lastCheckDate: Date?
    @Published var automaticChecksEnabled: Bool {
        didSet {
            guard !synchronizing, oldValue != automaticChecksEnabled else { return }
            backend.automaticChecksEnabled = automaticChecksEnabled
            synchronizeProperties()
        }
    }

    var onPresentationChanged: ((Bool) -> Void)?
    var onWillInstall: (() -> Void)?

    private let backend: any UpdateBackend
    private var started = false
    private var synchronizing = false
    private var presented = false

    convenience init(version: AppVersion = .current) {
        self.init(backend: SparkleUpdateBackend(version: version))
    }

    init(backend: any UpdateBackend) {
        self.backend = backend
        automaticChecksEnabled = backend.automaticChecksEnabled
        lastCheckDate = backend.lastCheckDate
        backend.onEvent = { [weak self] event in self?.receive(event) }
    }

    func start() {
        guard !started else { return }
        do {
            try backend.start()
            started = true
            synchronizeProperties()
        } catch {
            state = .failed(error.localizedDescription)
            canCheck = false
        }
    }

    func checkForUpdates() {
        guard started, canCheck, state != .checking else { return }
        // A gentle reminder is already an active Sparkle session. Calling the
        // same API presents that update; starting another session would lose it.
        if case .available = state {} else { state = .checking }
        setPresented(true)
        backend.checkForUpdates()
        synchronizeProperties()
    }

    private func receive(_ event: UpdateBackendEvent) {
        switch event {
        case .propertiesChanged: break
        case .checking: state = .checking
        case let .available(version): state = .available(version)
        case .upToDate: state = .upToDate
        case let .failed(message): state = .failed(message)
        case let .presentationChanged(value): setPresented(value)
        case .finished:
            if case .available = state { state = .idle }
            if state == .checking { state = .idle }
            setPresented(false)
        case .willInstall: onWillInstall?()
        }
        synchronizeProperties()
    }

    private func setPresented(_ value: Bool) {
        guard presented != value else { return }
        presented = value
        onPresentationChanged?(value)
    }

    private func synchronizeProperties() {
        synchronizing = true
        canCheck = started && backend.canCheck
        automaticChecksEnabled = backend.automaticChecksEnabled
        lastCheckDate = backend.lastCheckDate
        synchronizing = false
    }
}

@MainActor
final class SparkleUpdateBackend: NSObject, UpdateBackend, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    var onEvent: ((UpdateBackendEvent) -> Void)?
    private let version: AppVersion
    private let versionDisplayer: ReleaseVersionDisplayer
    private var controller: SPUStandardUpdaterController?
    private var observations: [NSKeyValueObservation] = []

    init(version: AppVersion) {
        self.version = version
        versionDisplayer = ReleaseVersionDisplayer(version: version)
    }

    var canCheck: Bool { controller?.updater.canCheckForUpdates ?? false }
    var automaticChecksEnabled: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? true }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }
    var lastCheckDate: Date? { controller?.updater.lastUpdateCheckDate }

    func start() throws {
        guard controller == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        do {
            try controller.updater.start()
        } catch {
            self.controller = nil
            throw error
        }
        let updater = controller.updater
        // Info.plist supplies the daily interval and forbids automatic
        // downloads. Do not reset Sparkle's persisted scheduler at launch.
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.onEvent?(.propertiesChanged) }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.onEvent?(.propertiesChanged) }
            },
            updater.observe(\.lastUpdateCheckDate, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.onEvent?(.propertiesChanged) }
            },
        ]
    }

    func checkForUpdates() { controller?.checkForUpdates(nil) }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> { version.allowedChannels }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        onEvent?(.checking)
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        onEvent?(.available(item.displayVersionString))
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        report(error)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        report(error)
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if let error { report(error) }
        onEvent?(.finished)
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        onEvent?(.willInstall)
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // Even immediately after launch, scheduled updates only change the
        // menu/settings indicator. User-initiated checks bypass this callback.
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        onEvent?(.available(update.displayVersionString))
        if handleShowingUpdate { onEvent?(.presentationChanged(true)) }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        onEvent?(.presentationChanged(true))
    }

    func standardUserDriverWillShowModalAlert() { onEvent?(.presentationChanged(true)) }

    func standardUserDriverDidShowModalAlert() { onEvent?(.presentationChanged(false)) }

    func standardUserDriverWillFinishUpdateSession() { onEvent?(.finished) }

    func standardUserDriverRequestsVersionDisplayer() -> (any SUVersionDisplay)? { versionDisplayer }

    private func report(_ error: Error) {
        let error = error as NSError
        if error.domain == SUSparkleErrorDomain, error.code == SUError.noUpdateError.rawValue {
            let reason = (error.userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)?.int32Value
            if reason == nil || reason == SPUNoUpdateFoundReason.onLatestVersion.rawValue
                || reason == SPUNoUpdateFoundReason.onNewerThanLatestVersion.rawValue {
                onEvent?(.upToDate)
            } else {
                onEvent?(.failed(error.localizedDescription))
            }
        } else if error.domain == SUSparkleErrorDomain, error.code == SUError.installationCanceledError.rawValue {
            // User cancellation is not an update failure.
        } else if error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled {
            // Cancellation while downloading leaves the existing app intact.
        } else {
            onEvent?(.failed(error.localizedDescription))
        }
    }
}
