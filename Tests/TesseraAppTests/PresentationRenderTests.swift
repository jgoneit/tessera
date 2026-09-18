import AppKit
import SwiftUI
import Testing
import TesseraCore
@testable import TesseraApp

/// Optional, offscreen native rendering for visual review. No app is activated,
/// no hotkeys are registered, and the user's defaults are never changed.
@Suite("Presentation rendering", .serialized)
@MainActor
struct PresentationRenderTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TESSERA_UI_PREVIEW_DIR"] != nil))
    func settingsInBothLanguagesAndAppearances() throws {
        let path = try #require(ProcessInfo.processInfo.environment["TESSERA_UI_PREVIEW_DIR"])
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        _ = NSApplication.shared
        for language in [AppLanguage.en, .ko] {
            let suite = "Tessera.render.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let preferences = Preferences(defaults: defaults)
            preferences.language = language
            let coordinator = AppCoordinator(preferences: preferences)
            for theme in [AppTheme.light, .dark] {
                preferences.theme = theme
                let scheme: ColorScheme = theme == .dark ? .dark : .light
                let content = SettingsView(coordinator: coordinator, preferences: preferences)
                    .environment(\.colorScheme, scheme)
                    .environment(\.locale, Locale(identifier: language.rawValue))
                try render(content, size: CGSize(width: 680, height: 1320), theme: theme,
                    to: directory.appendingPathComponent("settings-\(language.rawValue)-\(theme.rawValue).png"))
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["TESSERA_UI_PREVIEW_DIR"] != nil))
    func selectorsAndFeedback() throws {
        let path = try #require(ProcessInfo.processInfo.environment["TESSERA_UI_PREVIEW_DIR"])
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        _ = NSApplication.shared
        for language in [AppLanguage.en, .ko] {
            for theme in [AppTheme.light, .dark] {
                for layout in LayoutPreset.allCases {
                    let bounds = CGRect(x: 0, y: 0, width: 1200, height: 800)
                    let target: PlacementTarget = layout == .twoByTwo ? .zone(4) : .column(2)
                    let frame = try GridGeometry.frame(in: bounds, layout: layout, target: target, gap: 8, scale: 1)
                    let model = ZoneSelectionModel(navigation: GridNavigation(
                        layout: layout, windowFrame: frame, visibleFrame: bounds, gap: 8, scale: 1))
                    model.status = L10n.text("Use arrow keys to move the window.", language: language)
                    let view = ZoneSelectorView(model: model, appName: "TextEdit", displayName: "Built-in Retina Display",
                        gridSize: CGSize(width: 540, height: 360), language: language, onSelect: { _ in })
                        .environment(\.colorScheme, theme == .dark ? .dark : .light)
                        .background(TesseraDesign.canvas)
                    try render(view, size: CGSize(width: 580, height: 546), theme: theme,
                        to: directory.appendingPathComponent("selector-\(layout.rawValue)-\(language.rawValue)-\(theme.rawValue).png"))
                }
                let feedback = PlacementFeedbackView(message: L10n.text(
                    "The window did not accept the exact requested size or position. It remains within the usable display area.", language: language),
                    width: 440, language: language)
                    .environment(\.colorScheme, theme == .dark ? .dark : .light)
                    .background(TesseraDesign.canvas)
                try render(feedback, size: CGSize(width: 440, height: 112), theme: theme,
                    to: directory.appendingPathComponent("feedback-\(language.rawValue)-\(theme.rawValue).png"))
            }
        }
    }

    private func render<V: View>(_ view: V, size: CGSize, theme: AppTheme, to url: URL) throws {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        host.appearance = NSAppearance(named: theme == .dark ? .darkAqua : .aqua)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        #expect(png.count > 1_000)
        try png.write(to: url)
        window.contentView = nil
        window.close()
    }
}
