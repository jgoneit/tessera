import Foundation
import Testing
import TesseraCore
@testable import TesseraApp

@Suite("English and Korean localization")
struct LocalizationTests {
    @Test("System language uses the first supported preference")
    func resolvesSystemLanguage() {
        #expect(L10n.resolvedLanguage(.system, preferredLanguages: ["ko-KR", "en-US"]) == .ko)
        #expect(L10n.resolvedLanguage(.system, preferredLanguages: ["en-GB", "ko-KR"]) == .en)
        #expect(L10n.resolvedLanguage(.system, preferredLanguages: ["fr-FR", "KO_kr", "en"]) == .ko)
        #expect(L10n.resolvedLanguage(.system, preferredLanguages: ["fr", "ja", "en_US", "ko"]) == .en)
        #expect(L10n.resolvedLanguage(.system, preferredLanguages: ["fr-FR", "ja-JP"]) == .en)
        #expect(L10n.resolvedLanguage(.system, preferredLanguages: []) == .en)
    }

    @Test("An explicit app language overrides system preferences")
    func explicitSelectionWins() {
        #expect(L10n.resolvedLanguage(.en, preferredLanguages: ["ko-KR"]) == .en)
        #expect(L10n.resolvedLanguage(.ko, preferredLanguages: ["en-US"]) == .ko)
        #expect(L10n.text("Window arranged.", language: .en) == "Window arranged.")
        #expect(L10n.text("Window arranged.", language: .ko) == "창을 배치했습니다.")
    }

    @Test("Size-adjusted success has the approved concise wording in both languages")
    func sizeAdjustedFeedback() {
        let key = "Arranged · Adjusted to app size"
        #expect(L10n.text(key, language: .en) == key)
        #expect(L10n.text(key, language: .ko) == "배치됨 · 앱 크기에 맞춤")
    }

    @Test("Screen-wide labels describe the screen without an irrelevant grid prefix")
    func screenWideLabels() {
        let labels: [(PlacementTarget, String, String)] = [
            (.maximized, "Maximize", "최대화"),
            (.screenTop, "Top half of screen", "화면 위쪽 절반"),
            (.screenBottom, "Bottom half of screen", "화면 아래쪽 절반"),
        ]
        for layout in LayoutPreset.allCases {
            for (target, english, korean) in labels {
                let placement = GridPlacement(layout: layout, target: target)
                #expect(placement.localizedLabel(language: .en) == english)
                #expect(placement.localizedLabel(language: .ko) == korean)
            }
            #expect(GridPlacement(layout: layout, target: .column(1)).localizedLabel(language: .en)
                == "\(layout.title) · Column 1 · full height")
        }
    }

    @Test("Stored language decoding does not coerce unsupported values")
    func savedLanguageDecoding() throws {
        let name = "TesseraLocalizationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(L10n.savedLanguage(defaults: defaults) == .system)
        for language in AppLanguage.allCases {
            defaults.set(language.rawValue, forKey: "tessera.language.v1")
            #expect(L10n.savedLanguage(defaults: defaults) == language)
        }
        for value: Any in ["fr", "ko-KR", true, 1, ["ko"]] {
            defaults.set(value, forKey: "tessera.language.v1")
            #expect(L10n.savedLanguage(defaults: defaults) == .system)
        }
    }

    @Test("Both packaged catalogs have the same nonempty keys and values")
    func catalogParity() throws {
        let english = try catalog(.en)
        let korean = try catalog(.ko)
        #expect(!english.isEmpty)
        #expect(Set(english.keys) == Set(korean.keys))
        for (key, value) in english {
            #expect(value == key)
            #expect(!key.isEmpty)
            #expect(korean[key]?.isEmpty == false)
            #expect(L10n.text(key, language: .en) == value)
            #expect(L10n.text(key, language: .ko) == korean[key])
        }
    }

    @Test("Format arguments retain their count, order, and C type across languages")
    func formatPlaceholderParity() throws {
        let english = try catalog(.en)
        let korean = try catalog(.ko)
        // %% consumes no argument. Positional arguments are kept in this check
        // so a translation cannot silently change a placeholder's C type.
        let pattern = #"%(?:[0-9]+\$)?[-+#0 ]*(?:[0-9]+|\*)?(?:\.(?:[0-9]+|\*))?(?:hh|ll|[hljztL])?[@diuoxXfFeEgGaAcCsSp%]"#
        let expression = try NSRegularExpression(pattern: pattern)
        func placeholders(_ value: String) -> [String] {
            expression.matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap { match in
                guard let range = Range(match.range, in: value) else { return nil }
                let placeholder = String(value[range])
                return placeholder == "%%" ? nil : placeholder
            }
        }
        for (key, value) in english {
            #expect(placeholders(value) == placeholders(try #require(korean[key])), "Format mismatch: \(key)")
        }
    }

    @Test("Every literal L10n call in app source exists in both catalogs")
    func literalSourceKeyCoverage() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = root.appendingPathComponent("Sources/TesseraApp", isDirectory: true)
        let files = try #require(FileManager.default.enumerator(
            at: source, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]))
        let expression = try NSRegularExpression(pattern: #"\bL10n\.(?:text|format)\(\s*("(?:[^"\\]|\\.)*")"#)
        let english = try catalog(.en)
        let korean = try catalog(.ko)
        var found = Set<String>()
        for case let url as URL in files where url.pathExtension == "swift" {
            let contents = try String(contentsOf: url, encoding: .utf8)
            for match in expression.matches(in: contents, range: NSRange(contents.startIndex..., in: contents)) {
                let range = try #require(Range(match.range(at: 1), in: contents))
                let literal = String(contents[range])
                let key = try JSONDecoder().decode(String.self, from: Data(literal.utf8))
                found.insert(key)
                #expect(english[key] != nil, "Missing English key in \(url.lastPathComponent): \(key)")
                #expect(korean[key] != nil, "Missing Korean key in \(url.lastPathComponent): \(key)")
            }
        }
        #expect(!found.isEmpty)
    }

    @Test("Formatted strings substitute numbers and nested localized text")
    func formatsArguments() {
        #expect(L10n.format("Zone %d", Int32(4), language: .en) == "Zone 4")
        #expect(L10n.format("Zone %d", Int32(4), language: .ko) == "영역 4")
        #expect(L10n.format("Column %ld · full height", 2, language: .ko) == "2열 · 전체 높이")
        #expect(L10n.format("Arranging %@…", "영역 4", language: .ko) == "영역 4에 배치 중…")
        #expect(L10n.format("Could not %@ through Accessibility (%ld).", "창 이동", -25204, language: .ko)
            == "손쉬운 사용을 통해 창 이동 작업을 수행하지 못했습니다(-25204).")
    }

    @Test("A missing key falls back to its English source text")
    func missingKeyFallsBack() {
        let key = "Uncatalogued English fallback"
        #expect(L10n.text(key, language: .en) == key)
        #expect(L10n.text(key, language: .ko) == key)
    }

    private func catalog(_ language: AppLanguage) throws -> [String: String] {
        let url = try #require(L10n.resourceURL(for: language))
        #expect(url.deletingLastPathComponent().lastPathComponent == "\(language.rawValue).lproj")
        let values = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), options: [], format: nil)
        return try #require(values as? [String: String])
    }
}
