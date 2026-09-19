import CoreGraphics
import Foundation
import Testing
import TesseraCore
@testable import TesseraApp

@Suite("Bounded window placement", .timeLimit(.minutes(1)))
@MainActor
struct WindowPlacementTests {
    private let bounds = CGRect(x: 0, y: 0, width: 1200, height: 800)

    private func frame(_ layout: LayoutPreset, _ target: PlacementTarget) throws -> CGRect {
        CoordinateSpace.flip(try GridGeometry.frame(in: bounds, layout: layout,
            target: target, gap: 8, scale: 1), primaryTop: bounds.maxY)
    }

    @Test("Right-third to right-half expansion makes room before its one resize",
          arguments: [PlacementTarget.column(2), .zone(2), .zone(4)])
    func rightEdgeExpansion(_ target: PlacementTarget) throws {
        let originalTarget: PlacementTarget
        switch target {
        case .column: originalTarget = .column(3)
        case .zone(2): originalTarget = .zone(3)
        default: originalTarget = .zone(6)
        }
        let initial = try frame(.threeByTwo, originalTarget)
        let requested = try frame(.twoByTwo, target)

        // This backend reproduces the observed dependency on the old origin.
        let oldOrder = PlacementWindowFake(frame: initial, bounds: bounds)
        try oldOrder.setSize(requested.size)
        try oldOrder.setPosition(requested.origin)
        #expect(oldOrder.frame.width < requested.width)

        let window = PlacementWindowFake(frame: initial, bounds: bounds)
        let result = window.place(requested)
        #expect(result.outcome == .applied)
        #expect(result.constraintReason == nil)
        #expect(result.feedbackDuration == .seconds(1))
        #expect(result.actualFrame == requested)
        #expect(window.writes.count == 3)
        #expect(window.resizeCount == 1)
        #expect(window.positionCount == 2)
        #expect(window.events == ["validate", "read", "validate", "position", "read",
            "validate", "size", "read", "validate", "position", "read"])
        #expect(window.traces.map { $0.0 } == ["requested", "initial", "prepared", "resized", "final"])
        #expect(window.traces.first?.1 == requested)
        #expect(window.traces.last?.1 == requested)
    }

    @Test("Middle-third to right-half expansion already has room and needs no preparation")
    func middleExpansionSkipsPreparation() throws {
        let requested = try frame(.twoByTwo, .column(2))
        let window = PlacementWindowFake(frame: try frame(.threeByTwo, .column(2)), bounds: bounds)
        let result = window.place(requested)
        #expect(result.outcome == .applied)
        #expect(window.writes == [.size(requested.size), .position(requested.origin)])
        #expect(window.traces.map { $0.0 } == ["requested", "initial", "resized", "final"])
    }

    @Test("The mirrored left-side expansion keeps the original two-write path")
    func leftExpansionSkipsPreparation() throws {
        let requested = try frame(.twoByTwo, .column(1))
        let window = PlacementWindowFake(frame: try frame(.threeByTwo, .column(1)), bounds: bounds)
        let result = window.place(requested)
        #expect(result.outcome == .applied)
        #expect(window.writes == [.size(requested.size), .position(requested.origin)])
        #expect(result.actualFrame == requested)
    }

    @Test("Bottom-to-full expansion first creates vertical room")
    func verticalExpansion() throws {
        let initial = try frame(.twoByTwo, .zone(4))
        let requested = try frame(.twoByTwo, .column(2))
        let window = PlacementWindowFake(frame: initial, bounds: bounds)
        let result = window.place(requested)
        #expect(result.outcome == .applied)
        #expect(window.writes.count == 3)
        let prepared = try #require(window.traces.first { $0.0 == "prepared" }?.1)
        #expect(prepared.minY < initial.minY)
        #expect(prepared.minY + requested.height <= bounds.maxY)
        #expect(result.actualFrame == requested)
    }

    @Test("Mixed-axis transitions keep the existing and requested sizes inside the staging bounds",
          arguments: [false, true])
    func mixedAxisExpansion(_ growsBothAxes: Bool) throws {
        let initial = try frame(.threeByTwo, growsBothAxes ? .zone(6) : .column(3))
        let requested = try frame(.twoByTwo, growsBothAxes ? .column(2) : .zone(4))
        let window = PlacementWindowFake(frame: initial, bounds: bounds)
        let result = window.place(requested)
        #expect(result.outcome == .applied)
        let prepared = try #require(window.traces.first { $0.0 == "prepared" }?.1)
        #expect(prepared.maxX <= bounds.maxX)
        #expect(prepared.maxY <= bounds.maxY)
        #expect(prepared.minX + requested.width <= bounds.maxX)
        #expect(prepared.minY + requested.height <= bounds.maxY)
        #expect(window.resizeCount == 1)
        #expect(window.writes.count == 3)
    }

    @Test("Preparation uses AX global coordinates on a shifted display")
    func shiftedDisplay() throws {
        let dx: CGFloat = -1600.5
        let dy: CGFloat = -900.5
        let shiftedBounds = bounds.offsetBy(dx: dx, dy: dy)
        let initial = try frame(.threeByTwo, .zone(6)).offsetBy(dx: dx, dy: dy)
        let requested = try frame(.twoByTwo, .column(2)).offsetBy(dx: dx, dy: dy)
        let window = PlacementWindowFake(frame: initial, bounds: shiftedBounds)
        let result = window.place(requested)
        #expect(result.outcome == .applied)
        #expect(result.actualFrame == requested)
        #expect(window.writes.count == 3)
    }

    @Test("Application minimum sizes remain constraints rather than triggering retries",
          arguments: [CGSize(width: 700, height: 600), CGSize(width: 1300, height: 900)])
    func minimumSizeRemainsConstrained(_ minimum: CGSize) throws {
        let requested = try frame(.twoByTwo, .zone(2))
        let window = PlacementWindowFake(frame: try frame(.threeByTwo, .zone(3)), bounds: bounds)
        window.minimumSize = minimum
        let result = window.place(requested)
        #expect(result.outcome == .constrained)
        #expect(result.actualFrame?.size == minimum)
        #expect(window.resizeCount == 1)
        #expect(window.writes.count == 3)
        if minimum.width > bounds.width {
            #expect(result.actualFrame?.origin == bounds.origin)
            #expect(result.constraintReason == .outsideVisibleArea)
            #expect(result.feedbackDuration == .seconds(4))
            #expect(result.message == L10n.text("The window could not fit fully inside the usable display area."))
        } else {
            #expect(result.constraintReason == .sizeAdjusted)
            #expect(result.feedbackDuration == .seconds(1))
            #expect(result.message == L10n.text("Arranged · Adjusted to app size"))
        }
    }

    @Test("Observed 474.5pt halves align correctly when the app requires a 600pt height",
          arguments: [2, 3], [false, true])
    func observedMinimumHeight(columns: Int, bottom: Bool) {
        let display = CGRect(x: 0, y: 33, width: 1512, height: 949)
        let width = display.width / CGFloat(columns)
        let initial = CGRect(x: width, y: 33, width: width, height: 949)
        let requested = CGRect(x: width, y: bottom ? 507.5 : 33, width: width, height: 474.5)
        let window = PlacementWindowFake(frame: initial, bounds: display)
        window.minimumSize = CGSize(width: 0, height: 600)

        let result = window.place(requested)

        #expect(result.outcome == .constrained)
        #expect(result.constraintReason == .sizeAdjusted)
        #expect(result.message == L10n.text("Arranged · Adjusted to app size"))
        #expect(result.feedbackDuration == .seconds(1))
        #expect(result.actualFrame == CGRect(x: width, y: bottom ? 382 : 33, width: width, height: 600))
        #expect(window.writes == [.size(requested.size),
            .position(CGPoint(x: width, y: bottom ? 382 : 33))])
        #expect(window.resizeCount == 1)
        #expect(window.positionCount == 1)
        #expect(window.traces.map { $0.0 } == ["requested", "initial", "resized", "final"])
    }

    @Test("Alignment is judged against the final size when the app adjusts again during its move")
    func finalSizeDeterminesAlignment() {
        let display = CGRect(x: 0, y: 33, width: 1512, height: 949)
        let requested = CGRect(x: 504, y: 507.5, width: 504, height: 474.5)
        let window = PlacementWindowFake(frame: CGRect(x: 504, y: 33, width: 504, height: 949), bounds: display)
        window.minimumSize = CGSize(width: 0, height: 600)
        // After accepting the 600pt resize, the app reports a 610pt window
        // aligned to the bottom edge by its own final move handling.
        window.readFrames[3] = CGRect(x: 504, y: 372, width: 504, height: 610)

        let result = window.place(requested)

        #expect(result.outcome == .constrained)
        #expect(result.constraintReason == .sizeAdjusted)
        #expect(result.actualFrame == window.readFrames[3])
        #expect(result.feedbackDuration == .seconds(1))
        #expect(window.writes == [.size(requested.size), .position(CGPoint(x: 504, y: 382))])
    }

    @Test("An ignored final move is a position mismatch even when resizing also has constraints",
          arguments: [CGSize.zero, CGSize(width: 700, height: 600)])
    func ignoredFinalPosition(_ minimum: CGSize) throws {
        let requested = try frame(.twoByTwo, .zone(2))
        let initial = CGRect(x: 100, y: 200, width: 300, height: 300)
        let window = PlacementWindowFake(frame: initial, bounds: bounds)
        window.minimumSize = minimum
        window.ignoreFirstPosition = true

        let result = window.place(requested)

        #expect(result.outcome == .constrained)
        #expect(result.constraintReason == .positionMismatch)
        #expect(result.message == L10n.text("The window could not be aligned to the requested position."))
        #expect(result.feedbackDuration == .seconds(4))
        #expect(result.actualFrame?.origin == initial.origin)
        #expect(window.writes.count == 2)
        #expect(window.resizeCount == 1)
        #expect(window.positionCount == 1)
    }

    @Test("Outside-display readback takes precedence over its position mismatch")
    func outsideDisplayPrecedesPositionMismatch() throws {
        let requested = try frame(.twoByTwo, .column(2))
        let window = PlacementWindowFake(frame: try frame(.threeByTwo, .column(2)), bounds: bounds)
        window.readOffsets[3] = CGPoint(x: 9, y: 0)

        let result = window.place(requested)

        #expect(result.outcome == .constrained)
        #expect(result.constraintReason == .outsideVisibleArea)
        #expect(result.message == L10n.text("The window could not fit fully inside the usable display area."))
        #expect(result.feedbackDuration == .seconds(4))
        #expect(try #require(result.actualFrame).maxX > bounds.maxX)
        #expect(window.writes.count == 2)
    }

    @Test("An ignored preparation move ends with honest constrained readback and no retry")
    func ignoredPreparation() throws {
        let requested = try frame(.twoByTwo, .column(2))
        let window = PlacementWindowFake(frame: try frame(.threeByTwo, .column(3)), bounds: bounds)
        window.ignoreFirstPosition = true
        let result = window.place(requested)
        #expect(result.outcome == .constrained)
        #expect(result.constraintReason == .sizeAdjusted)
        #expect(try #require(result.actualFrame).width < requested.width)
        #expect(window.resizeCount == 1)
        #expect(window.positionCount == 2)
        #expect(window.writes.count == 3)
    }

    @Test("Final readback distinguishes floating-point noise from a visible adjustment",
          arguments: [CGFloat(0.0002), CGFloat(0.25)])
    func finalReadbackClassification(_ offset: CGFloat) throws {
        let requested = try frame(.twoByTwo, .column(2))
        let window = PlacementWindowFake(frame: try frame(.threeByTwo, .column(2)), bounds: bounds)
        window.readOffsets[3] = CGPoint(x: offset, y: -offset)
        let result = window.place(requested)
        #expect(result.outcome == (offset < 0.001 ? .applied : .constrained))
        #expect(result.constraintReason == (offset < 0.001 ? nil : .positionMismatch))
        #expect(window.writes.count == 2)
    }

    @Test("Permission or focus changes at each validation boundary prevent every later write",
          arguments: [WindowSystemError.permissionRequired, .targetChanged])
    func validationFailureStopsLaterWrites(_ error: WindowSystemError) throws {
        for boundary in 1...4 {
            let window = try edgeWindow()
            window.validationFailure = (boundary, error)
            let result = window.place(try frame(.twoByTwo, .column(2)))
            #expect(window.writes.count == max(0, boundary - 2))
            #expect(window.validationCount == boundary)
            #expect(result.outcome == (boundary <= 2 ? .unavailable : .failed))
            #expect(result.constraintReason == nil)
            #expect(result.feedbackDuration == .seconds(4))
            if boundary > 2 { #expect(result.message.contains(L10n.text("The window may be partly arranged."))) }
        }
    }

    @Test("Cancellation raised during validation prevents the immediately following write",
          arguments: [1, 2, 3, 4])
    func cancellationDuringValidation(_ boundary: Int) async throws {
        let window = try edgeWindow()
        window.cancelOnValidation = boundary
        let requested = try frame(.twoByTwo, .column(2))
        let task = Task { @MainActor in window.place(requested) }
        let result = await task.value
        #expect(window.writes.count == max(0, boundary - 2))
        #expect(result.outcome == (boundary <= 2 ? .unavailable : .failed))
        #expect((result.message.contains(L10n.text("Arrangement was cancelled.")) || result.message == L10n.text("Arrangement was cancelled before the window was changed.")))
    }

    @Test("Cancellation after preparation or resizing preserves the partial result without another write",
          arguments: [1, 2])
    func cancellationBetweenWrites(_ write: Int) async throws {
        let window = try edgeWindow()
        window.cancelAfterWrite = write
        let requested = try frame(.twoByTwo, .column(2))
        let task = Task { @MainActor in window.place(requested) }
        let result = await task.value
        #expect(result.outcome == .failed)
        #expect(result.message.contains(L10n.text("The window may be partly arranged.")))
        #expect((result.message.contains(L10n.text("Arrangement was cancelled.")) || result.message == L10n.text("Arrangement was cancelled before the window was changed.")))
        #expect(window.writes.count == write)
        #expect(result.actualFrame == window.frame)
        #expect(window.resizeCount == (write == 1 ? 0 : 1))
    }

    @Test("Already cancelled work never reads or writes a window")
    func cancellationBeforeStart() async throws {
        let window = try edgeWindow()
        let requested = try frame(.twoByTwo, .column(2))
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return window.place(requested)
        }
        let result = await task.value
        #expect(result.outcome == .unavailable)
        #expect(window.events.isEmpty)
        #expect(window.writes.isEmpty)
    }

    @Test("Every setter failure is partial even if AX reports failure after applying the write",
          arguments: [1, 2, 3])
    func setterFailure(_ write: Int) throws {
        let window = try edgeWindow()
        window.failWrite = write
        let result = window.place(try frame(.twoByTwo, .column(2)))
        #expect(result.outcome == .failed)
        #expect(result.constraintReason == nil)
        #expect(result.feedbackDuration == .seconds(4))
        #expect(result.message.contains(L10n.text("The window may be partly arranged.")))
        #expect(window.writes.count == write)
        #expect(window.readCount == write + 1) // one diagnostic read after the setter error
        #expect(result.actualFrame == window.frame)
        #expect(window.resizeCount <= 1)
    }

    @Test("Read failures never retry or return a stale frame",
          arguments: [1, 2, 3, 4])
    func readFailure(_ read: Int) throws {
        let window = try edgeWindow()
        window.failReads = [read]
        let result = window.place(try frame(.twoByTwo, .column(2)))
        #expect(result.outcome == (read == 1 ? .unavailable : .failed))
        #expect(result.actualFrame == nil)
        #expect(window.readCount == read)
        #expect(window.writes.count == read - 1)
        #expect(window.writes.count <= 3)
    }

    @Test("An invalid readback is also terminal and cannot expose a previous frame")
    func invalidReadback() throws {
        let window = try edgeWindow()
        window.invalidRead = 3
        let result = window.place(try frame(.twoByTwo, .column(2)))
        #expect(result.outcome == .failed)
        #expect(result.actualFrame == nil)
        #expect(window.readCount == 3)
        #expect(window.writes.count == 2)
    }

    @Test("A failed diagnostic read after a setter error is not retried")
    func failedSetterDiagnosticRead() throws {
        let window = try edgeWindow()
        window.failWrite = 1
        window.failReads = [2]
        let result = window.place(try frame(.twoByTwo, .column(2)))
        #expect(result.outcome == .failed)
        #expect(result.actualFrame == nil)
        #expect(window.readCount == 2)
        #expect(window.writes.count == 1)
    }

    @Test("Invalid requested geometry is rejected before validation or any AX operation")
    func invalidRequestedGeometry() throws {
        for requested in [CGRect.zero, CGRect(x: 0, y: 0, width: -20, height: 30),
            CGRect(x: CGFloat.nan, y: 0, width: 20, height: 30),
            CGRect(x: 1100, y: 0, width: 200, height: 100)] {
            let window = try edgeWindow()
            let result = window.place(requested)
            #expect(result.outcome == .unavailable)
            #expect(result.actualFrame == nil)
            #expect(window.events.isEmpty)
            #expect(window.traces.isEmpty)
        }
    }

    private func edgeWindow() throws -> PlacementWindowFake {
        PlacementWindowFake(frame: try frame(.threeByTwo, .column(3)), bounds: bounds)
    }
}

