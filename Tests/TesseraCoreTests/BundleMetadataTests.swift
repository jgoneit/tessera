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
    #expect(plist["CFBundleIconFile"] as? String == "AppIcon.icns")
    #expect(plist["CFBundleLocalizations"] as? [String] == ["en", "ko"])
    #expect(plist["NSPrincipalClass"] as? String == "NSApplication")
    #expect(plist["LSUIElement"] as? Bool == true)
    #expect(plist["LSMinimumSystemVersion"] as? String == "14.0")
    #expect(plist["CFBundleVersion"] as? String == "4")
    #expect(plist["TesseraReleaseVersion"] as? String == "0.1.0-alpha.4")
    #expect(plist["SUFeedURL"] as? String == "https://jgoneit.github.io/tessera/appcast.xml")
    let publicKey = try #require(plist["SUPublicEDKey"] as? String)
    #expect(Data(base64Encoded: publicKey)?.count == 32)
    #expect(plist["SUEnableAutomaticChecks"] as? Bool == true)
    #expect(plist["SUScheduledCheckInterval"] as? Int == 86400)
    #expect(plist["SUAutomaticallyUpdate"] as? Bool == false)
    #expect(plist["SUAllowsAutomaticUpdates"] as? Bool == false)
    #expect(plist["SUEnableSystemProfiling"] as? Bool == false)
    #expect(plist["SUVerifyUpdateBeforeExtraction"] as? Bool == true)
    #expect(plist["SURequireSignedFeed"] as? Bool == true)
    #expect(plist["SUEnableInstallerLauncherService"] == nil)

    let iconData = try Data(contentsOf: root.appendingPathComponent("Resources/AppIcon.png"))
    #expect(iconData.starts(with: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))
}
