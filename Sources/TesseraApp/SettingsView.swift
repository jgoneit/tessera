import SwiftUI
import TesseraCore

// Resolve the property wrapper on SDKs that also declare a State macro.
private typealias SettingsState<Value> = SwiftUI.State<Value>

struct SettingsView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var preferences: Preferences
    @SettingsState private var draftShortcuts: DirectionalShortcuts
    @SettingsState private var shortcutsExpanded: Bool

    init(coordinator: AppCoordinator, preferences: Preferences) {
        self.coordinator = coordinator
        self.preferences = preferences
        _draftShortcuts = SettingsState(initialValue: preferences.directionalShortcuts)
        _shortcutsExpanded = SettingsState(initialValue: !coordinator.shortcutsActive || coordinator.shortcutError != nil)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                permissionCard
                layoutCard
                appearanceCard
                shortcutsCard
                guidance
                statusFooter
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(TesseraDesign.canvas)
        .onChange(of: preferences.directionalShortcuts) { _, bindings in
            draftShortcuts = bindings
        }
        .onChange(of: coordinator.shortcutError) { _, error in
            if error != nil { shortcutsExpanded = true }
        }
        .onChange(of: coordinator.shortcutsActive) { _, active in
            if !active { shortcutsExpanded = true }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(nsImage: AppIcon.image)
                .resizable().scaledToFit().frame(width: 48, height: 48)
                .accessibilityHidden(true)
            Text("Tessera").font(.system(size: 22, weight: .semibold))
            Spacer(minLength: 8)
            Text("v0.1")
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(.quaternary, in: Capsule())
        }
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var permissionCard: some View {
        if coordinator.permissionGranted {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.accentColor.opacity(0.8))
                    .accessibilityHidden(true)
                Text(t("Ready to arrange windows"))
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                permissionActions
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        } else {
            TesseraSurface(padding: 16) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 38, height: 38)
                        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t("Permission required"))
                            .font(.callout.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(t("Allow Tessera to move and resize windows."))
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    permissionActions
                }
            }
        }
    }

    private var permissionActions: some View {
        HStack(spacing: 8) {
            Button(t("Open Settings")) { coordinator.openAccessibilitySettings() }
                .accessibilityLabel(t("Open Accessibility Settings"))
                .help(t("Open Accessibility Settings"))
            Button { coordinator.refreshPermission() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel(t("Check Again"))
            .help(t("Check Again"))
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var layoutCard: some View {
        TesseraSurface {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeading("Layouts", subtitle: "Choose the grids you want to move through.")
                HStack(spacing: 12) {
                    ForEach(Preferences.supportedLayouts) { layout in
                        layoutToggle(layout)
                    }
                }
                Text(t("Keep at least one layout enabled."))
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                HStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t("Window spacing")).font(.callout.weight(.medium))
                        Text(t("Space between windows and screen edges."))
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Picker(t("Window spacing"), selection: $preferences.gap) {
                        ForEach(Preferences.supportedGaps, id: \.self) { gap in
                            Text("\(gap) pt").tag(gap)
                        }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 236)
                    .accessibilityLabel(t("Window spacing"))
                }
            }
        }
    }

    private func layoutToggle(_ layout: LayoutPreset) -> some View {
        let selected = preferences.isLayoutEnabled(layout)
        let required = selected && preferences.enabledLayouts.count == 1
        return Toggle(isOn: Binding(
            get: { preferences.isLayoutEnabled(layout) },
            set: { preferences.setLayout(layout, enabled: $0) })) {
            VStack(spacing: 12) {
                SettingsGridPreview(layout: layout, selected: selected)
                    .frame(height: 48).accessibilityHidden(true)
                HStack {
                    Text(layout.title).font(.callout.weight(.semibold))
                    Spacer(minLength: 4)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .toggleStyle(.button)
        .buttonStyle(SettingsLayoutButtonStyle(selected: selected))
        .disabled(required)
        .accessibilityLabel(layout.title)
        .accessibilityHint(required ? t("Keep at least one layout enabled.") : "")
        .help(required ? t("Keep at least one layout enabled.") : layout.title)
    }

    private var appearanceCard: some View {
        TesseraSurface(padding: 16) {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeading("Appearance")
                HStack {
                    Label(t("Theme"), systemImage: "circle.lefthalf.filled")
                        .font(.callout)
                    Spacer()
                    Picker(t("Theme"), selection: Binding(
                        get: { preferences.theme },
                        set: { coordinator.shortcutRecorder.cancelRecording(); preferences.theme = $0 })) {
                        Text(t("System")).tag(AppTheme.system)
                        Text(t("Light")).tag(AppTheme.light)
                        Text(t("Dark")).tag(AppTheme.dark)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 260)
                    .accessibilityLabel(t("Theme"))
                }
                Divider()
                HStack {
                    Label(t("Language"), systemImage: "globe")
                        .font(.callout)
                    Spacer()
                    Picker(t("Language"), selection: Binding(
                        get: { preferences.language },
                        set: { coordinator.shortcutRecorder.cancelRecording(); preferences.language = $0 })) {
                        Text(t("System")).tag(AppLanguage.system)
                        Text("한국어").tag(AppLanguage.ko)
                        Text("English").tag(AppLanguage.en)
                    }
                    .pickerStyle(.menu).labelsHidden().frame(width: 180)
                    .accessibilityLabel(t("Language"))
                }
            }
        }
    }

    private var shortcutsCard: some View {
        TesseraSurface(padding: 0) {
            DisclosureGroup(isExpanded: Binding(
                get: { shortcutsExpanded },
                set: { expanded in
                    if !expanded { coordinator.shortcutRecorder.cancelRecording() }
                    shortcutsExpanded = expanded
                })) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(t("Move the active window without leaving your app."))
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 0) {
                        shortcutRow(.left, title: "Move left", symbol: "arrow.left")
                        Divider()
                        shortcutRow(.right, title: "Move right", symbol: "arrow.right")
                        Divider()
                        shortcutRow(.up, title: "Move up", symbol: "arrow.up")
                        Divider()
                        shortcutRow(.down, title: "Move down", symbol: "arrow.down")
                        Divider()
                        maximizeShortcutRow
                    }
                    Text(t("Choose a different key for each action. Include ⌘, ⌃, or ⌥."))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let validation = draftShortcuts.validationMessage {
                        inlineError(validation)
                    }
                    if let error = coordinator.shortcutError {
                        inlineError(error)
                    }
                    HStack {
                        Spacer(minLength: 4)
                        Button(t("Apply Shortcuts")) { coordinator.applyShortcuts(draftShortcuts) }
                            .buttonStyle(.borderedProminent)
                            .disabled(draftShortcuts.validationMessage != nil
                            || (draftShortcuts == preferences.directionalShortcuts && coordinator.shortcutsActive
                                && coordinator.shortcutError == nil))
                    }
                }
                .padding(.top, 14)
            } label: {
                HStack(spacing: 12) {
                    Text(t("Window shortcuts"))
                        .font(.system(size: 15, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 4)
                    shortcutStatus
                }
            }
            .disclosureGroupStyle(SettingsDisclosureStyle(language: preferences.language))
        }
    }

    private var shortcutStatus: some View {
        let changed = draftShortcuts != preferences.directionalShortcuts
        let key = changed ? "Changes not applied"
            : (coordinator.shortcutsActive ? "All shortcuts are active" : "Shortcuts are inactive")
        let symbol = changed ? "circle.dotted"
            : (coordinator.shortcutsActive ? "checkmark.circle" : "exclamationmark.circle")
        return Label(t(key), systemImage: symbol)
            .font(.caption)
            .foregroundStyle(coordinator.shortcutsActive || changed ? Color.secondary : Color.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func shortcutRow(_ direction: GridDirection, title: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary).frame(width: 24).accessibilityHidden(true)
            Text(t(title)).font(.callout)
            Spacer()
            ShortcutRecorder(current: draftShortcuts[direction],
                label: L10n.format("Record %@ shortcut", t(title), language: preferences.language),
                bridge: coordinator.shortcutRecorder,
                onRecord: { draftShortcuts[direction] = $0 })
                .frame(width: 174, height: 30)
        }
        .padding(.vertical, 9)
    }

    private var maximizeShortcutRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                .frame(width: 24).accessibilityHidden(true)
            Text(t("Maximize")).font(.callout)
            Spacer()
            ShortcutRecorder(current: draftShortcuts.maximize,
                label: L10n.format("Record %@ shortcut", t("Maximize"), language: preferences.language),
                bridge: coordinator.shortcutRecorder,
                onRecord: { draftShortcuts.maximize = $0 })
                .frame(width: 174, height: 30)
            Button {
                coordinator.shortcutRecorder.cancelRecording()
                draftShortcuts.maximize = nil
            } label: { Image(systemName: "xmark.circle") }
                .buttonStyle(.plain)
                .accessibilityLabel(t("Clear maximize shortcut"))
                .help(t("Clear maximize shortcut"))
                .disabled(draftShortcuts.maximize == nil)
        }
        .padding(.vertical, 9)
    }

    private var guidance: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(t("How it works")).font(.callout.weight(.semibold))
            guidanceRow(keys: "← →", title: "Left and right",
                detail: "Follow the screen order of enabled columns. Hold to repeat.")
            guidanceRow(keys: "↑ ↓", title: "Up and down",
                detail: "Move between top, full height, and bottom, one press at a time.")
            guidanceRow(keys: preferences.directionalShortcuts.maximize?.displayString ?? "—", title: "Maximize",
                detail: "Fill the usable display without gaps. Use arrows to return to the grid.")
            Text(t("Choose Arrange Window… in the menu bar to select a zone by number or click."))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    private func guidanceRow(keys: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            TesseraKeycap(keys).frame(minWidth: 48, alignment: .leading).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(t(title)).font(.caption.weight(.medium))
                Text(t(detail)).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text(t("Last action")).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text(coordinator.statusMessage).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 4)
    }

    private func sectionHeading(_ title: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(t(title)).font(.system(size: 15, weight: .semibold)).accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(t(subtitle)).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func inlineError(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.callout).foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func t(_ key: String) -> String { L10n.text(key, language: preferences.language) }
}

/// The entire header is one keyboard-accessible control, including its padding.
private struct SettingsDisclosureStyle: DisclosureGroupStyle {
    let language: AppLanguage

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                configuration.isExpanded.toggle()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        .accessibilityHidden(true)
                    configuration.label
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(L10n.text(configuration.isExpanded ? "Expanded" : "Collapsed", language: language))
            if configuration.isExpanded {
                configuration.content
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
    }
}

private struct SettingsGridPreview: View {
    let layout: LayoutPreset
    let selected: Bool

    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<layout.rows, id: \.self) { _ in
                HStack(spacing: 3) {
                    ForEach(0..<layout.columns, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(selected ? Color.accentColor.opacity(0.75) : Color.secondary.opacity(0.25))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
    }
}

private struct SettingsLayoutButtonStyle: ButtonStyle {
    @Environment(\.colorSchemeContrast) private var contrast
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(selected ? Color.accentColor.opacity(configuration.isPressed ? 0.14 : 0.07)
                : Color.primary.opacity(configuration.isPressed ? 0.07 : 0.025),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : TesseraDesign.border,
                        lineWidth: selected || contrast == .increased ? 2 : 1)
                    .allowsHitTesting(false)
            }
    }
}
