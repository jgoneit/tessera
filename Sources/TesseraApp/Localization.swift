import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case en
    case ko

    var id: String { rawValue }
}

enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }
}

/// Resolves language per call so AX work and UI rendering do not share mutable
/// locale state. Explicit language arguments also keep previews and tests isolated.
enum L10n {
    static func text(_ key: String, language: AppLanguage? = nil) -> String {
        let resolved = resolvedLanguage(language ?? savedLanguage())
        return localizedText(key, language: resolved)
            ?? localizedText(key, language: .en)
            ?? key
    }

    static func format(_ key: String, _ arguments: CVarArg..., language: AppLanguage? = nil) -> String {
        let resolved = resolvedLanguage(language ?? savedLanguage())
        // These formats contain counts and error identifiers, not localized
        // measurements. Preserve digits verbatim: -25204 must not become -25,204.
        return String(format: text(key, language: resolved), arguments: arguments)
    }

    static func savedLanguage(defaults: UserDefaults = .standard) -> AppLanguage {
        (defaults.object(forKey: "tessera.language.v1") as? String).flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    /// The first supported language wins; an unsupported preference list falls
    /// back to English. Regional forms such as ko-KR and en_US are supported.
    static func resolvedLanguage(
        _ language: AppLanguage,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> AppLanguage {
        guard language == .system else { return language }
        for identifier in preferredLanguages {
            let base = identifier.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first
            if base == "ko" { return .ko }
            if base == "en" { return .en }
        }
        return .en
    }

    static func resourceURL(for language: AppLanguage) -> URL? {
        Bundle.module.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: language.rawValue)
    }

    private static func localizedText(_ key: String, language: AppLanguage) -> String? {
        guard let url = resourceURL(for: language),
              let bundle = Bundle(url: url.deletingLastPathComponent()) else { return nil }
        let missing = "\u{1}TesseraMissingLocalization\u{1}"
        let value = bundle.localizedString(forKey: key, value: missing, table: "Localizable")
        return value == missing ? nil : value
    }
}
