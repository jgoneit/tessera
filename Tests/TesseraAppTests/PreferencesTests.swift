import AppKit
import Carbon
import Foundation
import Testing
import TesseraCore
@testable import TesseraApp

@Suite("Preferences and shortcut configuration")
@MainActor
struct PreferencesTests {
    private let shortcutKey = "tessera.placementShortcuts.v3"
    private let legacyDirectionalKey = "tessera.directionalShortcuts.v2"
    private let layoutKey = "tessera.enabledLayouts.v1"
    private let legacyLayoutKey = "tessera.defaultLayout"

    @Test("Valid v2 direction keys migrate unchanged with the new Maximize default")
    func directionalMigrationPreservesCustomKeys() throws {
        try withDefaults { defaults in
            var legacy = DirectionalShortcuts.default
            legacy.left = Shortcut(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(cmdKey | shiftKey))
            defaults.set(try legacyData(legacy), forKey: legacyDirectionalKey)
            defaults.set(12, forKey: "tessera.gap")
            defaults.set([LayoutPreset.twoByTwo.rawValue, LayoutPreset.threeByTwo.rawValue], forKey: layoutKey)
            let preferences = Preferences(defaults: defaults)
            #expect(preferences.directionalShortcuts == legacy)
            #expect(preferences.directionalShortcuts.maximize == .defaultMaximize)
            #expect(preferences.maximizeMigrationPending)
            #expect(preferences.shortcutMigrationNotice == nil)
            #expect(preferences.gap == 12)
            #expect(preferences.enabledLayouts == [.twoByTwo, .threeByTwo])
            #expect(defaults.object(forKey: legacyDirectionalKey) == nil)
            preferences.setDirectionalShortcuts(preferences.directionalShortcuts)
            #expect(!preferences.maximizeMigrationPending)
            let restored = Preferences(defaults: defaults)
            #expect(restored.directionalShortcuts == legacy)
            #expect(!restored.maximizeMigrationPending)
        }
    }

    @Test("An interrupted migration retains fallback eligibility until registration succeeds")
    func interruptedMigrationRemainsPending() throws {
        try withDefaults { defaults in
            var legacy = DirectionalShortcuts.default
            legacy.left = Shortcut(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(cmdKey))
            defaults.set(try legacyData(legacy), forKey: legacyDirectionalKey)
            let firstLaunch = Preferences(defaults: defaults)
            #expect(firstLaunch.maximizeMigrationPending)
            // No setDirectionalShortcuts call: startup registration failed or
            // the process ended before completing its first registration.
            let nextLaunch = Preferences(defaults: defaults)
            #expect(nextLaunch.maximizeMigrationPending)
            #expect(nextLaunch.directionalShortcuts == legacy)
            var registeredFallback = nextLaunch.directionalShortcuts
            registeredFallback.maximize = nil
            nextLaunch.setDirectionalShortcuts(registeredFallback)
            let completed = Preferences(defaults: defaults)
            #expect(!completed.maximizeMigrationPending)
            #expect(completed.directionalShortcuts == registeredFallback)
        }
    }

    @Test("Successfully applying the unchanged set completes first-startup migration")
    func unchangedSuccessfulRegistrationCompletesMigration() throws {
        try withDefaults { defaults in
            let preferences = Preferences(defaults: defaults)
            #expect(preferences.maximizeMigrationPending)
            preferences.setDirectionalShortcuts(preferences.directionalShortcuts)
            #expect(!preferences.maximizeMigrationPending)
            #expect(!Preferences(defaults: defaults).maximizeMigrationPending)
        }
    }

    @Test("An existing Return chord remains assigned to its direction during migration")
    func internalMigrationConflictLeavesMaximizeUnassigned() throws {
        try withDefaults { defaults in
            var legacy = DirectionalShortcuts.default
            legacy.right = .defaultMaximize
            defaults.set(try legacyData(legacy), forKey: legacyDirectionalKey)
            let preferences = Preferences(defaults: defaults)
            #expect(preferences.directionalShortcuts.right == .defaultMaximize)
            #expect(preferences.directionalShortcuts.maximize == nil)
            #expect(preferences.directionalShortcuts.validationMessage == nil)
            #expect(preferences.shortcutMigrationNotice != nil)
            let restored = Preferences(defaults: defaults)
            #expect(restored.directionalShortcuts == preferences.directionalShortcuts)
            #expect(restored.directionalShortcuts.maximize == nil)
        }
    }

