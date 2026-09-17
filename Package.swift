// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tessera",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Tessera", targets: ["TesseraApp"])],
    targets: [
        .target(name: "TesseraCore"),
        .executableTarget(name: "TesseraApp", dependencies: ["TesseraCore"]),
        .testTarget(name: "TesseraCoreTests", dependencies: ["TesseraCore"]),
    ]
)
