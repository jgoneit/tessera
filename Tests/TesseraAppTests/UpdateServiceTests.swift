import Foundation
import Sparkle
import Testing
@testable import TesseraApp

@Suite("Update service")
@MainActor
struct UpdateServiceTests {
    @Test("Construction is inert and repeated startup does not restart a scheduler")
    func lazyStartup() {
        let backend = FakeUpdateBackend()
        let service = UpdateService(backend: backend)
        #expect(backend.starts == 0)
        #expect(!service.canCheck)
        service.checkForUpdates()
        #expect(backend.checks == 0)
        service.start()
        service.start()
        #expect(backend.starts == 1)
        #expect(service.canCheck)
    }

    @Test("Only one manual request runs while the feed is loading")
    func coalescesChecks() {
        let backend = FakeUpdateBackend()
        let service = UpdateService(backend: backend)
        var presentations: [Bool] = []
        service.onPresentationChanged = { presentations.append($0) }
        service.start()
        service.checkForUpdates()
        service.checkForUpdates()
        #expect(backend.checks == 1)
        #expect(service.state == .checking)
        #expect(presentations == [true])
        backend.complete(.upToDate)
        #expect(service.state == .upToDate)
        #expect(service.canCheck)
        #expect(presentations == [true, false])
    }

    @Test("A scheduled reminder stays quiet and an explicit action opens its existing session")
    func gentleReminder() {
        let backend = FakeUpdateBackend()
        let service = UpdateService(backend: backend)
        var presentations: [Bool] = []
        service.onPresentationChanged = { presentations.append($0) }
        service.start()
        backend.onEvent?(.checking)
        backend.canCheck = true
        backend.onEvent?(.available("0.1.0-alpha.5"))
        #expect(service.canCheck)
        #expect(presentations.isEmpty)
        #expect(service.state == .available("0.1.0-alpha.5"))
        service.checkForUpdates()
        #expect(backend.checks == 1)
        #expect(presentations == [true])
        backend.complete(.finished)
        #expect(service.state == .idle)
        #expect(presentations == [true, false])
    }

    @Test("No update, network failure, and cancellation keep distinct final states")
    func completionStates() {
        let backend = FakeUpdateBackend()
        let service = UpdateService(backend: backend)
        service.start()
        service.checkForUpdates()
        backend.complete(.upToDate)
        #expect(service.state == .upToDate)
        service.checkForUpdates()
        backend.complete(.failed("offline"))
        #expect(service.state == .failed("offline"))
        service.checkForUpdates()
        backend.complete(.finished)
        #expect(service.state == .idle)
    }

    @Test("Scheduled failures never request app activation")
    func quietFailure() {
        let backend = FakeUpdateBackend()
        let service = UpdateService(backend: backend)
        var presentations: [Bool] = []
        service.onPresentationChanged = { presentations.append($0) }
        service.start()
        backend.onEvent?(.checking)
        backend.complete(.failed("offline"))
        #expect(presentations.isEmpty)
        #expect(service.state == .failed("offline"))
    }

    @Test("The backend owns automatic-check preferences and last check date across restart")
    func backendPersistence() {
        let storage = FakeUpdateStorage()
        let backend = FakeUpdateBackend(storage: storage)
        let service = UpdateService(backend: backend)
        service.start()
        #expect(service.automaticChecksEnabled)
        service.automaticChecksEnabled = false
        #expect(!storage.automatic)
        let date = Date(timeIntervalSince1970: 1_000)
        storage.date = date
        backend.onEvent?(.propertiesChanged)
        #expect(service.lastCheckDate == date)
        let restarted = UpdateService(backend: FakeUpdateBackend(storage: storage))
        restarted.start()
        #expect(!restarted.automaticChecksEnabled)
        #expect(restarted.lastCheckDate == date)
        restarted.checkForUpdates()
        #expect(restarted.state == .checking)
    }

    @Test("Backend preference changes refresh the model without another preference write")
    func externallyChangedPreference() {
        let backend = FakeUpdateBackend()
        let service = UpdateService(backend: backend)
        service.start()
        backend.storage.automatic = false
        backend.onEvent?(.propertiesChanged)
        #expect(!service.automaticChecksEnabled)
        #expect(backend.preferenceWrites == 0)
    }

    @Test("Installer preparation follows user presentation and failed install closes it")
    func installerLifecycle() {
        let backend = FakeUpdateBackend()
        let service = UpdateService(backend: backend)
        var events: [String] = []
        service.onPresentationChanged = { events.append($0 ? "open" : "close") }
        service.onWillInstall = { events.append("install") }
        service.start()
        service.checkForUpdates()
        backend.onEvent?(.available("0.1.0-alpha.5"))
        backend.onEvent?(.willInstall)
        backend.complete(.failed("installer failed"))
        #expect(events == ["open", "install", "close"])
        #expect(service.state == .failed("installer failed"))
    }

