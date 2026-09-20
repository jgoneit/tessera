import Foundation
import Sparkle

/// A release label is for people; Sparkle compares the monotonically increasing
/// CFBundleVersion independently of this label.
struct AppVersion: Equatable, Sendable {
    let baseVersion: String
    let build: String
    let fullVersion: String

    var displayVersion: String { fullVersion }
    var isPrerelease: Bool { fullVersion.contains("-") }
    var allowedChannels: Set<String> { isPrerelease ? ["alpha"] : [] }

    static var current: AppVersion {
        AppVersion(infoDictionary: Bundle.main.infoDictionary ?? [:]) ?? .development
    }

    /// SwiftPM test/preview executables do not have the app's Info.plist. Do not
    /// pretend they are a particular published release.
    static let development = AppVersion(baseVersion: "0.0.0", build: "0", fullVersion: "Development")

    init(baseVersion: String, build: String, fullVersion: String) {
        self.baseVersion = baseVersion
        self.build = build
        self.fullVersion = fullVersion
    }

    init?(infoDictionary: [String: Any]) {
        guard let base = infoDictionary["CFBundleShortVersionString"] as? String,
              let build = infoDictionary["CFBundleVersion"] as? String,
              let release = infoDictionary["TesseraReleaseVersion"] as? String,
              base.range(of: #"\A[0-9]+\.[0-9]+\.[0-9]+\z"#, options: .regularExpression) != nil,
              build.range(of: #"\A[1-9][0-9]*\z"#, options: .regularExpression) != nil,
              release == base || release.range(
                  of: #"\A"# + NSRegularExpression.escapedPattern(for: base) + #"-alpha\.[1-9][0-9]*\z"#,
                  options: .regularExpression
              ) != nil else { return nil }
        self.init(baseVersion: base, build: build, fullVersion: release)
    }
}

/// Applies the explicit release label to Sparkle's installed-version display.
/// Feed entries already contain their full release label in shortVersionString.
final class ReleaseVersionDisplayer: NSObject, SUVersionDisplay {
    private let version: AppVersion

    init(version: AppVersion) { self.version = version }

    func formatUpdateVersion(
        fromUpdate update: SUAppcastItem,
        andBundleDisplayVersion inOutBundleDisplayVersion: AutoreleasingUnsafeMutablePointer<NSString>,
        withBundleVersion bundleVersion: String
    ) -> String {
        inOutBundleDisplayVersion.pointee = version.fullVersion as NSString
        return update.displayVersionString
    }

    func formatBundleDisplayVersion(
        _ bundleDisplayVersion: String,
        withBundleVersion bundleVersion: String,
        matchingUpdate: SUAppcastItem?
    ) -> String {
        version.fullVersion
    }
}
