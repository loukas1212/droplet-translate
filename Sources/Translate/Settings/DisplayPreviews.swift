import DroppyKit
import SwiftUI

/// One sentence translated both ways, so the pictures follow the chosen
/// direction. A third language falls back to English.
enum PreviewSample {
    static let thai = "ฝนตกหนักที่กรุงเทพฯ เมื่อวานนี้"
    static let english = "It rained heavily in Bangkok yesterday."

    /// The original, the result, and the language each is in.
    static func forTarget(_ targetID: String) -> (source: String, result: String, sourceLanguage: String) {
        let target = Locale.Language(identifier: targetID).languageCode?.identifier
        return target == "th"
            ? (english, thai, "en")
            : (thai, english, "th")
    }

    /// A real model preloaded with the example, so the widget draws its result
    /// the way it draws a real one, in the user's languages.
    ///
    /// `showsResult` is false for the surfaces whose first step is the input
    /// alone: their example must show the card as it opens.
    @MainActor
    static func widgetModel(_ model: TranslateModel, showsResult: Bool = true) -> TranslateModel {
        let sample = forTarget(model.targetID)
        let preview = TranslateModel()
        preview.beginPreview(
            source: sample.sourceLanguage,
            target: model.targetID,
            text: sample.source,
            translated: sample.result,
            showsResult: showsResult
        )
        return preview
    }
}

/// One destination drawn inside the host's shell and surface. Inert: the
/// picker above chooses, and nothing here changes a setting.
struct ResultDisplayPreview: View {
    let display: ResultDisplay
    @ObservedObject var model: TranslateModel

    /// The size this shelf widget declares to the host.
    private static let shelfWidth: CGFloat = 440
    private static let panelWidth: CGFloat = 460

    /// The box every picture is drawn into. Its width is the shelf's, so a
    /// picture never reads wider than its siblings; its height is the tallest
    /// card a picture shows (the floating panel with an original), so that
    /// one still fills the width instead of shrinking to fit a short stage.
    static let stageSize = CGSize(
        width: 440,
        height: ResultWindowView.minimumHeightWithOriginal
    )

    var body: some View {
        drawing
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            // Scale after layout so the shell and its contents keep their
            // proportions together. The anchor keeps the picture's top edge
            // where it was, so the name under it stays with it.
            .scaleEffect(scale, anchor: .top)
            .frame(
                width: surfaceSize.width * scale,
                height: surfaceSize.height * scale,
                alignment: .top
            )
            .frame(maxWidth: .infinity)
    }

    /// The picture fits the stage the way a document fits a window: as large
    /// as its own shape allows, and no larger.
    private var scale: CGFloat {
        Self.previewScale(surfaceSize: surfaceSize, stageSize: Self.stageSize)
    }

    /// The scale a picture of `surfaceSize` takes inside `stageSize`.
    static func previewScale(surfaceSize: CGSize, stageSize: CGSize) -> CGFloat {
        guard surfaceSize.width > 0, surfaceSize.height > 0 else { return 1 }
        return min(
            stageSize.width / surfaceSize.width,
            stageSize.height / surfaceSize.height
        )
    }

    private var surfaceSize: CGSize {
        switch display {
        case .normal: return shelfSurfaceSize
        case .panel:
            // The measured card: the result alone, or with the original above
            // it, both including the footer the siblings wear.
            return CGSize(
                width: Self.panelWidth,
                height: model.resultContent.showsOriginal
                    ? ResultWindowView.minimumHeightWithOriginal
                    : ResultWindowView.minimumHeight
            )
        case .sidePanel: return sidePanelSurfaceSize
        }
    }

    private var shelfSurfaceSize: CGSize {
        ShelfWidgetSurfacePreview.previewSize(
            widgetSize: shelfWidgetSize,
            usesIslandCurvature: model.shelfUsesIslandCurvature,
            notchHeight: model.notchCutoutHeight
        )
    }

    private var sidePanelSurfaceSize: CGSize {
        SidePanelSurfacePreview.cardSize
    }

    /// The shelf opens at its first step: the input alone, in the card the
    /// host draws around it.
    private var shelfWidgetSize: CGSize {
        CGSize(width: Self.shelfWidth, height: ShelfHeightStep.compact.contentHeight)
    }