/// Screen-bounded resize behavior deliberately depends on the current origin,
/// reproducing an app that clamps expansion before a later move makes room.
@MainActor
private final class PlacementWindowFake {
    enum Write: Equatable {
        case position(CGPoint)
        case size(CGSize)
    }
    enum Failure: Error { case injected }

    var frame: CGRect
    let bounds: CGRect
    var minimumSize = CGSize.zero
    var ignoreFirstPosition = false
    var validationFailure: (Int, WindowSystemError)?
    var cancelOnValidation: Int?
    var cancelAfterWrite: Int?
    var failWrite: Int?
    var failReads: Set<Int> = []
    var invalidRead: Int?
    var readOffsets: [Int: CGPoint] = [:]
    var readFrames: [Int: CGRect] = [:]
    private(set) var events: [String] = []
    private(set) var writes: [Write] = []
    private(set) var traces: [(String, CGRect)] = []
    private(set) var validationCount = 0
    private(set) var readCount = 0
    private(set) var resizeCount = 0
    private(set) var positionCount = 0

    init(frame: CGRect, bounds: CGRect) {
        self.frame = frame
        self.bounds = bounds
    }

    func place(_ requested: CGRect) -> PlacementResult {
        WindowPlacement.perform(frame: requested, visibleFrame: bounds,
            readFrame: { try self.readFrame() }, validate: { try self.validate() },
            setSize: { try self.setSize($0) }, setPosition: { try self.setPosition($0) },
            trace: { self.traces.append(($0, $1)) })
    }

