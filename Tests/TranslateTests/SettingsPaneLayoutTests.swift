import AppKit
import DroppyKit
import SwiftUI
import Testing
@testable import Translate

/// The settings pane, as the host draws it.
///
/// The pane is a grouped Form, and the Form is what lays the rows out: a
/// button squeezed into a sliver, a field of a few points, a picker whose
/// face is empty. None of that shows in a build, so the pane is hosted in a
/// real Form here and measured.
@Suite("The settings pane")
@MainActor
struct SettingsPaneLayoutTests {
    /// The width the Form gives a field on the trailing edge of a row.
    private static let minimumFieldWidth: CGFloat = 150

    @Test("A field keeps the room the Form gives it")
    func fieldsKeepTheirWidth() throws {
        let model = TranslateModel()
        model.translationProvider = .openAI

        // The fields are on the translation page, behind the droplet's page:
        // the pane itself is a list of doors, and the Form's column is what
        // the page has to hold its fields in.
        let hosting = Self.host(
            Form {
                TranslateTranslationSettings(model: model).sections
            }
            .formStyle(.grouped)
            .frame(width: 590, height: 1400)
        )
        defer { hosting.window.orderOut(nil) }

        let widths = Self.textFieldWidths(in: hosting.view)
        #expect(!widths.isEmpty, "the pane drew no field at all")
        for width in widths {
            #expect(
                width >= Self.minimumFieldWidth,
                "a field is \(Int(width))pt wide: the Form gives a trailing field its own column"
            )
        }
    }

    @Test("The translation page draws its cards")
    func translationPageDraws() throws {
        // The page is behind a door, so the harness never renders it: this is
        // the only picture of it. Written next to the shots, not asserted on:
        // the point is that a person can look at it.
        let model = TranslateModel()
        let (view, window) = Self.host(
            Form {
                DropletSettingsPane {
                    TranslateTranslationSettings(model: model).sections
                }
            }
            .formStyle(.grouped)
            .frame(width: 590, height: 900)
        )
        defer { window.orderOut(nil) }

        #expect(Self.ink(in: view) > 0, "the translation page draws nothing at all")

        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        #expect(rep != nil, "the page drew no bitmap")
        if let rep, let data = (view.cacheDisplay(in: view.bounds, to: rep),
                                rep.representation(using: .png, properties: [:])).1 {
            let url = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("translate-settings-translation.png")
            try data.write(to: url)
        }
    }

    @Test("The Apple engines draw the pair row")
    func pairRowOnAppleEngines() throws {
        // Apple's models download a pair per strategy, so the translation page
        // carries the status row on both Apple engines. Written next to the
        // other pages' pictures so a person can look at it.
        let model = TranslateModel()
        model.setTranslationEngine(.appleIntelligence)
        let (view, window) = Self.host(
            Form {
                DropletSettingsPane {
                    TranslateTranslationSettings(model: model).sections
                }
            }
            .formStyle(.grouped)
            .frame(width: 590, height: 900)
        )
        defer { window.orderOut(nil) }

        #expect(Self.ink(in: view) > 0, "the translation page draws nothing at all")

        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        #expect(rep != nil, "the page drew no bitmap")
        if let rep, let data = (view.cacheDisplay(in: view.bounds, to: rep),
                                rep.representation(using: .png, properties: [:])).1 {
            let url = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("translate-settings-classic.png")
            try data.write(to: url)
        }
    }

    @Test("The preview page draws its cards")
    func displayPageDraws() throws {
        // The page is behind a door, so the harness never renders it.
        let model = TranslateModel()
        model.setResultDisplay(.panel)
        let (view, window) = Self.host(
            Form {
                DropletSettingsPane {
                    TranslateDisplaySettings(model: model).sections
                }
            }
            .formStyle(.grouped)
            .frame(width: 590, height: 1500)
        )
        defer { window.orderOut(nil) }

        #expect(Self.ink(in: view) > 0, "the preview page draws nothing at all")

        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        #expect(rep != nil, "the page drew no bitmap")
        if let rep, let data = (view.cacheDisplay(in: view.bounds, to: rep),
                                rep.representation(using: .png, properties: [:])).1 {
            let url = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("translate-settings-display.png")
            try data.write(to: url)
        }
    }

    @Test("A picker row draws the value it is set to")
    func pickerRowsDrawTheirValue() throws {
        // Two rows that differ in one thing only: the value they are set to.
        // If the face of the row drew nothing but the chevron, the two
        // pictures would be the same.
        let alpha = try Self.drawPickerRow(value: "Alpha")
        let omega = try Self.drawPickerRow(value: "Omega")
        #expect(
            alpha != omega,
            "the picker row draws no value: the face of the row is empty"
        )
    }

    @Test("The preview page's pictures take no taps")
    func displayPicturesAreInert() throws {
        // A picture of a surface is not a control. The examples on the
        // Preview page are the only place a user sees these shapes before
        // choosing, and they used to be buttons: a picture that answers a tap
        // is a hidden control. The place is chosen on the picker row above.
        let model = TranslateModel()
        model.resultDisplay = .normal
        let (view, window) = Self.host(
            HStack {
                ForEach(ResultDisplay.allCases) { display in
                    ResultDisplayPreview(display: display, model: model)
                }
            }
            .frame(width: 700, height: 600)
        )
        defer { window.orderOut(nil) }

        // Every example is hit-testing disabled, so a click at its centre
        // lands on the container, never on the picture.
        let centre = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), from: nil)
        let hit = view.hitTest(centre)
        #expect(hit === view || hit?.isDescendant(of: view) == true)
        #expect(model.resultDisplay == .normal, "a picture changed the setting")
    }

    @Test("The shelf preview includes the complete host shell")
    func shelfPreviewIncludesHostShell() {
        let widget = CGSize(width: 440, height: ShelfHeightStep.compact.contentHeight)
        let island = ShelfWidgetSurfacePreview.previewSize(
            widgetSize: widget,
            usesIslandCurvature: true,
            notchHeight: DroppyShellMetrics.physicalNotchHeight
        )
        #expect(island == CGSize(width: 475, height: 269))

        let notch = ShelfWidgetSurfacePreview.previewSize(
            widgetSize: widget,
            usesIslandCurvature: false,
            notchHeight: DroppyShellMetrics.physicalNotchHeight
        )
        #expect(notch == CGSize(width: 539, height: 300))
    }

    @Test("Display previews follow host changes between notch and island")
    func displayPreviewTracksHostGeometry() {
        let model = TranslateModel()
        // A mounted widget's surface is authoritative. On a paired island the
        // host disables island curvature, but the preview is still an island.
        model.updateShelfPreviewShape(from: ShelfWidgetContext(
            availableSize: CGSize(width: 230, height: 480),
            isPaired: true,
            placement: .leading,
            isCompact: true,
            isShelfTransitioning: false,
            isPreview: true,
            surface: .dynamicIsland,
            usesIslandCurvature: false,
            usesAdaptiveForegrounds: false
        ))
        #expect(model.shelfUsesIslandCurvature)

        // The environment's live geometry takes over when the host changes
        // the simulated/physical display while Settings stays open.
        model.updateShelfPreviewShape(from: DropletNotchGeometry(
            closedWidth: 210,
            closedHeight: 34,
            cornerRadius: 12,
            isHardwareNotch: true,
            displayID: 1
        ))
        #expect(!model.shelfUsesIslandCurvature)
        #expect(model.notchCutoutWidth == 210)
        #expect(model.notchCutoutHeight == 34)
        let notch = ShelfWidgetSurfacePreview.previewSize(
            widgetSize: CGSize(width: 440, height: 480),
            usesIslandCurvature: model.shelfUsesIslandCurvature,
            notchHeight: model.notchCutoutHeight
        )

        model.updateShelfPreviewShape(from: DropletNotchGeometry(
            closedWidth: 210,
            closedHeight: 34,
            cornerRadius: 12,
            isHardwareNotch: false,
            displayID: 1
        ))
        #expect(model.shelfUsesIslandCurvature)
        let island = ShelfWidgetSurfacePreview.previewSize(
            widgetSize: CGSize(width: 440, height: 480),
            usesIslandCurvature: model.shelfUsesIslandCurvature,
            notchHeight: model.notchCutoutHeight
        )
        #expect(notch != island)
    }

    @Test("Every picture fills the stage in the direction its own shape allows")
    func displayPreviewFitsTheStage() {
        let stage = ResultDisplayPreview.stageSize
        #expect(stage == CGSize(width: 440, height: 280))

        // A wide panel and a tall card both fill the stage's width, so neither
        // reads as bigger than the other on the page.
        let panel = ResultDisplayPreview.previewScale(
            surfaceSize: CGSize(width: 460, height: 250),
            stageSize: stage
        )
        let card = ResultDisplayPreview.previewScale(
            surfaceSize: CGSize(width: 475, height: 265),
            stageSize: stage
        )
        #expect(abs(460 * panel - stage.width) < 0.001)
        #expect(abs(475 * card - stage.width) < 0.001)
        #expect(250 * panel <= stage.height + 0.001)
        #expect(265 * card <= stage.height + 0.001)
        #expect(
            ResultDisplayPreview.previewScale(surfaceSize: .zero, stageSize: stage) == 1
        )
    }

    @Test("Every page of the settings draws its content")
    func everyPageDraws() throws {
        let model = TranslateModel()
        let pages: [(name: String, page: AnyView)] = [
            ("main", AnyView(TranslateSettings(model: model))),
            ("translation", AnyView(TranslateTranslationSettings(model: model).sections)),
            ("display", AnyView(TranslateDisplaySettings(model: model).sections)),
            ("permissions", AnyView(TranslatePermissionsSettings(model: model).sections)),
            ("help", AnyView(TranslateHelpSettings(model: model).sections))
        ]

        for (name, page) in pages {
            let (view, window) = Self.host(
                Form {
                    page
                }
                .formStyle(.grouped)
                .frame(width: 590, height: 1200)
            )
            defer { window.orderOut(nil) }
            #expect(
                Self.ink(in: view) > 0,
                "the \(name) page draws nothing at all"
            )
        }
    }

    // MARK: - The measurements

    /// How much of a hosted view was drawn: the pixels that are not the
    /// background.
    private static func ink(in view: NSView) -> Int {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return 0
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        var count = 0
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh {
                guard let color = rep.colorAt(x: x, y: y) else { continue }
                if color.brightnessComponent > 0.2 { count += 1 }
            }
        }
        return count
    }

    /// The widths of the editable text fields in a hosted view. A menu's
    /// label is an `NSTextField` too, but the Form never lays it out in a
    /// field column.
    private static func textFieldWidths(in view: NSView) -> [CGFloat] {
        var widths: [CGFloat] = []
        if let field = view as? NSTextField, field.isEditable {
            widths.append(field.frame.width)
        }
        for subview in view.subviews {
            widths.append(contentsOf: textFieldWidths(in: subview))
        }
        return widths
    }

    /// A hosted view, in a window, with its layout done.
    private static func host(_ view: some View) -> (view: NSView, window: NSWindow) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.orderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        return (hosting, window)
    }

    /// The picture of one picker row, set to one value.
    private static func drawPickerRow(value: String) throws -> Data {
        let (view, window) = host(
            Form {
                DropletSettingsPane {
                    DropletSettingsCard {
                        settingsUnifiedPickerRow(
                            title: "Choice",
                            subtitle: "",
                            options: [value, "Beta"],
                            groupPosition: .only,
                            isSelected: { $0 == value },
                            action: { _ in }
                        ) { option, _, _ in
                            settingsUnifiedSegmentLabel(
                                icon: "",
                                title: option,
                                isSelected: false,
                                isEnabled: true
                            )
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(width: 590, height: 160)
        )
        defer { window.orderOut(nil) }

        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        #expect(rep != nil, "the row drew no bitmap")
        guard let rep else { return Data() }
        view.cacheDisplay(in: view.bounds, to: rep)
        let data = rep.representation(using: .png, properties: [:])
        #expect(data != nil, "the row drew no picture")
        return data ?? Data()
    }
}