    @ViewBuilder
    private var drawing: some View {
        switch display {
        case .normal:
            ShelfWidgetSurfacePreview(
                model: model,
                widgetSize: shelfWidgetSize
            )
            .frame(
                width: surfaceSize.width,
                height: surfaceSize.height,
                alignment: .topLeading
            )
        case .panel:
            let sample = PreviewSample.forTarget(model.targetID)
            ResultWindowView(
                model: model,
                translated: sample.result,
                source: sample.source,
                sourceName: model.name(for: sample.sourceLanguage),
                pinned: false,
                showsOriginal: model.resultContent.showsOriginal,
                colorScheme: model.surfaceColorScheme,
                backdrop: .hostGlassOnBlack,
                onCopy: {},
                onClose: {},
                onPin: {}
            )
            .frame(width: Self.panelWidth)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.colorScheme, model.surfaceColorScheme)
            .frame(
                width: surfaceSize.width,
                height: surfaceSize.height,
                alignment: .top
            )
        case .sidePanel:
            SidePanelSurfacePreview(model: model)
                .frame(
                    width: surfaceSize.width,
                    height: surfaceSize.height,
                    alignment: .topLeading
                )
        }
    }
}

/// The droplet's own edge panel: the card that opens out of the screen's edge
/// with the result in it. The example shows the card as it opens, before a
/// result is in it.
struct SidePanelSurfacePreview: View {
    @ObservedObject var model: TranslateModel
    @State private var chip = SidePanelChipState()

    /// The body the panel holds with the input alone.
    static let bodyHeight = SidePanelContentView.panelMinBodyHeight
    /// The card, at the size it opens at.
    static let cardSize = CGSize(
        width: SidePanel.expandedWidth,
        height: SidePanel.cardHeight(forBody: bodyHeight)
    )
    private static var contentWidth: CGFloat {
        SidePanel.expandedWidth - SidePanelContentView.inset * 2
    }

    private var mirrored: Bool { model.sidePanelSide == .left }

    var body: some View {
        ZStack(alignment: .topLeading) {
            card
            SidePanelContentView(
                model: PreviewSample.widgetModel(model, showsResult: false),
                chip: chip,
                boxFloor: SidePanelContentView.panelBoxFloor
            )
            .frame(
                width: Self.contentWidth,
                height: SidePanelContentView.contentHeight(forBody: Self.bodyHeight)
            )
            .offset(
                x: SidePanelContentView.inset,
                y: SidePanelCardShape.filletRadius + SidePanelContentView.inset
            )
        }
        // The panel's chrome is Droppy's dark glass, whatever the system is set
        // to, so its tiles and controls read the app's own appearance.
        .environment(\.colorScheme, model.surfaceColorScheme)
        .frame(width: Self.cardSize.width, height: Self.cardSize.height, alignment: .topLeading)
    }

    /// The card and its face, mirrored to the chosen edge. The content is not
    /// part of the mirror: it is already laid out for either side, and flipping
    /// it would shift it by its inset.
    private var card: some View {
        ZStack(alignment: .topLeading) {
            // The same face the live card draws, on the same outline. The
            // picture has the settings page behind it, not the desktop, so the
            // glass needs the droplet's black under it to melt from; without
            // it the glass samples the page and comes out grey.
            SidePanelUnifiedShape(reveal: 1, stretch: 1)
                .fill(.black)
            SidePanelCardSurface(
                shape: AnyShape(SidePanelUnifiedShape(reveal: 1, stretch: 1))
            )
            .frame(
                width: Self.cardSize.width,
                height: Self.cardSize.height,
                alignment: .topLeading
            )
        }
        .scaleEffect(x: mirrored ? -1 : 1, y: 1)
    }
}