    @Test("An unassigned or custom Maximize survives restart")
    func optionalMaximizePersistence() throws {
        try withDefaults { defaults in
            let preferences = Preferences(defaults: defaults)
            for shortcut in [nil, Shortcut(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(cmdKey | optionKey))] {
                var bindings = preferences.directionalShortcuts
                bindings.maximize = shortcut
                preferences.setDirectionalShortcuts(bindings)
                #expect(Preferences(defaults: defaults).directionalShortcuts == bindings)
            }
        }
    }

    @Test("The current schema ignores stale direction data even when malformed")
    func presentCurrentSchemaWins() throws {
        try withDefaults { defaults in
            var legacy = DirectionalShortcuts.default
            legacy.left = Shortcut(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(cmdKey))
            defaults.set(try legacyData(legacy), forKey: legacyDirectionalKey)
            defaults.set("bad", forKey: shortcutKey)
            let preferences = Preferences(defaults: defaults)
            #expect(preferences.directionalShortcuts == .default)
            #expect(!preferences.maximizeMigrationPending)
            #expect(defaults.object(forKey: legacyDirectionalKey) == nil)
        }
    }

    @Test("Invalid v2 data recovers to five usable defaults")
    func invalidLegacyDirectionsRecover() throws {
        try withDefaults { defaults in
            var duplicate = DirectionalShortcuts.default
            duplicate.left = duplicate.right
            let invalidData = [Data("not JSON".utf8), try legacyData(duplicate)]
            for data in invalidData {
                defaults.removeObject(forKey: shortcutKey)
                defaults.set(data, forKey: legacyDirectionalKey)
                let preferences = Preferences(defaults: defaults)
                #expect(preferences.directionalShortcuts == .default)
                #expect(preferences.maximizeMigrationPending)
            }
        }
    }

    @Test("A new installation has usable directional defaults")
    func freshDefaults() throws {
        try withDefaults { defaults in
            let preferences = Preferences(defaults: defaults)
            #expect(preferences.enabledLayouts == [.threeByTwo])
            #expect(defaults.stringArray(forKey: layoutKey) == [LayoutPreset.threeByTwo.rawValue])
            #expect(preferences.gap == 8)
            #expect(preferences.directionalShortcuts == .default)
            #expect(preferences.directionalShortcuts.validationMessage == nil)
            let stored = try #require(defaults.data(forKey: shortcutKey))
            #expect(try JSONDecoder().decode(DirectionalShortcuts.self, from: stored) == .default)
        }
    }

