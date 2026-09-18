import Combine
import Foundation
import TesseraCore

@MainActor
final class Preferences: ObservableObject {
    static let supportedGaps = [0, 4, 8, 12]
    static let supportedLayouts: [LayoutPreset] = [.twoByTwo, .threeByTwo, .fourByTwo]

    @Published private(set) var enabledLayouts: [LayoutPreset]

    @Published var gap: Int {
        didSet {
            if !Self.supportedGaps.contains(gap) { gap = 8 }
            defaults.set(gap, forKey: Keys.gap)
        }
    }

    @Published private(set) var directionalShortcuts: DirectionalShortcuts

    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Keys.language) }
    }

    @Published var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: Keys.theme) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let enabledLayouts = "tessera.enabledLayouts.v1"
        static let legacyLayout = "tessera.defaultLayout"
        static let gap = "tessera.gap"
        static let directionalShortcuts = "tessera.directionalShortcuts.v2"
        static let legacyShortcut = "tessera.globalShortcut"
        static let language = "tessera.language.v1"
        static let theme = "tessera.theme.v1"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = L10n.savedLanguage(defaults: defaults)
        theme = (defaults.object(forKey: Keys.theme) as? String).flatMap(AppTheme.init(rawValue:)) ?? .system
        if let stored = defaults.object(forKey: Keys.enabledLayouts) {
            if let values = stored as? [String], !values.isEmpty {
                let decoded = values.compactMap(LayoutPreset.init(rawValue:))
                enabledLayouts = decoded.count == values.count
                    ? Self.supportedLayouts.filter(decoded.contains) : [.threeByTwo]
            } else {
                enabledLayouts = [.threeByTwo]
            }
        } else if let raw = defaults.object(forKey: Keys.legacyLayout) as? String,
                  let legacy = LayoutPreset(rawValue: raw) {
            enabledLayouts = [legacy]
        } else {
            enabledLayouts = [.threeByTwo]
        }
        if let number = defaults.object(forKey: Keys.gap) as? NSNumber,
           CFGetTypeID(number) != CFBooleanGetTypeID(),
           let storedGap = Int(exactly: number.doubleValue),
           Self.supportedGaps.contains(storedGap) {
            gap = storedGap
        } else {
            gap = 8
        }
        if let data = defaults.data(forKey: Keys.directionalShortcuts),
           let stored = try? JSONDecoder().decode(DirectionalShortcuts.self, from: data),
           stored.validationMessage == nil {
            directionalShortcuts = stored
        } else {
            directionalShortcuts = .default
        }
        // The old single key cannot express four directions. Migrate to the
        // new defaults while preserving layout/gap, and normalize corrupt v2 data.
        if let data = try? JSONEncoder().encode(directionalShortcuts) {
            defaults.set(data, forKey: Keys.directionalShortcuts)
        }
        defaults.removeObject(forKey: Keys.legacyShortcut)
        defaults.set(language.rawValue, forKey: Keys.language)
        defaults.set(theme.rawValue, forKey: Keys.theme)
        persistLayouts()
    }

    func isLayoutEnabled(_ layout: LayoutPreset) -> Bool { enabledLayouts.contains(layout) }

    func setLayout(_ layout: LayoutPreset, enabled: Bool) {
        guard enabled != isLayoutEnabled(layout) else { return }
        if enabled {
            enabledLayouts = Self.supportedLayouts.filter { $0 == layout || enabledLayouts.contains($0) }
        } else {
            guard enabledLayouts.count > 1 else { return }
            enabledLayouts.removeAll { $0 == layout }
        }
        persistLayouts()
    }

    private func persistLayouts() {
        defaults.set(enabledLayouts.map(\.rawValue), forKey: Keys.enabledLayouts)
        defaults.removeObject(forKey: Keys.legacyLayout)
    }

    // The caller registers the complete candidate successfully before committing it.
    func setDirectionalShortcuts(_ bindings: DirectionalShortcuts) {
        guard bindings.validationMessage == nil,
              let data = try? JSONEncoder().encode(bindings) else { return }
        directionalShortcuts = bindings
        defaults.set(data, forKey: Keys.directionalShortcuts)
    }
}