/// The host's own surface: Droppy's Dynamic Glass, in the shape the host
/// draws it.
///
/// The host's surface is a rounded rectangle, so it is drawn a corner wider
/// than the card it covers: its own corners then fall outside the card and
/// only its body shows, and the card reads as one piece of glass instead of a
/// black shape with a second shape laid on it.
struct HostGlassSurface: View {
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if DroppyKitSurfaceBridge.panelSurfaceProvider == nil {
                // Standalone previews have no host theme provider; the black
                // under it is then the whole surface.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.black)
            } else {
                DroppyPanelSurface(cornerRadius: cornerRadius)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// The widget inside the host's expanded shell. The preview adds the host
/// chrome; the widget keeps the insets `ShelfWidgetContext` supplies.
struct ShelfWidgetSurfacePreview: View {
    @ObservedObject var model: TranslateModel
    let widgetSize: CGSize

    static func previewSize(
        widgetSize: CGSize,
        usesIslandCurvature: Bool,
        notchHeight: CGFloat
    ) -> CGSize {
        let hostInsets = DroppyShellMetrics.shelfContentInsets(
            usesNotchStyle: !usesIslandCurvature,
            notchHeight: notchHeight
        )
        let slot = DroppyShellMetrics.shelfWidgetSlotInset
        return CGSize(
            width: widgetSize.width + hostInsets.leading + hostInsets.trailing + slot * 2,
            height: widgetSize.height + hostInsets.top + hostInsets.bottom + slot * 2
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The shelf's chrome: the host's own surface over the shell's
            // black, so a glass theme melts from black the way it does on the
            // notch, and a black theme is black.
            shell.fill(.black)
            hostSurface

            TranslateWidget(
                model: PreviewSample.widgetModel(model, showsResult: false),
                requestCapture: {},
                requestSelection: {},
                cancelSelection: {},
                shelfStep: .compact
            )
            .padding(widgetInsets)
            .frame(width: widgetSize.width, height: widgetSize.height)
            .padding(shellInsets)

            if !model.shelfUsesIslandCurvature {
                housing
                    .frame(width: model.notchCutoutWidth, height: model.notchCutoutHeight)
                    .frame(width: size.width, alignment: .center)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shell)
        // The picture follows the appearance Droppy is drawing its surfaces
        // in, so the glass on the shelf reads the app's own theme.
        .environment(\.colorScheme, model.surfaceColorScheme)
    }

    private var size: CGSize {
        Self.previewSize(
            widgetSize: widgetSize,
            usesIslandCurvature: model.shelfUsesIslandCurvature,
            notchHeight: model.notchCutoutHeight
        )
    }

    /// The host's own surface over the shell. On the island the shell is the
    /// host's own rounded rectangle, so the surface is drawn whole; a hardware
    /// notch has a shell of its own shape, and the surface is clipped to it.
    @ViewBuilder
    private var hostSurface: some View {
        if model.shelfUsesIslandCurvature {
            HostGlassSurface(cornerRadius: DroppyShellMetrics.expandedIslandCornerRadius)
        } else {
            ThemedHostSurfacePreview(
                shell: shell,
                cornerRadius: DroppyShellMetrics.expandedShelfCornerRadius
            )
        }
    }

    private var shellInsets: EdgeInsets {
        let hostInsets = DroppyShellMetrics.shelfContentInsets(
            usesNotchStyle: !model.shelfUsesIslandCurvature,
            notchHeight: model.notchCutoutHeight
        )
        let slot = DroppyShellMetrics.shelfWidgetSlotInset
        return EdgeInsets(
            top: hostInsets.top + slot,
            leading: hostInsets.leading + slot,
            bottom: hostInsets.bottom + slot,
            trailing: hostInsets.trailing + slot
        )
    }

    private var widgetInsets: EdgeInsets {
        let inset: CGFloat = model.shelfUsesIslandCurvature ? 0 : DroppySpacing.sm
        return EdgeInsets(top: inset, leading: inset, bottom: inset, trailing: inset)
    }

    private var shell: AnyShape {
        if model.shelfUsesIslandCurvature {
            return AnyShape(RoundedRectangle(
                cornerRadius: DroppyShellMetrics.expandedIslandCornerRadius,
                style: .continuous
            ))
        }
        return AnyShape(DroppyNotchShellShape(
            topCornerRadius: DroppyShellMetrics.expandedNotchTopRadius,
            bottomRadius: DroppyShellMetrics.expandedShelfCornerRadius
        ))
    }

    private var housing: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: DroppyShellMetrics.closedNotchBottomRadius(height: model.notchCutoutHeight),
            bottomTrailingRadius: DroppyShellMetrics.closedNotchBottomRadius(height: model.notchCutoutHeight),
            topTrailingRadius: 0,
            style: .continuous
        )
        .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        .allowsHitTesting(false)
    }
}

/// The host's own surface, in the shape of the shelf's chrome.
///
/// In Droppy this is the themed glass, and it follows the app's theme. It is
/// drawn over whatever is behind the picture, so the glass melts into the
/// page the way it melts into the desktop, and the app's own raised wash on
/// top of it is what makes the card read as a surface instead of a hole.
private struct ThemedHostSurfacePreview: View {
    let shell: AnyShape
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if DroppyKitSurfaceBridge.panelSurfaceProvider == nil {
                // Standalone previews have no host theme provider; the black
                // under it is then the whole surface.
                shell.fill(.black)
            } else {
                DroppyPanelSurface(cornerRadius: cornerRadius)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