    @Test("All five shortcuts and layout settings survive a fresh model")
    func persistenceAcrossInstances() throws {
        try withDefaults { defaults in
            let preferences = Preferences(defaults: defaults)
            let bindings = DirectionalShortcuts(
                left: Shortcut(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(cmdKey | shiftKey)),
                right: Shortcut(keyCode: UInt32(kVK_ANSI_H), modifiers: UInt32(cmdKey | shiftKey)),
                up: Shortcut(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(cmdKey | shiftKey)),
                down: Shortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey | shiftKey))
            )
            preferences.setLayout(.fourByTwo, enabled: true)
            preferences.setLayout(.threeByTwo, enabled: false)
            preferences.setDirectionalShortcuts(bindings)
            for gap in [0, 4, 8, 12] {
                preferences.gap = gap
                let restored = Preferences(defaults: defaults)
                #expect(restored.enabledLayouts == [.fourByTwo])
                #expect(restored.gap == gap)
                #expect(restored.directionalShortcuts == bindings)
            }
        }
    }

    @Test("The old single key migrates to placement defaults without resetting layout or gap")
    func legacyShortcutMigration() throws {
        try withDefaults { defaults in
            let legacy = Shortcut(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(cmdKey | shiftKey))
            defaults.set(try JSONEncoder().encode(legacy), forKey: "tessera.globalShortcut")
            defaults.set(LayoutPreset.fourByTwo.rawValue, forKey: "tessera.defaultLayout")
            defaults.set(12, forKey: "tessera.gap")
            let preferences = Preferences(defaults: defaults)
            #expect(preferences.directionalShortcuts == .default)
            #expect(preferences.enabledLayouts == [.fourByTwo])
            #expect(preferences.gap == 12)
            #expect(defaults.object(forKey: "tessera.globalShortcut") == nil)
            #expect(Preferences(defaults: defaults).directionalShortcuts == .default)
        }
    }

    @Test("Valid v3 shortcuts take precedence over stale legacy values")
    func currentSchemaWinsDuringMigration() throws {
        try withDefaults { defaults in
            var bindings = DirectionalShortcuts.default
            bindings.left = Shortcut(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(cmdKey))
            defaults.set(try JSONEncoder().encode(bindings), forKey: shortcutKey)
            defaults.set(try JSONEncoder().encode(Shortcut.default), forKey: "tessera.globalShortcut")
            #expect(Preferences(defaults: defaults).directionalShortcuts == bindings)
            #expect(defaults.object(forKey: "tessera.globalShortcut") == nil)
        }
    }

    @Test("Unknown and incorrectly typed legacy layouts recover to the default")
    func malformedLegacyLayouts() throws {
        try withDefaults { defaults in
            let invalidValues: [Any] = ["fiveByThree", 42, false, ["threeByTwo"]]
            for value in invalidValues {
                defaults.removeObject(forKey: layoutKey)
                defaults.set(value, forKey: legacyLayoutKey)
                #expect(Preferences(defaults: defaults).enabledLayouts == [.threeByTwo])
                #expect(defaults.object(forKey: legacyLayoutKey) == nil)
            }
        }
    }

    @Test("Every nonempty layout combination persists in canonical order", arguments: 1...7)
    func allLayoutCombinations(mask: Int) throws {
        try withDefaults { defaults in
            let preferences = Preferences(defaults: defaults)
            let expected = Preferences.supportedLayouts.enumerated()
                .filter { mask & (1 << $0.offset) != 0 }.map(\.element)
            // Add requested layouts before removing the default so the set is
            // never temporarily empty, including the 2×2-only and 4×2-only cases.
            for layout in expected.reversed() { preferences.setLayout(layout, enabled: true) }
            for layout in Preferences.supportedLayouts where !expected.contains(layout) {
                preferences.setLayout(layout, enabled: false)
            }
            #expect(preferences.enabledLayouts == expected)
            #expect(defaults.stringArray(forKey: layoutKey) == expected.map(\.rawValue))
            #expect(Preferences(defaults: defaults).enabledLayouts == expected)
        }
    }

    @Test("The last enabled layout cannot be removed", arguments: LayoutPreset.allCases)
    func preservesLastLayout(layout: LayoutPreset) throws {
        try withDefaults { defaults in
            defaults.set([layout.rawValue], forKey: layoutKey)
            let preferences = Preferences(defaults: defaults)
            preferences.setLayout(layout, enabled: false)
            #expect(preferences.enabledLayouts == [layout])
            #expect(preferences.isLayoutEnabled(layout))
            #expect(defaults.stringArray(forKey: layoutKey) == [layout.rawValue])
            #expect(Preferences(defaults: defaults).enabledLayouts == [layout])
        }
    }

    @Test("A valid legacy layout migrates once to a singleton", arguments: LayoutPreset.allCases)
    func migratesLegacyLayout(layout: LayoutPreset) throws {
        try withDefaults { defaults in
            defaults.set(layout.rawValue, forKey: legacyLayoutKey)
            let preferences = Preferences(defaults: defaults)
            #expect(preferences.enabledLayouts == [layout])
            #expect(defaults.stringArray(forKey: layoutKey) == [layout.rawValue])
            #expect(defaults.object(forKey: legacyLayoutKey) == nil)
            #expect(Preferences(defaults: defaults).enabledLayouts == [layout])
        }
    }

    @Test("A present layout list wins over stale legacy data")
    func currentLayoutsOverrideLegacy() throws {
        try withDefaults { defaults in
            defaults.set(LayoutPreset.threeByTwo.rawValue, forKey: legacyLayoutKey)
            defaults.set([LayoutPreset.fourByTwo.rawValue, LayoutPreset.twoByTwo.rawValue], forKey: layoutKey)
            #expect(Preferences(defaults: defaults).enabledLayouts == [.twoByTwo, .fourByTwo])
            #expect(defaults.object(forKey: legacyLayoutKey) == nil)
        }
    }

    @Test("Duplicate stored layouts are deduplicated and persisted in canonical order")
    func deduplicatesStoredLayouts() throws {
        try withDefaults { defaults in
            defaults.set([
                LayoutPreset.fourByTwo.rawValue, LayoutPreset.threeByTwo.rawValue,
                LayoutPreset.twoByTwo.rawValue, LayoutPreset.fourByTwo.rawValue,
                LayoutPreset.twoByTwo.rawValue,
            ], forKey: layoutKey)
            #expect(Preferences(defaults: defaults).enabledLayouts == Preferences.supportedLayouts)
            #expect(defaults.stringArray(forKey: layoutKey) == Preferences.supportedLayouts.map(\.rawValue))
        }
    }

    @Test("Malformed present layout storage resets the whole set without using legacy data")
    func malformedCurrentLayouts() throws {
        try withDefaults { defaults in
            let invalidValues: [Any] = [
                "threeByTwo", 42, false, [String](), ["unknown"],
                [LayoutPreset.twoByTwo.rawValue, "unknown"],
                [LayoutPreset.threeByTwo.rawValue, 3] as [Any],
                ["layout": LayoutPreset.fourByTwo.rawValue], Data("[]".utf8),
            ]
            for value in invalidValues {
                defaults.set(LayoutPreset.fourByTwo.rawValue, forKey: legacyLayoutKey)
                defaults.set(value, forKey: layoutKey)
                #expect(Preferences(defaults: defaults).enabledLayouts == [.threeByTwo])
                #expect(defaults.stringArray(forKey: layoutKey) == [LayoutPreset.threeByTwo.rawValue])
                #expect(defaults.object(forKey: legacyLayoutKey) == nil)
            }
        }
    }

    @Test("Repeated enable and disable requests do not duplicate layouts")
    func layoutAssignmentsAreIdempotent() throws {
        try withDefaults { defaults in
            let preferences = Preferences(defaults: defaults)
            preferences.setLayout(.threeByTwo, enabled: true)
            preferences.setLayout(.twoByTwo, enabled: false)
            preferences.setLayout(.fourByTwo, enabled: true)
            preferences.setLayout(.fourByTwo, enabled: true)
            #expect(preferences.enabledLayouts == [.threeByTwo, .fourByTwo])
            preferences.setLayout(.fourByTwo, enabled: false)
            preferences.setLayout(.fourByTwo, enabled: false)
            #expect(preferences.enabledLayouts == [.threeByTwo])
        }
    }

    @Test("Unsupported values and incorrect gap types recover without crashing")
    func malformedGaps() throws {
        try withDefaults { defaults in
            let invalidValues: [Any] = [-4, 3, 16, "4", 4.5, false, [8]]
            for value in invalidValues {
                defaults.set(value, forKey: "tessera.gap")
                #expect(Preferences(defaults: defaults).gap == 8, "Invalid stored gap: \(String(describing: value))")
            }
        }
    }

    @Test("An unsupported gap assignment restores and persists the safe default")
    func invalidGapAssignment() throws {
        try withDefaults { defaults in
            let preferences = Preferences(defaults: defaults)
            preferences.gap = 12
            preferences.gap = -1
            #expect(preferences.gap == 8)
            #expect(Preferences(defaults: defaults).gap == 8)
        }
    }

    @Test("Malformed or partial v3 shortcut storage recovers as one complete set")
    func malformedShortcutStorage() throws {
        try withDefaults { defaults in
            let invalidValues: [Any] = [
                "not data", 123, false, ["left": 49],
                Data("not JSON".utf8), Data("[]".utf8),
                Data("{\"left\":{\"keyCode\":123,\"modifiers\":6144}}".utf8),
                Data("{\"keyCode\":49,\"modifiers\":6144}".utf8),
            ]
            for value in invalidValues {
                defaults.set(value, forKey: shortcutKey)
                #expect(Preferences(defaults: defaults).directionalShortcuts == .default)
                let repaired = try #require(defaults.data(forKey: shortcutKey))
                #expect(try JSONDecoder().decode(DirectionalShortcuts.self, from: repaired) == .default)
            }
        }
    }

    @Test("Any invalid or duplicate stored direction resets the complete set")
    func invalidStoredShortcuts() throws {
        try withDefaults { defaults in
            var invalidSets = invalidShortcuts.map { shortcut in
                var bindings = DirectionalShortcuts.default
                bindings.left = shortcut
                return bindings
            }
            var duplicate = DirectionalShortcuts.default
            duplicate.up = duplicate.down
            invalidSets.append(duplicate)
            for bindings in invalidSets {
                defaults.set(try JSONEncoder().encode(bindings), forKey: shortcutKey)
                #expect(Preferences(defaults: defaults).directionalShortcuts == .default)
            }
        }
    }

    @Test("An invalid or duplicate replacement cannot overwrite saved bindings")
    func invalidShortcutDoesNotReplaceSavedValue() throws {
        try withDefaults { defaults in
            let preferences = Preferences(defaults: defaults)
            var saved = DirectionalShortcuts.default
            saved.left = Shortcut(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(controlKey))
            preferences.setDirectionalShortcuts(saved)
            var invalidSets = invalidShortcuts.map { shortcut in
                var bindings = saved
                bindings.left = shortcut
                return bindings
            }
            var duplicate = saved
            duplicate.left = duplicate.right
            invalidSets.append(duplicate)
            for bindings in invalidSets {
                preferences.setDirectionalShortcuts(bindings)
                #expect(preferences.directionalShortcuts == saved)
                #expect(Preferences(defaults: defaults).directionalShortcuts == saved)
            }
        }
    }

    @Test("Swapping two directions persists as a complete valid replacement")
    func swappingDirections() throws {
        try withDefaults { defaults in
            let preferences = Preferences(defaults: defaults)
            var swapped = preferences.directionalShortcuts
            let previousLeft = swapped.left
            swapped.left = swapped.right
            swapped.right = previousLeft
            preferences.setDirectionalShortcuts(swapped)
            #expect(preferences.directionalShortcuts == swapped)
            #expect(Preferences(defaults: defaults).directionalShortcuts == swapped)
        }
    }

    @Test("A global shortcut requires a supported key and a command modifier")
    func shortcutValidation() {
        for shortcut in invalidShortcuts {
            #expect(shortcut.validationMessage != nil)
        }
        for modifiers in [cmdKey, controlKey, optionKey, controlKey | optionKey | shiftKey] {
            let shortcut = Shortcut(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(modifiers))
            #expect(shortcut.validationMessage == nil)
        }
        for keyCode in [kVK_Space, kVK_LeftArrow, kVK_F1, kVK_ANSI_Keypad1] {
            let shortcut = Shortcut(keyCode: UInt32(keyCode), modifiers: UInt32(controlKey))
            #expect(shortcut.validationMessage == nil)
        }
    }

    @Test("Displayed bindings use stable physical-key labels and modifier order")
    func shortcutDisplay() {
        #expect(Shortcut.default.displayString == "⌃⌥" + L10n.text("Space"))
        let allModifiers = Shortcut(
            keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey)
        )
        #expect(allModifiers.displayString == "⌃⌥⇧⌘G")
        let arrow = Shortcut(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(cmdKey))
        #expect(arrow.displayString == "⌘←")
    }

    @Test("Recording uses physical key codes independently of Korean text input")
    func eventUsesPhysicalKey() throws {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .option, .capsLock, .function],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "ㅎ",
            charactersIgnoringModifiers: "ㅎ",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_G)
        ))
        let shortcut = Shortcut(event: event)
        #expect(shortcut.keyCode == UInt32(kVK_ANSI_G))
        #expect(shortcut.modifiers == UInt32(cmdKey | optionKey))
        #expect(shortcut.displayString == "⌥⌘G")
        #expect(shortcut.validationMessage == nil)
    }

    private func legacyData(_ shortcuts: DirectionalShortcuts) throws -> Data {
        try JSONEncoder().encode([
            "left": shortcuts.left, "right": shortcuts.right,
            "up": shortcuts.up, "down": shortcuts.down,
        ])
    }

    private var invalidShortcuts: [Shortcut] {
        [
            Shortcut(keyCode: UInt32(kVK_ANSI_G), modifiers: 0),
            Shortcut(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(shiftKey)),
            Shortcut(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(cmdKey | alphaLock)),
            Shortcut(keyCode: UInt32(kVK_Command), modifiers: UInt32(cmdKey)),
            Shortcut(keyCode: UInt32(kVK_Escape), modifiers: UInt32(controlKey)),
            Shortcut(keyCode: UInt32.max, modifiers: UInt32(optionKey)),
        ]
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let domain = "TesseraTests.Preferences.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        try body(defaults)
    }
}
