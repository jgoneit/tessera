import CryptoKit
import Foundation

// A public-key-only verifier for release/CI use. Signing tools read the private
// key from Keychain; verification must never require that key or a prompt.
func fail(_ message: String) -> Never {
    fputs("Update verification failed: \(message)\n", stderr)
    exit(1)
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard (2...3).contains(arguments.count) else {
        fail("Usage: swift scripts/verify-update.swift <Info.plist> <appcast.xml> [archive]")
    }
    let infoData = try Data(contentsOf: URL(fileURLWithPath: arguments[0]))
    guard let info = try PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any],
          let publicKeyString = info["SUPublicEDKey"] as? String,
          let publicKeyData = Data(base64Encoded: publicKeyString), publicKeyData.count == 32 else {
        fail("Missing updater public key.")
    }
    let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
    let feed = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
    let marker = Data("<!-- sparkle-signatures:\n".utf8)
    guard let blockRange = feed.range(of: marker, options: .backwards),
          let block = String(data: feed[blockRange.lowerBound...], encoding: .utf8) else {
        fail("Missing signed appcast block.")
    }
    let pattern = #"\A<!-- sparkle-signatures:\nedSignature: ([A-Za-z0-9+/=]+)\nlength: ([0-9]+)\n-->\n?\z"#
    let expression = try NSRegularExpression(pattern: pattern)
    guard let match = expression.firstMatch(in: block, range: NSRange(block.startIndex..., in: block)),
          let signatureRange = Range(match.range(at: 1), in: block),
          let lengthRange = Range(match.range(at: 2), in: block),
          let signature = Data(base64Encoded: String(block[signatureRange])),
          let length = Int(block[lengthRange]), length == blockRange.lowerBound,
          publicKey.isValidSignature(signature, for: feed.prefix(length)) else {
        fail("Invalid appcast signature or signed length.")
    }
    let document = try XMLDocument(data: Data(feed.prefix(length)), options: [.nodeLoadExternalEntitiesNever])
    let items = try document.nodes(forXPath: "/rss/channel/item").compactMap { $0 as? XMLElement }
    guard !items.isEmpty else { fail("Feed has no update items.") }
    let namespace = "http://www.andymatuschak.org/xml-namespaces/sparkle"
    var matchingEnclosure: XMLElement?
    var seenBuilds = Set<String>()
    for item in items {
        guard let version = item.elements(forLocalName: "version", uri: namespace).first?.stringValue,
              let numericVersion = Int(version), numericVersion > 0, seenBuilds.insert(version).inserted,
              let enclosure = item.elements(forName: "enclosure").first,
              let urlString = enclosure.attribute(forName: "url")?.stringValue,
              let url = URL(string: urlString), url.scheme == "https",
              url.host == "github.com", url.path.hasPrefix("/jgoneit/tessera/releases/download/"),
              let encodedSignature = enclosure.attribute(forLocalName: "edSignature", uri: namespace)?.stringValue,
              Data(base64Encoded: encodedSignature)?.count == 64,
              let lengthText = enclosure.attribute(forName: "length")?.stringValue,
              let archiveLength = Int(lengthText), archiveLength > 0 else {
            fail("Invalid update item version, URL, signature, or archive length.")
        }
        if version == info["CFBundleVersion"] as? String {
            guard let release = info["TesseraReleaseVersion"] as? String,
                  item.elements(forLocalName: "shortVersionString", uri: namespace).first?.stringValue == release else {
                fail("The feed display version does not match the app's full release version.")
            }
            let channel = item.elements(forLocalName: "channel", uri: namespace).first?.stringValue
            guard release.contains("-alpha.") ? channel == "alpha" : channel == nil else {
                fail("The release does not use the expected alpha or stable update channel.")
            }
            matchingEnclosure = enclosure
        }
    }
    if arguments.count == 3 {
        guard let enclosure = matchingEnclosure,
              let signatureText = enclosure.attribute(forLocalName: "edSignature", uri: namespace)?.stringValue,
              let signature = Data(base64Encoded: signatureText),
              let expectedLengthText = enclosure.attribute(forName: "length")?.stringValue,
              let expectedLength = Int(expectedLengthText),
              let url = enclosure.attribute(forName: "url")?.stringValue,
              let release = info["TesseraReleaseVersion"] as? String else {
            fail("The feed does not contain the app's build.")
        }
        let archiveURL = URL(fileURLWithPath: arguments[2])
        let expectedURL = "https://github.com/jgoneit/tessera/releases/download/v\(release)/\(archiveURL.lastPathComponent)"
        guard url == expectedURL else { fail("Archive URL does not match the release tag and filename.") }
        let archive = try Data(contentsOf: archiveURL, options: .mappedIfSafe)
        guard archive.count == expectedLength, publicKey.isValidSignature(signature, for: archive) else {
            fail("Archive signature or length does not match.")
        }
        print("Verified signed appcast and archive for \(release).")
    } else {
        print("Verified signed appcast using the bundled public key.")
    }
} catch {
    fail(error.localizedDescription)
}
