// swift-tools-version: 6.0
import PackageDescription
import Foundation

// Some Command Line Tools distributions bundle Swift Testing's macro plugin in
// a nested directory that the build engine does not automatically discover.
// Resolve it from the selected compiler rather than pinning a machine/SDK path.
func bundledTestingMacroSettings() -> [SwiftSetting] {
    let compilerPath: String
    if let configured = Context.environment["SWIFT_EXEC"], !configured.isEmpty {
        compilerPath = configured
    } else {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--find", "swiftc"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let result = String(data: data, encoding: .utf8) else { return [] }
        compilerPath = result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard !compilerPath.isEmpty else { return [] }
    let directory = URL(fileURLWithPath: compilerPath).resolvingSymlinksInPath()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("lib/swift/host/plugins/testing", isDirectory: true)
    guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("libTestingMacros.dylib").path) else {
        return []
    }
    return [.unsafeFlags(["-plugin-path", directory.path])]
}

let testingMacroSettings = bundledTestingMacroSettings()

let package = Package(
    name: "Tessera",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Tessera", targets: ["TesseraApp"])],
    targets: [
        .target(name: "TesseraCore"),
        .executableTarget(name: "TesseraApp", dependencies: ["TesseraCore"],
            resources: [.process("Resources")]),
        .testTarget(name: "TesseraCoreTests", dependencies: ["TesseraCore"], swiftSettings: testingMacroSettings),
        .testTarget(name: "TesseraAppTests", dependencies: ["TesseraApp"], swiftSettings: testingMacroSettings),
    ]
)
