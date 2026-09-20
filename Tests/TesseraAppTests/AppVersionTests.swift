import Foundation
import Sparkle
import Testing
@testable import TesseraApp

@Suite("Release version metadata")
struct AppVersionTests {
    @Test("The installed release label is separate from the ordering build number")
    func alphaLabel() throws {
        let version = try #require(AppVersion(infoDictionary: metadata()))
        #expect(version.displayVersion == "0.1.0-alpha.4")
        #expect(version.baseVersion == "0.1.0")
        #expect(version.build == "4")
        #expect(version.isPrerelease)
        #expect(version.allowedChannels == ["alpha"])
    }

    @Test("Stable builds see the default channel only")
    func stableChannel() throws {
        let version = try #require(AppVersion(infoDictionary: metadata(release: "0.1.0", build: "12")))
        #expect(!version.isPrerelease)
        #expect(version.allowedChannels.isEmpty)
    }

    @Test("Missing and inconsistent identity is not guessed from build number")
    func invalidMetadata() {
        #expect(AppVersion(infoDictionary: [:]) == nil)
        #expect(AppVersion(infoDictionary: metadata(release: "0.2.0-alpha.4")) == nil)
        #expect(AppVersion(infoDictionary: metadata(release: "v0.1.0-alpha.4")) == nil)
        #expect(AppVersion(infoDictionary: metadata(release: "0.1.0-alpha.")) == nil)
        #expect(AppVersion(infoDictionary: metadata(release: "0.1.0-alpha.4\n")) == nil)
        #expect(AppVersion(infoDictionary: metadata(build: "alpha.4")) == nil)
        #expect(AppVersion(infoDictionary: metadata(build: "0")) == nil)
        var wrongType = metadata()
        wrongType["CFBundleVersion"] = 4
        #expect(AppVersion(infoDictionary: wrongType) == nil)
    }

    @Test("Sparkle orders monotonically increasing builds, including stable promotion")
    func buildOrdering() {
        let compare = SUStandardVersionComparator.default
        #expect(compare.compareVersion("4", toVersion: "4") == .orderedSame)
        #expect(compare.compareVersion("3", toVersion: "4") == .orderedAscending)
        #expect(compare.compareVersion("10", toVersion: "4") == .orderedDescending)
        #expect(compare.compareVersion("12", toVersion: "10") == .orderedDescending)
    }

    @Test("Sparkle's current-version alert uses the full installed release label")
    func sparklesDisplay() throws {
        let version = try #require(AppVersion(infoDictionary: metadata()))
        let display = ReleaseVersionDisplayer(version: version)
        #expect(display.formatBundleDisplayVersion("0.1.0", withBundleVersion: "4", matchingUpdate: nil) == "0.1.0-alpha.4")
    }

    private func metadata(release: String = "0.1.0-alpha.4", build: String = "4") -> [String: Any] {
        ["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": build, "TesseraReleaseVersion": release]
    }
}
