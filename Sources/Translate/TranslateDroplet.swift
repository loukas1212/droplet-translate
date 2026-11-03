import AppKit
import Combine
import DroppyKit
import SwiftUI

@objc(TranslatePrincipal)
public final class TranslatePrincipal: NSObject, DropletPrincipal {
    public override init() { super.init() }
    @MainActor public func makeDroplet() -> AnyObject { TranslateDroplet() }
}

@MainActor
public final class TranslateDroplet: NSObject, ObservableObject, Droplet {
    public nonisolated static let id: DropletID = "translate"

    private let model = TranslateModel()
    private let capture = CaptureService()
    private let selection = SelectionService()
    private var host: DropletHost?
    /// The card height the shelf content asks for. The descriptor reports it,
    /// and the host springs to it after an invalidation.
    private var shelfCardHeight = SidePanelContentView.shelfOpeningCardHeight
    /// The last height the host was told about. Small changes wait until they
    /// cross the threshold, so typing does not invalidate on every keystroke.
    private var lastShelfLayoutHeight = SidePanelContentView.shelfOpeningCardHeight
    private static let shelfLayoutThreshold: CGFloat = 8
    /// Watches the chosen destination, so the edge panel comes and goes with it.
    private var displayCancellable: AnyCancellable?
    /// Moves the edge panel when its side changes.
    private var sidePanelCancellable: AnyCancellable?

    public func activate(host: DropletHost) throws {
        LanguageTools.checkLanguageIDRules()
        TranslateModel.checkPinReleaseRules()
        self.host = host
        model.attach(host: host)
        capture.attach(host: host, model: model)
        selection.attach(host: host, model: model)
        // The floating panel's more menu uses the same capture and selection
        // actions as the edge panel; the droplet owns the services.
        TranslationPanel.shared.configure(
            requestCapture: { [weak self] in self?.capture.requestRegion() },
            requestSelection: { [weak self] in self?.selection.requestSelection() },
            cancelSelection: { [weak self] in self?.selection.cancel() }
        )
        registerShortcuts(host: host)
        displayCancellable = model.$resultDisplay.sink { [weak self] display in
            MainActor.assumeIsolated { self?.updateSidePanel(display) }
        }
        sidePanelCancellable = model.$sidePanelSide.sink { side in
            MainActor.assumeIsolated { SidePanel.shared.setSide(side) }
        }
        updateSidePanel(model.resultDisplay)
    }

    /// The edge panel exists only while it is the chosen Display mode; every
    /// other mode keeps its tab off the screen.
    private func updateSidePanel(_ display: ResultDisplay) {
        guard display == .sidePanel else {
            SidePanel.shared.hide()
            return
        }
        SidePanel.shared.show(
            model: model,
            requestCapture: { [weak self] in self?.capture.requestRegion() },
            requestSelection: { [weak self] in self?.selection.requestSelection() },
            cancelSelection: { [weak self] in self?.selection.cancel() }
        )
    }

    public func deactivate() {
        capture.detach()
        selection.detach()
        model.teardown()
        displayCancellable?.cancel()
        displayCancellable = nil
        sidePanelCancellable?.cancel()
        sidePanelCancellable = nil
        SidePanel.shared.hide()
        TranslationPanel.shared.closePanel(animated: false)
        // The host drops these on deactivate; clearing now empties the list
        // the moment the droplet is off.
        host?.shortcuts.unregister(id: "select-text")
        host?.shortcuts.unregister(id: "capture-region")
        host?.shortcuts.unregister(id: "open-translate")
        host = nil
    }

    /// The three ways to start a translation without the shelf, all also shelf
    /// buttons. Declared here so Droppy's Shortcuts page can show them. Every
    /// default is nil: the user picks, and the host drops a suggestion that
    /// collides with an existing binding.
    private func registerShortcuts(host: DropletHost) {
        host.shortcuts.register(
            id: "select-text",
            title: L10n.tr("settings.shortcuts.select"),
            defaultShortcut: nil
        ) { [weak self] in
            self?.selection.requestSelection()
        }
        host.shortcuts.register(
            id: "capture-region",
            title: L10n.tr("settings.shortcuts.capture"),
            defaultShortcut: nil
        ) { [weak self] in
            self?.capture.requestRegion()
        }
        host.shortcuts.register(
            id: "open-translate",
            title: L10n.tr("settings.shortcuts.open"),
            defaultShortcut: nil
        ) { [weak self] in
            self?.model.openTranslate()
        }
    }
}

// MARK: - Shelf widget

extension TranslateDroplet: ShelfWidgetProviding {
    public var widgetDescriptors: [ShelfWidgetDescriptor] {
        [
            ShelfWidgetDescriptor(
                id: "translate",
                title: "Translate",
                systemImage: "translate",
                layoutTraits: ShelfWidgetLayoutTraits(
                    preferredSoloWidth: SidePanelContentView.shelfSoloWidth,
                    preferredPairedWidth: 230,
                    // The content's own height; the widget reports it as the
                    // input and the fitted result grow.
                    contentHeight: .fixed(shelfCardHeight)
                ),
                // The primary surface is a text field.
                focusPolicy: .keyboardFocusable,
                searchKeywords: ["translate", "translation", "language", "traduire", "traduction"]
            )
        ]
    }

