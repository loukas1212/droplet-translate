import DroppyKit
import SwiftUI

struct TranslateSettings: View {
    @ObservedObject var model: TranslateModel

    var body: some View {
        DropletSettingsPane {
            DropletSettingsSection {
                sectionHeader("settings.languages")
            } content: {
                DropletSettingsCard {
                    languagePicker(title: L10n.tr("settings.source"), selection: $model.sourceID, includesAuto: true)
                    languagePicker(title: L10n.tr("settings.target"), selection: $model.targetID, includesAuto: false)
                    DropletToggleRow(
                        title: L10n.tr("settings.live"),
                        subtitle: L10n.tr("settings.live.sub"),
                        isOn: $model.liveTranslate
                    )
                    DropletControlRow(title: L10n.tr("settings.ui")) {
                        Picker("", selection: $model.uiLanguage) {
                            Text(L10n.tr("settings.ui.system")).tag("system")
                            Text("English").tag("en")
                            Text("Français").tag("fr")
                        }
                        .menuPicker()
                    }
                }
            }

            DropletSettingsSection {
                sectionHeader("settings.offline")
            } content: {
                DropletSettingsCard {
                    DropletControlRow(title: L10n.tr("settings.pair")) {
                        DropletValuePill(text: pairText)
                            .task(id: "\(model.sourceID)>\(model.targetID)") {
                                await model.refreshPairInfo()
                            }
                    }
                    DropletControlRow(title: L10n.tr("settings.download")) {
                        Button(L10n.tr("settings.download")) { model.requestDownload() }
                            .buttonStyle(.bordered)
                            .disabled(!model.pairInfo.canDownload)
                            .translationPreparer(model)
                    }
                }
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

    private func sectionHeader(_ key: String) -> some View {
        settingsSectionHeader(LocalizedStringKey(L10n.tr(key)))
    }

    private func languagePicker(title: String, selection: Binding<String>, includesAuto: Bool) -> some View {
        DropletControlRow(title: title) {
            Picker("", selection: selection) {
                if includesAuto {
                    Text(L10n.tr("auto")).tag(TranslateModel.auto)
                    Divider()
                }
                ForEach(model.languages) { language in
                    Text(language.name).tag(language.id)
                }
            }
            .menuPicker()
        }
    }
}

private extension View {
    func menuPicker() -> some View {
        labelsHidden().pickerStyle(.menu)
    }
}
