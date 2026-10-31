import DroppyKit
import SwiftUI

/// The pages in the order the user reads them.
enum TranslateSettingsPage: String, CaseIterable {
    case translation
    case display
    case permissions
    case help

    var symbol: String {
        switch self {
        case .translation: return "translate"
        case .display: return "macwindow"
        case .permissions: return "lock.shield"
        case .help: return "questionmark.circle"
        }
    }
}

// MARK: - The droplet's page

/// The droplet's page: doors to its own settings and to the rights the system
/// grants it.
struct TranslateSettings: View {
    @ObservedObject var model: TranslateModel
    /// The host's way into a page of the droplet's own.
    @Environment(\.dropletSettingsPageOpener) private var pageOpener

    var body: some View {
        DropletSettingsPane {
            DropletSettingsSection {
                iconHeader("settings.customization", symbol: "slider.horizontal.3")
            } content: {
                DropletSettingsCard {
                    pageLink(.translation)
                    pageLink(.display)
                    shortcutsRow
                }
            }

            DropletSettingsSection {
                iconHeader("settings.rights", symbol: "checkmark.shield")
            } content: {
                DropletSettingsCard {
                    pageLink(
                        .permissions,
                        summary: permissionSummaryText
                    )
                    pageLink(.help)
                }
            }
        }
        .task { model.refreshPermissions() }
    }

    /// One door to a page of the droplet's own.
    private func pageLink(
        _ page: TranslateSettingsPage,
        summary: String? = nil
    ) -> some View {
        SettingsDoorRow(
            title: L10n.tr("settings.\(page.rawValue)"),
            subtitle: L10n.tr("settings.\(page.rawValue).sub"),
            symbol: page.symbol,
            summary: summary
        ) {
            pageOpener?(page: page.rawValue, title: L10n.tr("settings.\(page.rawValue)"))
        }
    }

    /// Shortcuts live in Droppy's own page, so this door leaves the droplet
    /// instead of opening one of its pages.
    private var shortcutsRow: some View {
        SettingsDoorRow(
            title: L10n.tr("settings.shortcuts"),
            subtitle: L10n.tr("settings.shortcuts.sub"),
            symbol: "command",
            external: true
        ) {
            model.openShortcuts()
        }
        .disabled(!model.canOpenShortcuts)
    }

    /// Only shown when both are granted; anything else belongs on the
    /// permissions page, where the user can fix it.
    private var permissionSummaryText: String? {
        let states = model.permissionStates
        guard !states.isEmpty, states.allSatisfy({ $0.status == .granted }) else { return nil }
        return L10n.tr("settings.permissions.all")
    }
}

// MARK: - The translation page

struct TranslateTranslationSettings: View {
    @ObservedObject var model: TranslateModel
    @State private var isKeyVisible = false
    /// Nil on a host that cannot open a page; the guide is then part of this
    /// page.
    @Environment(\.dropletSettingsPageOpener) private var pageOpener

    var body: some View {
        DropletSettingsPage { sections }
    }

    @ViewBuilder
    var sections: some View {
        // 1. Language Pair
        DropletSettingsSection {
            iconHeader(
                "settings.section.languages",
                subtitleKey: "settings.section.languages.sub",
                symbol: "translate"
            )
        } content: {
            DropletSettingsCard {
                TranslateLanguagePairRow(model: model)
                modelsRow
            }
        }

        // 2. Translation Engine
        DropletSettingsSection {
            iconHeader(
                "settings.section.translation",
                subtitleKey: "settings.section.translation.sub",
                symbol: "cpu"
            )
        } content: {
            DropletSettingsCard {
                engineRow
                if model.translationEngine == .provider {
                    TranslatePickerRow(
                        title: L10n.tr("settings.provider"),
                        subtitle: L10n.tr("settings.provider.sub"),
                        options: TranslationProvider.aiCases,
                        label: { L10n.tr("settings.engine.\($0.rawValue)") },
                        glyph: { providerGlyph($0) },
                        isSelected: { $0 == model.translationProvider },
                        action: { model.translationProvider = $0 }
                    )
                    endpointRow
                    modelRow
                    apiKeyRow
                    keyInUseRow
                    testRow
                }
            }
        }

        Section {
            EmptyView()
        } footer: {
            privacyNote
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, DroppySpacing.xs)
        }