    public func makeWidgetView(_ id: ShelfWidgetID, context: ShelfWidgetContext) -> AnyView {
        model.updateShelfPreviewShape(from: context)
        let insets = context.contentInsets
        // The host gives a notch card 8pt at its sides and a solo island card
        // none; the widget keeps the 8 itself, so both draw the same boxes.
        let side = max(insets.leading, insets.trailing, SidePanelContentView.shelfBoxInset)
        let edges = EdgeInsets(
            top: insets.top,
            leading: side,
            bottom: insets.bottom,
            trailing: side
        )
        let width = context.availableSize.width - side * 2
        return AnyView(
            TranslateWidget(
                model: model,
                requestCapture: { [weak self] in self?.capture.requestRegion() },
                requestSelection: { [weak self] in self?.selection.requestSelection() },
                cancelSelection: { [weak self] in self?.selection.cancel() },
                rowWidth: width > 0
                    ? min(SidePanelContentView.defaultRowWidth, width)
                    : SidePanelContentView.defaultRowWidth,
                shelfHeightBudget: insets.top + insets.bottom,
                onShelfHeight: { [weak self] height in self?.setShelfHeight(height) }
            )
            .padding(edges)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        )
    }

    /// The content's needed card height. The host re-reads the descriptor and
    /// springs to it, but only once the change is worth a resize.
    private func setShelfHeight(_ height: CGFloat) {
        let range = DroppyShellMetrics.shelfWidgetFixedContentHeightRange
        let clamped = min(max(height, range.lowerBound), range.upperBound)
        shelfCardHeight = clamped
        guard abs(clamped - lastShelfLayoutHeight) >= Self.shelfLayoutThreshold else { return }
        lastShelfLayoutHeight = clamped
        host?.shelf.invalidateLayout(for: "translate")
    }

    public func makeWidgetSettingsPopover(_ id: ShelfWidgetID) -> AnyView? { nil }
}

// MARK: - Settings pane

/// `SettingsPagesProviding` refines `SettingsPaneProviding`, so the droplet
/// keeps its pane and adds pages of its own inside it.
extension TranslateDroplet: SettingsPagesProviding {
    public func makeSettingsPane(context: SettingsPaneContext) -> AnyView {
        AnyView(TranslateSettings(model: model))
    }

    public func makeSettingsPage(id: String, context: SettingsPaneContext) -> AnyView? {
        switch TranslateSettingsPage(rawValue: id) {
        case .translation: return AnyView(TranslateTranslationSettings(model: model))
        case .display: return AnyView(TranslateDisplaySettings(model: model))
        case .permissions: return AnyView(TranslatePermissionsSettings(model: model))
        case .help: return AnyView(TranslateHelpSettings(model: model))
        case nil: return nil
        }
    }

    /// Search lands on the droplet's own page, so every entry mirrors a row
    /// there. Keywords are English and Thai, matching both interface languages.
    public var settingsSearchEntries: [SettingsSearchEntry] {
        [
            SettingsSearchEntry(
                title: L10n.tr("settings.permissions.screenCapture"),
                keywords: ["permission", "capture", "ocr", "screen", "record",
                           "สิทธิ์", "จับหน้าจอ", "อ่านข้อความ"]
            ),
            SettingsSearchEntry(
                title: L10n.tr("settings.permissions.accessibility"),
                keywords: ["permission", "selection", "selected text", "assistive",
                           "สิทธิ์", "เลือกข้อความ", "เข้าถึง"]
            ),
            SettingsSearchEntry(
                title: L10n.tr("settings.translation"),
                keywords: ["translation", "language", "engine", "model", "classic", "apple intelligence",
                           "key", "api", "download", "offline", "provider", "behavior", "auto copy",
                           "การแปลภาษา", "แปลภาษา", "ภาษา", "เอนจิน", "โมเดล", "คีย์", "ดาวน์โหลด", "คัดลอก"]
            ),
            SettingsSearchEntry(
                title: L10n.tr("settings.display"),
                keywords: ["display", "result", "panel", "side panel", "notch", "widget", "interface",
                           "theme", "appearance", "preview",
                           "การแสดงผล", "ผลลัพธ์", "แผง", "แผงลอย", "แผงด้านข้าง", "notch", "หน้าตาของโปรแกรม", "ตัวอย่าง"]
            ),
            SettingsSearchEntry(
                title: L10n.tr("settings.help"),
                keywords: ["guide", "steps", "shortcuts", "keyboard", "help",
                           "คู่มือ", "ขั้นตอน", "ปุ่มลัด", "แป้นพิมพ์"]
            )
        ]
    }
}