    @Test("A startup failure leaves checks unavailable and can be retried")
    func failedStartup() {
        let backend = FakeUpdateBackend()
        backend.startError = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "configuration unavailable"])
        let service = UpdateService(backend: backend)
        service.start()
        #expect(service.state == .failed("configuration unavailable"))
        #expect(!service.canCheck)
        backend.startError = nil
        service.start()
        #expect(service.canCheck)
        #expect(backend.starts == 2)
    }

    @Test("Sparkle scheduled alerts are suppressed even in immediate focus")
    func nativeGentlePolicy() {
        let backend = SparkleUpdateBackend(version: .development)
        let item = SUAppcastItem.empty()
        #expect(backend.supportsGentleScheduledUpdateReminders)
        #expect(!backend.standardUserDriverShouldHandleShowingScheduledUpdate(item, andInImmediateFocus: true))
        #expect(!backend.standardUserDriverShouldHandleShowingScheduledUpdate(item, andInImmediateFocus: false))
        #expect(!backend.canCheck)
    }

    @Test("The native adapter distinguishes latest or newer builds from unsupported updates")
    func nativeNoUpdateReasons() {
        let backend = SparkleUpdateBackend(version: .development)
        let service = UpdateService(backend: backend)
        // Instantiation is inert: none of these delegates starts the updater.
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        for reason in [SPUNoUpdateFoundReason.onLatestVersion, .onNewerThanLatestVersion] {
            let error = NSError(domain: SUSparkleErrorDomain, code: Int(SUError.noUpdateError.rawValue), userInfo: [
                SPUNoUpdateFoundReasonKey: NSNumber(value: reason.rawValue),
            ])
            backend.updaterDidNotFindUpdate(controller.updater, error: error)
            backend.updater(controller.updater, didFinishUpdateCycleFor: .updates, error: error)
            #expect(service.state == .upToDate)
        }
        let unsupported = NSError(domain: SUSparkleErrorDomain, code: Int(SUError.noUpdateError.rawValue), userInfo: [
            SPUNoUpdateFoundReasonKey: NSNumber(value: SPUNoUpdateFoundReason.systemIsTooOld.rawValue),
            NSLocalizedDescriptionKey: "This update requires a newer macOS version.",
        ])
        backend.updaterDidNotFindUpdate(controller.updater, error: unsupported)
        backend.updater(controller.updater, didFinishUpdateCycleFor: .updates, error: unsupported)
        #expect(service.state == .failed("This update requires a newer macOS version."))
    }

    @Test("Native cancellation is quiet, while offline errors remain visible in settings")
    func nativeFailureAndCancellation() {
        let backend = SparkleUpdateBackend(version: .development)
        let service = UpdateService(backend: backend)
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        var presentations: [Bool] = []
        service.onPresentationChanged = { presentations.append($0) }
        let cancelled = NSError(domain: SUSparkleErrorDomain, code: Int(SUError.installationCanceledError.rawValue))
        backend.updater(controller.updater, didFinishUpdateCycleFor: .updates, error: cancelled)
        #expect(service.state == .idle)
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: [NSLocalizedDescriptionKey: "offline"])
        backend.updater(controller.updater, didAbortWithError: offline)
        backend.updater(controller.updater, didFinishUpdateCycleFor: .updates, error: offline)
        #expect(service.state == .failed("offline"))
        #expect(presentations.isEmpty)
    }

    @Test("Menu and settings use both supported languages for each update state")
    func localizedPresentation() {
        let backend = FakeUpdateBackend()
        let service = UpdateService(backend: backend)
        service.start()
        for language in [AppLanguage.ko, .en] {
            #expect(service.menuTitle(language: language) == L10n.text("Check for Updates…", language: language))
            backend.onEvent?(.checking)
            #expect(service.statusText(language: language) == L10n.text("Checking for updates…", language: language))
            backend.onEvent?(.available("0.1.0-alpha.10"))
            #expect(service.menuTitle(language: language) == L10n.text("Update Available…", language: language))
            #expect(service.statusText(language: language).contains("0.1.0-alpha.10"))
            backend.complete(.upToDate)
            #expect(service.statusText(language: language) == L10n.text("You're up to date.", language: language))
            backend.complete(.failed("network error"))
            #expect(service.statusText(language: language) == L10n.text("Could not check for updates. Try again later.", language: language))
        }
    }
}

@MainActor
private final class FakeUpdateStorage {
    var automatic = true
    var date: Date?
}

@MainActor
private final class FakeUpdateBackend: UpdateBackend {
    let storage: FakeUpdateStorage
    var onEvent: ((UpdateBackendEvent) -> Void)?
    var canCheck = false
    var starts = 0
    var checks = 0
    var preferenceWrites = 0
    var startError: Error?

    init(storage: FakeUpdateStorage = FakeUpdateStorage()) { self.storage = storage }

    var automaticChecksEnabled: Bool {
        get { storage.automatic }
        set {
            storage.automatic = newValue
            preferenceWrites += 1
            onEvent?(.propertiesChanged)
        }
    }
    var lastCheckDate: Date? { storage.date }

    func start() throws {
        starts += 1
        if let startError { throw startError }
        canCheck = true
    }

    func checkForUpdates() {
        checks += 1
        canCheck = false
        onEvent?(.propertiesChanged)
    }

    func complete(_ event: UpdateBackendEvent) {
        canCheck = true
        onEvent?(event)
        onEvent?(.finished)
    }
}
