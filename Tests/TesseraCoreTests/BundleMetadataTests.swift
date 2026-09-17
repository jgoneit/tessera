import Foundation
import Testing

@Test func appBundleMetadataSupportsBackgroundLaunch() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
    let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    #expect(plist["CFBundleExecutable"] as? String == "Tessera")
    #expect(plist["CFBundlePackageType"] as? String == "APPL")
    #expect(plist["CFBundleIdentifier"] as? String == "io.github.jgoneit.tessera")
    #expect(plist["NSPrincipalClass"] as? String == "NSApplication")
    #expect(plist["LSUIElement"] as? Bool == true)
    #expect(plist["LSMinimumSystemVersion"] as? String == "14.0")
}
