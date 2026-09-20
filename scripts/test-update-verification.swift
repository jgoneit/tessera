import CryptoKit
import Foundation

// Independent short-lived test keys never leave this process. These fixtures
// exercise verification failures without reading the release signing key.
let verifier = CommandLine.arguments[1]
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tessera-signature-tests-\(UUID())")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let key = Curve25519.Signing.PrivateKey()
let archive = Data("signed archive fixture".utf8)
let archiveName = "Tessera-0.1.0-alpha.4-arm64.dmg"
let infoURL = directory.appendingPathComponent("Info.plist")
let feedURL = directory.appendingPathComponent("appcast.xml")
let archiveURL = directory.appendingPathComponent(archiveName)
let publicKey = key.publicKey.rawRepresentation.base64EncodedString()

func writeInfo(key: String) throws {
    try PropertyListSerialization.data(fromPropertyList: [
        "SUPublicEDKey": key, "CFBundleVersion": "4", "TesseraReleaseVersion": "0.1.0-alpha.4",
    ], format: .xml, options: 0).write(to: infoURL)
}

func makeFeed(build: String = "4", url: String = "https://github.com/jgoneit/tessera/releases/download/v0.1.0-alpha.4/Tessera-0.1.0-alpha.4-arm64.dmg", length: Int? = nil, channel: String = "alpha", displayVersion: String = "0.1.0-alpha.4", duplicate: Bool = false) throws -> Data {
    let archiveSignature = try key.signature(for: archive).base64EncodedString()
    let item = """
    <item><sparkle:version>\(build)</sparkle:version><sparkle:shortVersionString>\(displayVersion)</sparkle:shortVersionString><sparkle:channel>\(channel)</sparkle:channel><enclosure url="\(url)" sparkle:edSignature="\(archiveSignature)" length="\(length ?? archive.count)"/></item>
    """
    let content = Data("""
    <?xml version="1.0" encoding="utf-8"?>
    <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
    \(item)\(duplicate ? item : "")
    </channel></rss>

    """.utf8)
    let signature = try key.signature(for: content).base64EncodedString()
    return content + Data("<!-- sparkle-signatures:\nedSignature: \(signature)\nlength: \(content.count)\n-->\n".utf8)
}

func expect(_ name: String, success: Bool, includeArchive: Bool = true) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: verifier)
    process.arguments = [infoURL.path, feedURL.path] + (includeArchive ? [archiveURL.path] : [])
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard (process.terminationStatus == 0) == success else {
        fputs("Signature verifier regression: \(name)\n", stderr)
        exit(1)
    }
    print("Passed: \(name)")
}

try writeInfo(key: publicKey)
try archive.write(to: archiveURL)
let validFeed = try makeFeed()
try validFeed.write(to: feedURL)
try expect("valid signed feed and archive", success: true)
try expect("public-key-only feed verification", success: true, includeArchive: false)
try (validFeed + Data("unexpected trailer".utf8)).write(to: feedURL)
try expect("reject content after signing block", success: false)
var corruptFeed = validFeed
corruptFeed[20] ^= 1
try corruptFeed.write(to: feedURL)
try expect("reject tampered feed", success: false)
try validFeed.write(to: feedURL)
try Data("tampered archive".utf8).write(to: archiveURL)
try expect("reject tampered archive", success: false)
try archive.write(to: archiveURL)
try writeInfo(key: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString())
try expect("reject another signing key", success: false)
try writeInfo(key: publicKey)
try makeFeed(url: "http://localhost/unpublished.dmg").write(to: feedURL)
try expect("reject a local feed in production verification", success: false)
try makeFeed(url: "https://github.com/jgoneit/tessera/releases/download/v0.1.0-alpha.5/\(archiveName)").write(to: feedURL)
try expect("reject mismatched release URL", success: false)
try makeFeed(build: "5").write(to: feedURL)
try expect("reject absent current build", success: false)
try makeFeed(length: archive.count + 1).write(to: feedURL)
try expect("reject mismatched archive length", success: false)
try makeFeed(channel: "").write(to: feedURL)
try expect("reject missing alpha channel", success: false)
try makeFeed(displayVersion: "0.1.0").write(to: feedURL)
try expect("reject incomplete release display label", success: false)
try makeFeed(duplicate: true).write(to: feedURL)
try expect("reject duplicate build items", success: false)