        // 3. Automation
        DropletSettingsSection {
            iconHeader(
                "settings.section.behavior",
                subtitleKey: "settings.section.behavior.sub",
                symbol: "bolt"
            )
        } content: {
            DropletSettingsCard {
                TranslateToggleRow(
                    title: L10n.tr("settings.live"),
                    subtitle: L10n.tr("settings.live.sub"),
                    isOn: $model.liveTranslate
                )
                TranslateToggleRow(
                    title: L10n.tr("settings.result.autoCopy"),
                    subtitle: L10n.tr("settings.result.autoCopy.sub"),
                    isOn: $model.autoCopyResult
                )
            }
        }

        // 4. Interface Language
        DropletSettingsSection {
            iconHeader(
                "settings.section.interface",
                subtitleKey: "settings.section.interface.sub",
                symbol: "globe"
            )
        } content: {
            DropletSettingsCard {
                interfaceLanguageRow
            }
        }

        Section {
            EmptyView()
        } footer: {
            resetLink
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, DroppySpacing.smd)
        }
    }

    private var engineRow: some View {
        TranslatePickerRow(
            title: L10n.tr("settings.engine"),
            subtitle: L10n.tr("settings.engine.sub"),
            infoTip: L10n.tr("settings.engine.tip"),
            options: TranslationEngine.allCases,
            label: { L10n.tr("settings.engine.\($0.rawValue)") },
            glyph: { engineGlyph($0) },
            isSelected: { $0 == model.translationEngine },
            action: { model.setTranslationEngine($0) }
        )
    }

    /// A link, not a button: a small reversible reset should not shout.
    private var resetLink: some View {
        Button(L10n.tr("settings.reset")) {
            model.resetTranslationSettings()
        }
        .buttonStyle(.link)
        .font(.callout)
        .foregroundStyle(AdaptiveColors.selectionBlueAuto)
    }

    /// A filled circle marks done, a crossed one marks not on this Mac.
    /// Unknown and unsupported get no mark, which would claim a state.
    private var pairIcon: String? {
        switch model.pairInfo {
        case .ready: return "checkmark.circle.fill"
        case .needsDownload: return "xmark.circle.fill"
        case .unknown, .unsupported: return nil
        }
    }

    private var pairIconColor: Color? {
        switch model.pairInfo {
        case .ready: return Color(nsColor: .systemGreen)
        case .needsDownload: return Color(nsColor: .secondaryLabelColor)
        case .unknown, .unsupported: return nil
        }
    }

    /// It belongs with what the droplet does, not with where the result goes.
    private var interfaceLanguageRow: some View {
        TranslatePickerRow(
            title: L10n.tr("settings.ui"),
            subtitle: L10n.tr("settings.ui.sub"),
            options: uiLanguages,
            label: { uiLanguageTitle($0) },
            glyph: { _ in "" },
            isSelected: { $0 == model.uiLanguage },
            action: { model.uiLanguage = $0 }
        )
    }

    /// Apple's engines download models per pair and per strategy; a network
    /// provider has nothing to fetch, so the row is omitted for it.
    @ViewBuilder
    private var modelsRow: some View {
        if model.translationProvider == .apple {
            TranslateLabeledRow(
                title: pairText,
                subtitle: L10n.tr("settings.pair.sub"),
                icon: pairIcon,
                iconColor: pairIconColor,
                titleColor: model.pairInfo == .ready ? Color(nsColor: .systemGreen) : nil
            ) {
                // The check may not have answered yet; hiding the button
                // would read as nothing to download.
                if model.pairInfo == .needsDownload || model.pairInfo == .unknown {
                    Button { model.requestDownload() } label: {
                        HStack(spacing: DroppySpacing.xsm) {
                            Image(systemName: "arrow.down.circle")
                                .symbolEffect(.pulse, isActive: model.prepare != nil)
                            Text(
                                model.prepare == nil
                                    ? L10n.tr("settings.download")
                                    : L10n.tr("settings.download.preparing")
                            )
                        }
                    }
                    .buttonStyle(DroppyQuietButtonStyle(size: .small))
                    .disabled(model.prepare != nil)
                    .help(L10n.tr("settings.download.tip"))
                    .translationPreparer(model)
                }
            }
            .task(id: "\(model.preparedSource)>\(model.targetID)>\(model.downloadApproach.rawValue)") {
                await model.refreshPairInfo()
            }
        }
    }

    private var pairText: String {
        let key: String
        switch model.pairInfo {
        case .unknown: key = "unknown"
        case .ready: key = "installed"
        case .needsDownload: key = "needsDownload"
        case .unsupported: key = "unsupported"
        }
        return L10n.tr("settings.pair.\(key)")
    }

    private var endpointRow: some View {
        TranslateLabeledRow(
            title: L10n.tr("settings.endpoint"),
            subtitle: L10n.tr("settings.endpoint.sub"),
            icon: "network"
        ) {
            if model.translationProvider == .custom {
                TextField("", text: $model.providerBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(Text(L10n.tr("settings.endpoint")))
            } else {
                DropletValuePill(text: model.providerBaseURL)
            }
        }
    }

    private var modelRow: some View {
        TranslateLabeledRow(
            title: L10n.tr("settings.model"),
            subtitle: L10n.tr("settings.model.sub"),
            icon: "cpu"
        ) {
            TextField("", text: $model.providerModel)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(Text(L10n.tr("settings.model")))
        }
    }

    private var apiKeyRow: some View {
        TranslateLabeledRow(
            title: L10n.tr("settings.apiKey"),
            subtitle: L10n.tr("settings.key.sub"),
            icon: "key"
        ) {
            // A key pasted with a character missing is a key that does not
            // work, and there is no other way to see what is in the field.
            HStack(spacing: DroppySpacing.xs) {
                Group {
                    if isKeyVisible {
                        TextField("", text: $model.providerKey)
                    } else {
                        SecureField("", text: $model.providerKey)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(Text(L10n.tr("settings.apiKey")))
                Button {
                    isKeyVisible.toggle()
                } label: {
                    Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                }
                .buttonStyle(DroppyCircleButtonStyle(size: 24))
                .a11y(isKeyVisible ? "settings.apiKey.hide" : "settings.apiKey.show")
            }
        }
    }

    @ViewBuilder
    private var keyInUseRow: some View {
        if model.providerHasKey {
            TranslateLabeledRow(title: L10n.tr("settings.key.current")) {
                Button(L10n.tr("settings.key.remove")) {
                    model.removeProviderKey()
                }
                .buttonStyle(DroppyQuietButtonStyle(size: .small, destructive: true))
            }
        }
    }

    private var testRow: some View {
        TranslateLabeledRow(title: L10n.tr("settings.engine.test")) {
            HStack(spacing: DroppySpacing.sm) {
                DropletValuePill(text: model.engineStatus.text)
                Button(L10n.tr("settings.engine.test.action")) {
                    model.testEngineConnection()
                }
                .buttonStyle(DroppyAccentButtonStyle(size: .small))
                .disabled(model.engineStatus == .testing)
            }
        }
    }

    /// The one sentence the page owes the user: what leaves this Mac.
    private var privacyNote: some View {
        HStack(alignment: .firstTextBaseline, spacing: DroppySpacing.sm) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.secondary)
            Text(L10n.tr("settings.privacy"))
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
    }

}

struct TranslateLanguagePairRow: View {
    @ObservedObject var model: TranslateModel

    var body: some View {
        // Captions align leading, pickers centre in their column, so the two
        // halves read as a pair around the disc.
        HStack(alignment: .bottom, spacing: DroppySpacing.lg) {
            column(
                caption: L10n.tr("settings.source"),
                options: sourceLanguages,
                isSelected: { $0 == model.sourceID },
                action: { model.sourceID = $0 }
            )
            swapButton
            column(
                caption: L10n.tr("settings.target"),
                options: targetLanguages,
                isSelected: { $0 == model.targetID },
                action: { model.targetID = $0 }
            )
        }
    }

    private var sourceLanguages: [String] {
        [TranslateModel.auto] + model.languages.map(\.id)
    }

    private var targetLanguages: [String] {
        model.languages.map(\.id)
    }

    private func column(
        caption: String,
        options: [String],
        isSelected: @escaping (String) -> Bool,
        action: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(caption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            SettingsUnifiedSegmentedRow(
                options: options,
                groupPosition: .only,
                accessibilityLabel: caption,
                isSelected: isSelected,
                action: action
            ) { option, _ in
                settingsUnifiedSegmentLabel(
                    icon: "",
                    title: languageTitle(option, model: model),
                    isSelected: false,
                    isEnabled: true
                )
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// At 24 it reads as a footnote between two pickers rather than as the
    /// switch it is.
    private var swapButton: some View {
        Button {
            model.swapLanguageSelection()
        } label: {
            Image(systemName: "arrow.left.arrow.right")
        }
        .buttonStyle(DroppyCircleButtonStyle(size: 32))
        .disabled(!model.canSwap)
        .a11y("a11y.swap")
        .help(L10n.tr("settings.swap.tip"))
    }
}

// MARK: - The preview page

struct TranslateDisplaySettings: View {
    @ObservedObject var model: TranslateModel

    var body: some View {
        DropletSettingsPage { sections }
            .onAppear { model.refreshDisplayPreviewShape() }
    }

    @ViewBuilder
    var sections: some View {
        DropletSettingsSection {
            iconHeader(
                "settings.result",
                subtitleKey: "settings.result.destination.sub",
                symbol: "rectangle.on.rectangle"
            )
        } content: {
            DropletSettingsCard {
                TranslatePickerRow(
                    title: L10n.tr("settings.result.destination"),
                    infoTip: destinationDescription,
                    options: ResultDisplay.allCases,
                    label: { L10n.tr("settings.display.\($0.rawValue)") },
                    glyph: { displayGlyph($0) },
                    isSelected: { $0 == model.resultDisplay },
                    action: { model.setResultDisplay($0) }
                )
                if model.resultDisplay == .sidePanel {
                    TranslatePickerRow(
                        title: L10n.tr("settings.sidePanel.edge"),
                        options: SidePanelSide.allCases,
                        label: { L10n.tr("settings.sidePanel.\($0.rawValue)") },
                        glyph: { $0.symbol },
                        isSelected: { $0 == model.sidePanelSide },
                        action: { model.sidePanelSide = $0 }
                    )
                }
                if model.resultDisplay == .panel {
                    TranslatePickerRow(
                        title: L10n.tr("settings.panel.content"),
                        options: ResultContent.allCases,
                        label: { L10n.tr("settings.panel.content.\($0.rawValue)") },
                        glyph: { panelContentGlyph($0) },
                        isSelected: { $0 == model.resultContent },
                        action: { model.resultContent = $0 }
                    )
                }
                DropletStackedRow(
                    title: L10n.tr("settings.result.examples"),
                    infoTip: L10n.tr("settings.section.preview.sub")
                ) {
                    displayPicture
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var destinationDescription: String {
        switch model.resultDisplay {
        case .normal: return L10n.tr("settings.display.normal.desc")
        case .panel: return L10n.tr("settings.display.panel.desc")
        case .sidePanel: return L10n.tr("settings.display.sidePanel.desc")
        }
    }

    /// The picture of the chosen place, with its name under it. One picture at
    /// a time: the picker above says which place, and the row below shows that
    /// one, so the page never offers a choice it has not taken.
    private var displayPicture: some View {
        VStack(spacing: DroppySpacing.xxxl) {
            ResultDisplayPreview(display: model.resultDisplay, model: model)
                .padding(.bottom, DroppySpacing.xxxl)

            HStack(spacing: DroppySpacing.xs) {
                Image(systemName: displayGlyph(model.resultDisplay))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(L10n.tr("settings.display.\(model.resultDisplay.rawValue)"))
                    .font(.callout)
                    .foregroundStyle(.primary)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.top, DroppySpacing.xxl)
        .frame(maxWidth: .infinity)
    }
}

/// The glyph of a place the result can land in.
private func displayGlyph(_ display: ResultDisplay) -> String {
    switch display {
    case .normal: return "rectangle.grid.1x2"
    case .panel: return "macwindow"
    case .sidePanel: return "sidebar.right"
    }
}

// MARK: - The permissions page

/// What the droplet reads, and what macOS grants. Without both permissions the
/// shelf still translates typed text, and nothing else works.
struct TranslatePermissionsSettings: View {
    @ObservedObject var model: TranslateModel

    var body: some View {
        DropletSettingsPage { sections }
    }

    @ViewBuilder
    var sections: some View {
        DropletSettingsSection {
            HStack(spacing: DroppySpacing.xs) {
                sectionHeader("settings.permissions")
                SettingsInfoTip(L10n.tr("settings.permissions.note"))
                    .accessibilityLabel(Text(L10n.tr("settings.permissions.note")))
            }
        } content: {
            DropletSettingsCard {
                ForEach(model.permissionStates) { state in
                    permissionRow(state)
                }
            }
        }
    }

    private func permissionRow(_ state: TranslateModel.PermissionState) -> some View {
        TranslateLabeledRow(
            title: L10n.tr(state.titleKey),
            subtitle: L10n.tr(state.detailKey),
            icon: icon(for: state.permission)
        ) {
            HStack(spacing: DroppySpacing.sm) {
                DropletValuePill(text: L10n.tr(state.statusKey))
                switch state.status {
                case .notDetermined:
                    Button(L10n.tr("settings.permissions.allow")) {
                        Task { await model.requestPermission(state.permission) }
                    }
                    .buttonStyle(DroppyAccentButtonStyle(size: .small))
                case .denied:
                    Button(L10n.tr("settings.permissions.open")) {
                        model.openSystemSettings(for: state.permission)
                    }
                    .buttonStyle(DroppyQuietButtonStyle(size: .small))
                case .granted, .unavailable:
                    EmptyView()
                @unknown default:
                    EmptyView()
                }
            }
        }
    }

    private func icon(for permission: DropletPermission) -> String {
        switch permission {
        case .screenCapture: return "display"
        case .accessibility: return "accessibility"
        default: return "questionmark.circle"
        }
    }
}

// MARK: - The guide

struct TranslateHelpSettings: View {
    @ObservedObject var model: TranslateModel
    /// Nil on a host that cannot open a page; the guide then joins the long
    /// page with no toolbar of its own.
    @Environment(\.dropletSettingsPageOpener) private var pageOpener

    var body: some View {
        DropletSettingsPage { sections }
    }

    /// On its own page the toolbar holds the title; in the long page a card
    /// without a heading would belong to whatever came before it.
    @ViewBuilder
    var sections: some View {
        DropletSettingsSection {
            iconHeader("settings.help.steps", symbol: "list.bullet.clipboard")
        } content: {
            stepsCard
        }

        DropletSettingsSection {
            iconHeader("settings.help.keys", symbol: "keyboard")
        } content: {
            keysCard
        }

        DropletSettingsSection {
            iconHeader("help.pin.title", symbol: "pin")
        } content: {
            pinCard
        }
    }

    private var stepsCard: some View {
        DropletSettingsCard {
            ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: DroppySpacing.sm) {
                    Text("\(index + 1).")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 18, alignment: .trailing)
                    Text(L10n.tr(step))
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, DroppySpacing.xs)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var keysCard: some View {
        DropletSettingsCard {
            ForEach(Self.shortcuts, id: \.key) { shortcut in
                HStack(spacing: DroppySpacing.md) {
                    KeycapLabel(text: L10n.tr(shortcut.key))
                    Text(L10n.tr(shortcut.text))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, DroppySpacing.xs)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var pinCard: some View {
        DropletSettingsCard {
            HStack(alignment: .firstTextBaseline, spacing: DroppySpacing.sm) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text(L10n.tr("help.pin.text"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, DroppySpacing.xs)
            .accessibilityElement(children: .combine)
        }
    }

    private static let steps = [
        "help.step.type",
        "help.step.capture",
        "help.step.select",
        "help.step.swap",
        "help.step.result",
        "help.step.copy"
    ]

    private static let shortcuts: [(key: String, text: String)] = [
        ("help.key.submit.key", "help.key.submit.text"),
        ("help.key.copy.key", "help.key.copy.text"),
        ("help.key.cancel.key", "help.key.cancel.text")
    ]
}

/// A key reads as a key only when it is drawn like one, the way System
/// Settings draws a shortcut.
struct KeycapLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .monospaced()
            .foregroundStyle(AdaptiveColors.primaryTextAuto)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(AdaptiveColors.buttonBackgroundAuto)
            )
            .fixedSize()
    }
}

// MARK: - The parts every page shares

struct SettingsPageTile: View {
    let symbol: String

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(AdaptiveColors.buttonBackgroundAuto)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AdaptiveColors.primaryTextAuto)
            )
    }
}

/// At `DropletSettingsPageLink`'s metrics, but with room for a trailing
/// summary: the permissions state is why the row exists. A door that leaves
/// the droplet points out rather than in.
struct SettingsDoorRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    var summary: String?
    var external = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DroppySpacing.md) {
                SettingsPageTile(symbol: symbol)
                    .frame(
                        width: DropletSettingsPageLink<EmptyView>.tileSize,
                        height: DropletSettingsPageLink<EmptyView>.tileSize
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)

                Spacer(minLength: 12)

                if let summary {
                    HStack(spacing: DroppySpacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color(nsColor: .systemGreen))
                        Text(summary)
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }

                Image(systemName: external ? "arrow.up.forward" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(summary ?? subtitle))
        .accessibilityAddTraits(.isButton)
    }
}

/// The kit's header is text alone. A 13pt glyph on the header line lets a page
/// read like its doors; the description follows in an info tip, not a line.
@MainActor
private func iconHeader(
    _ titleKey: String,
    subtitleKey: String? = nil,
    symbol: String
) -> some View {
    HStack(spacing: DroppySpacing.xs) {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        settingsSectionHeader(LocalizedStringKey(L10n.tr(titleKey)))
        if let subtitleKey {
            SettingsInfoTip(L10n.tr(subtitleKey))
                .accessibilityLabel(Text(L10n.tr(subtitleKey)))
        }
    }
}

@MainActor
private func sectionHeader(_ titleKey: String) -> some View {
    settingsSectionHeader(LocalizedStringKey(L10n.tr(titleKey)))
}

@MainActor
private func languageTitle(_ id: String, model: TranslateModel) -> String {
    if id == TranslateModel.auto { return L10n.tr("auto") }
    return model.languages.first(where: { $0.id == id })?.menuName ?? id
}

private let uiLanguages = ["system", "en", "fr", "th"]

private func uiLanguageTitle(_ id: String) -> String {
    switch id {
    case "system": return L10n.tr("settings.ui.system")
    case "en": return "English"
    case "fr": return "Français"
    case "th": return "ไทย"
    default: return id
    }
}

// MARK: - The rows the pages are built from

/// The kit's rows carry one line; these add a description.
struct TranslateLabeledRow<Accessory: View>: View {
    let title: String
    var subtitle: String?
    var icon: String?
    var iconColor: Color?
    var titleColor: Color?
    let accessory: Accessory

    init(
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        iconColor: Color? = nil,
        titleColor: Color? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconColor = iconColor
        self.titleColor = titleColor
        self.accessory = accessory()
    }

    var body: some View {
        // Centred so a two-line label and its button read as one band.
        LabeledContent {
            accessory
                .frame(maxHeight: .infinity)
        } label: {
            TranslateRowLabel(
                title: title,
                subtitle: subtitle,
                icon: icon,
                iconColor: iconColor,
                titleColor: titleColor
            )
        }
    }
}

struct TranslateRowLabel: View {
    let title: String
    var subtitle: String?
    var icon: String?
    var iconColor: Color?
    var titleColor: Color?
    var infoTip: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: DroppySpacing.sm) {
                if let icon {
                    Image(systemName: icon)
                        .foregroundStyle(iconColor ?? .secondary)
                }
                Text(title)
                    .fontWeight(.semibold)
                    .foregroundStyle(titleColor ?? .primary)
                if let infoTip {
                    SettingsInfoTip(infoTip)
                        .accessibilityLabel(Text(infoTip))
                }
            }
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The switch is the row: a `Toggle` inside `LabeledContent` becomes a check
/// box, and the Form styles only a top-level `Toggle` as a switch.
/// System Settings writes the state beside the switch rather than leaving
/// the switch to be read on its own.
struct TranslateToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding private var isOn: Bool

    init(title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    var body: some View {
        // Built by hand at the Form's metrics so the state word stays out
        // of the label.
        HStack(spacing: DroppySpacing.sm) {
            TranslateRowLabel(title: title, subtitle: subtitle)
            Spacer(minLength: 12)
            Text(L10n.tr(isOn ? "settings.on" : "settings.off"))
                .foregroundStyle(.secondary)
                .fixedSize()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(L10n.tr(isOn ? "settings.on" : "settings.off")))
    }
}

struct TranslatePickerRow<Option: Hashable>: View {
    let title: String
    var subtitle: String?
    var infoTip: String?
    let options: [Option]
    let label: (Option) -> String
    let glyph: (Option) -> String
    let isSelected: (Option) -> Bool
    let action: (Option) -> Void

    init(
        title: String,
        subtitle: String? = nil,
        infoTip: String? = nil,
        options: [Option],
        label: @escaping (Option) -> String,
        glyph: @escaping (Option) -> String,
        isSelected: @escaping (Option) -> Bool,
        action: @escaping (Option) -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.infoTip = infoTip
        self.options = options
        self.label = label
        self.glyph = glyph
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        HStack(spacing: DroppySpacing.md) {
            TranslateRowLabel(title: title, subtitle: subtitle, infoTip: infoTip)
            Spacer(minLength: DroppySpacing.md)
            SettingsUnifiedSegmentedRow(
                options: options,
                groupPosition: .only,
                accessibilityLabel: title,
                isSelected: isSelected,
                action: action
            ) { option, _ in
                settingsUnifiedSegmentLabel(
                    icon: glyph(option),
                    title: label(option),
                    isSelected: false,
                    isEnabled: true
                )
            }
            .fixedSize()
        }
    }
}

private func panelContentGlyph(_ content: ResultContent) -> String {
    switch content {
    case .result: return "textformat"
    case .both: return "doc.on.doc"
    }
}

private func engineGlyph(_ engine: TranslationEngine) -> String {
    switch engine {
    case .classic: return "house"
    case .appleIntelligence: return "apple.logo"
    case .provider: return "sparkles"
    }
}

private func providerGlyph(_ provider: TranslationProvider) -> String {
    switch provider {
    case .apple: return "apple.logo"
    case .openAI, .anthropic, .gemini: return "cloud"
    case .ollama: return "laptopcomputer"
    case .custom: return "link"
    }
}