    func validate() throws {
        validationCount += 1
        events.append("validate")
        if cancelOnValidation == validationCount { withUnsafeCurrentTask { $0?.cancel() } }
        if let (boundary, error) = validationFailure, boundary == validationCount { throw error }
    }

    func readFrame() throws -> CGRect {
        readCount += 1
        events.append("read")
        if failReads.contains(readCount) { throw Failure.injected }
        if invalidRead == readCount { return CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10) }
        if let observed = readFrames[readCount] { return observed }
        if let offset = readOffsets[readCount] { return frame.offsetBy(dx: offset.x, dy: offset.y) }
        return frame
    }

    func setSize(_ size: CGSize) throws {
        writes.append(.size(size))
        events.append("size")
        resizeCount += 1
        frame.size = CGSize(
            width: max(minimumSize.width, min(size.width, bounds.maxX - frame.minX)),
            height: max(minimumSize.height, min(size.height, bounds.maxY - frame.minY))
        )
        try afterWrite()
    }

    func setPosition(_ origin: CGPoint) throws {
        writes.append(.position(origin))
        events.append("position")
        positionCount += 1
        if !(ignoreFirstPosition && positionCount == 1) {
            frame.origin = CGPoint(
                x: max(bounds.minX, min(origin.x, bounds.maxX - frame.width)),
                y: max(bounds.minY, min(origin.y, bounds.maxY - frame.height))
            )
        }
        try afterWrite()
    }

    private func afterWrite() throws {
        if cancelAfterWrite == writes.count { withUnsafeCurrentTask { $0?.cancel() } }
        if failWrite == writes.count { throw Failure.injected }
    }
}
