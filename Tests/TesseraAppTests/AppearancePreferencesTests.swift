import Carbon
import Foundation
import Testing
import TesseraCore
@testable import TesseraApp

@Suite("Appearance and language preferences")
@MainActor
struct AppearancePreferencesTests {
    @Test("Fresh preferences follow the system and normalize storage")
    func defaultsFollowSystem() throws {
        try withDefaults { defaults in
            let preferences = Preferences(defaults: defaults)
            #expect(preferences.language == .system)
            #expect(preferences.theme == .system)
            #expect(defaults.string(forKey: "tessera.language.v1") == "system")
            #expect(defaults.string(forKey: "tessera.theme.v1") == "system")
        }
    }

    @Test("Every language and theme combination survives a fresh model",
          arguments: AppLanguage.allCases, AppTheme.allCases)
    func persistsSelections(language: AppLanguage, theme: AppTheme) throws {
        try withDefaults { defaults in
            let preferences = Preferences(defaults: defaults)
            preferences.language = language
            preferences.theme = theme
            let restored = Preferences(defaults: defaults)
            #expect(restored.language == language)
            #expect(restored.theme == theme)
            #expect(defaults.string(forKey: "tessera.language.v1") == language.rawValue)
            #expect(defaults.string(forKey: "tessera.theme.v1") == theme.rawValue)
        }
    }

    @Test("Corrupt language or theme storage recovers independently")
    func invalidStorageFallsBackToSystem() throws {
        try withDefaults { defaults in
            let invalidValues: [Any] = ["unsupported", "", "ko-KR", 1, true, ["system"], Data("en".utf8)]
            for value in invalidValues {
                defaults.set(value, forKey: "tessera.language.v1")
                defaults.set("dark", forKey: "tessera.theme.v1")
                let badLanguage = Preferences(defaults: defaults)
                #expect(badLanguage.language == .system)
                #expect(badLanguage.theme == .dark)
                #expect(defaults.string(forKey: "tessera.language.v1") == "system")

                defaults.set("ko", forKey: "tessera.language.v1")
                defaults.set(value, forKey: "tessera.theme.v1")
                let badTheme = Preferences(defaults: defaults)
                #expect(badTheme.language == .ko)
                #expect(badTheme.theme == .system)
                #expect(defaults.string(forKey: "tessera.theme.v1") == "system")
            }
        }
    }

    @Test("Appearance changes preserve layout, gap, and directional shortcuts")
    func preservesExistingPreferences() throws {
        try withDefaults { defaults in
            let preferences = Preferences(defaults: defaults)
            preferences.setLayout(.twoByTwo, enabled: true)
            preferences.setLayout(.fourByTwo, enabled: true)
            preferences.setLayout(.threeByTwo, enabled: false)
            preferences.gap = 12
            var bindings = DirectionalShortcuts.default
            bindings.left = Shortcut(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(cmdKey | controlKey))
            preferences.setDirectionalShortcuts(bindings)

            preferences.language = .ko
            preferences.theme = .dark
            let restored = Preferences(defaults: defaults)
            #expect(restored.enabledLayouts == [.twoByTwo, .fourByTwo])
            #expect(restored.gap == 12)
            #expect(restored.directionalShortcuts == bindings)
            #expect(restored.language == .ko)
            #expect(restored.theme == .dark)
        }
    }

    @Test("Preference identities are stable persistence values")
    func stableIdentities() {
        #expect(AppLanguage.allCases.map(\.id) == ["system", "en", "ko"])
        #expect(AppTheme.allCases.map(\.id) == ["system", "light", "dark"])
    }

    private func withDefaults(_ operation: (UserDefaults) throws -> Void) throws {
        let name = "TesseraAppearancePreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try operation(defaults)
    }
}
