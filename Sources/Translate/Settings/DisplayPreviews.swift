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

    /// A real model preloaded with the example, so every picture is drawn by
    /// the surface's own view, in the user's languages and with the page they
    /// chose.
    @MainActor
    static func widgetModel(_ model: TranslateModel) -> TranslateModel {
        let sample = forTarget(model.targetID)
        let preview = TranslateModel()
        preview.beginPreview(
            source: sample.sourceLanguage,
            target: model.targetID,
            text: sample.source,
            translated: sample.result,
            page: model.resultPage
        )
        return preview
    }

    /// The body the example's card holds: the input at the shelf's floor
    /// beside the result, or the result alone.
    @MainActor
    static func bodyHeight(_ model: TranslateModel) -> CGFloat {
        let alone = !model.resultPage.showsOriginal
        let box = SidePanelContentView.shelfBoxFloor
        return SidePanelContentView.bodyHeight(
            forBox: alone ? 0 : box,
            result: true,
            resultHeight: SidePanelContentView.restingResultHeight(
                for: model,
                alone: alone,
                matching: box
            )
        )
    }
}

/// The shape and theme the host draws the example in. Copied from the model,
/// so a picture holds the example's words and nothing else.
private struct PreviewLook {
    var colorScheme: ColorScheme
    var side: SidePanelSide
    var usesIslandCurvature: Bool
    var notchWidth: CGFloat
    var notchHeight: CGFloat
}

/// The droplet's own surface, cut to the card's outline, with black under
/// the host's glass so it melts from black as it does on screen.
private struct PreviewCardFace: View {
    let shape: AnyShape

    var body: some View {
        ZStack {
            shape.fill(.black)
            SidePanelCardSurface(shape: shape)
        }
    }
}

/// One destination drawn inside the host's shell and surface. Inert: the
/// pickers above choose, and nothing here changes a setting.
struct ResultDisplayPreview: View {
    let display: ResultDisplay
    @ObservedObject var model: TranslateModel

    /// One stage for every picture, so switching the place never changes how
    /// large the example reads. Its width is the settings column's worth.
    static let stageWidth: CGFloat = 440

    var body: some View {
        let preview = PreviewSample.widgetModel(model)
        let look = PreviewLook(
            colorScheme: model.surfaceColorScheme,
            side: model.sidePanelSide,
            usesIslandCurvature: model.shelfUsesIslandCurvature,
            notchWidth: model.notchCutoutWidth,
            notchHeight: model.notchCutoutHeight
        )
        let width = Self.surfaceWidth(display, model: preview, look: look)
        let scale = Self.scale(forWidth: width)
        // The edge panel hangs from a screen edge, so the picture sits on the
        // stage's own edge instead of floating away from it.
        let edge: Alignment = display == .sidePanel
            ? (look.side == .left ? .leading : .trailing)
            : .center
        return drawing(preview, look: look)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            // Scale after layout so the shell and its contents keep their
            // proportions together. The anchor keeps the picture's top edge
            // where it was, so the row below it stays put.
            .scaleEffect(scale, anchor: .top)
            .frame(width: width * scale, alignment: .top)
            .frame(maxWidth: .infinity, alignment: edge)
    }

    private static func surfaceWidth(_ display: ResultDisplay, model: TranslateModel, look: PreviewLook) -> CGFloat {
        switch display {
        case .normal:
            let widget = ShelfWidgetSurfacePreview.widgetSize(for: model, look: look)
            return ShelfWidgetSurfacePreview.previewSize(widgetSize: widget, look: look).width
        case .panel, .sidePanel:
            return SidePanel.expandedWidth
        }
    }

    /// The picture fills the stage's width; no picture is ever widened past
    /// its own pixels.
    private static func scale(forWidth width: CGFloat) -> CGFloat {
        guard width > 0 else { return 1 }
        return min(1, stageWidth / width)
    }

    @ViewBuilder
    private func drawing(_ preview: TranslateModel, look: PreviewLook) -> some View {
        switch display {
        case .normal:
            ShelfWidgetSurfacePreview(model: preview, look: look)
        case .panel:
            FloatingSurfacePreview(model: preview, look: look)
        case .sidePanel:
            SidePanelSurfacePreview(model: preview, look: look)
        }
    }
}

/// The droplet's own floating panel: the edge panel's card in the panel's
/// rounded outline, with the result in it.
private struct FloatingSurfacePreview: View {
    @ObservedObject var model: TranslateModel
    let look: PreviewLook
    @State private var chip = SidePanelChipState()
    @State private var pin = SidePanelPinState()
    /// The body the card's own content reports, so the picture fits the real
    /// card instead of a height guessed from the sample.
    @State private var reportedBody: CGFloat = 0

    private var bodyHeight: CGFloat {
        max(PreviewSample.bodyHeight(model), reportedBody)
    }

    private var cardSize: CGSize {
        CGSize(width: SidePanel.expandedWidth, height: bodyHeight)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            PreviewCardFace(
                shape: AnyShape(
                    RoundedRectangle(cornerRadius: panelRadius, style: .continuous)
                )
            )
            .frame(width: cardSize.width, height: cardSize.height)
            FloatingPanelBody(
                model: model,
                chip: chip,
                pin: pin,
                onBodyHeight: { height, _ in
                    if abs(height - reportedBody) > 0.5 { reportedBody = height }
                },
                translationOnly: !model.resultPage.showsOriginal
            )
            .frame(width: cardSize.width, height: cardSize.height)
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .environment(\.colorScheme, look.colorScheme)
    }
}

/// The droplet's own edge panel: the card that opens out of the screen's edge
/// with the result in it, on the edge the user chose.
private struct SidePanelSurfacePreview: View {
    @ObservedObject var model: TranslateModel
    let look: PreviewLook
    @State private var chip = SidePanelChipState()
    @State private var pin = SidePanelPinState()
    /// The body the card's own content reports, so the picture fits the real
    /// card instead of a height guessed from the sample.
    @State private var reportedBody: CGFloat = 0

    private var bodyHeight: CGFloat {
        max(PreviewSample.bodyHeight(model), reportedBody)
    }

    private var cardSize: CGSize {
        CGSize(
            width: SidePanel.expandedWidth,
            height: SidePanel.cardHeight(forBody: bodyHeight)
        )
    }

    private var contentSize: CGSize {
        CGSize(
            width: SidePanel.expandedWidth - SidePanelContentView.sideInset * 2,
            height: SidePanelContentView.contentHeight(forBody: bodyHeight)
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            card
            // The live window's own hosting frame: the card's content inset,
            // below the fillet that melts it into the screen edge.
            SidePanelContentView(
                model: model,
                chip: chip,
                pin: pin,
                requestCapture: {},
                requestSelection: {},
                cancelSelection: {},
                boxFloor: SidePanelContentView.shelfBoxFloor,
                boxCap: SidePanelContentView.floatingBoxCap,
                translationOnly: !model.resultPage.showsOriginal,
                fitsResult: true,
                maxBodyHeight: SidePanelContentView.floatingMaxBodyHeight,
                onClose: {},
                onPin: {},
                onBodyHeight: { height, _ in
                    if abs(height - reportedBody) > 0.5 { reportedBody = height }
                }
            )
            .frame(width: contentSize.width, height: contentSize.height, alignment: .topLeading)
            .offset(
                x: SidePanelContentView.sideInset,
                y: SidePanelCardShape.filletRadius + SidePanelContentView.inset
            )
        }
        // The panel's chrome is Droppy's dark glass, whatever the system is set
        // to, so its tiles and controls read the app's own appearance.
        .environment(\.colorScheme, look.colorScheme)
        .frame(width: cardSize.width, height: cardSize.height, alignment: .topLeading)
    }

    /// The card and its face, mirrored to the chosen edge. The content is not
    /// mirrored: it is already laid out for either side.
    private var card: some View {
        PreviewCardFace(
            shape: AnyShape(SidePanelUnifiedShape(reveal: 1, stretch: 1))
        )
        .frame(width: cardSize.width, height: cardSize.height, alignment: .topLeading)
        .scaleEffect(x: look.side == .left ? -1 : 1, y: 1)
    }
}

/// The widget inside the host's expanded shell. The preview adds the host
/// chrome; the widget keeps the insets `ShelfWidgetContext` supplies.
private struct ShelfWidgetSurfacePreview: View {
    @ObservedObject var model: TranslateModel
    let look: PreviewLook
    @State private var chip = SidePanelChipState()

    /// The width the widget declares to the host.
    static let widgetWidth: CGFloat = SidePanelContentView.shelfSoloWidth
    /// The droplet's own inset inside the widget rectangle, on every shape.
    static let contentInset: CGFloat = SidePanelContentView.shelfBoxInset
    static var contentWidth: CGFloat { widgetWidth - contentInset * 2 }
    /// The widget's height budget: 8pt top and bottom under a notch, none on
    /// a solo island card.
    static func verticalInset(_ look: PreviewLook) -> CGFloat {
        look.usesIslandCurvature ? 0 : DroppySpacing.sm
    }

    static func contentHeight(for model: TranslateModel) -> CGFloat {
        PreviewSample.bodyHeight(model) - SidePanelContentView.inset * 2
    }

    static func widgetSize(for model: TranslateModel, look: PreviewLook) -> CGSize {
        CGSize(
            width: widgetWidth,
            height: contentHeight(for: model) + verticalInset(look) * 2
        )
    }

    /// The shell the host draws around the widget rectangle: its own side
    /// insets, the cutout clearance on a notch, and the 1.5pt slot on every
    /// edge.
    static func previewSize(widgetSize: CGSize, look: PreviewLook) -> CGSize {
        let hostInsets = DroppyShellMetrics.shelfContentInsets(
            usesNotchStyle: !look.usesIslandCurvature,
            notchHeight: look.notchHeight
        )
        let slot = DroppyShellMetrics.shelfWidgetSlotInset * 2
        return CGSize(
            width: widgetSize.width + hostInsets.leading + hostInsets.trailing + slot,
            height: widgetSize.height + hostInsets.top + hostInsets.bottom + slot
        )
    }

    private var size: CGSize {
        Self.previewSize(widgetSize: Self.widgetSize(for: model, look: look), look: look)
    }

    private var contentHeight: CGFloat { Self.contentHeight(for: model) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The host's shelf chrome in Droppy's theme, read here so the
            // picture never shows the launcher's glass over the page's grey.
            PreviewCardFace(shape: shell)

            SidePanelContentView(
                model: model,
                chip: chip,
                requestCapture: {},
                requestSelection: {},
                cancelSelection: {},
                boxFloor: SidePanelContentView.shelfBoxFloor,
                boxCap: SidePanelContentView.shelfBoxCap,
                translationOnly: !model.resultPage.showsOriginal,
                keepsGripInsideCard: true,
                maxBodyHeight: contentHeight,
                rowWidth: min(SidePanelContentView.defaultRowWidth, Self.contentWidth),
                mountWidth: Self.contentWidth,
                onShelfGripTap: {},
                onSubmit: {},
                onClear: {},
                onClose: {},
                onShelfContentHeight: { _ in }
            )
            .frame(width: Self.contentWidth, height: contentHeight, alignment: .topLeading)
            .padding(EdgeInsets(
                top: Self.verticalInset(look),
                leading: Self.contentInset,
                bottom: Self.verticalInset(look),
                trailing: Self.contentInset
            ))
            .padding(shellInsets)

            if !look.usesIslandCurvature {
                housing
                    .frame(width: look.notchWidth, height: look.notchHeight)
                    .frame(width: size.width, alignment: .center)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shell)
        // The picture follows the appearance Droppy is drawing its surfaces
        // in, so the glass on the shelf reads the app's own theme.
        .environment(\.colorScheme, look.colorScheme)
    }

    private var shellInsets: EdgeInsets {
        let hostInsets = DroppyShellMetrics.shelfContentInsets(
            usesNotchStyle: !look.usesIslandCurvature,
            notchHeight: look.notchHeight
        )
        let slot = DroppyShellMetrics.shelfWidgetSlotInset
        return EdgeInsets(
            top: hostInsets.top + slot,
            leading: hostInsets.leading + slot,
            bottom: hostInsets.bottom + slot,
            trailing: hostInsets.trailing + slot
        )
    }

    private var shell: AnyShape {
        if look.usesIslandCurvature {
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
            bottomLeadingRadius: DroppyShellMetrics.closedNotchBottomRadius(height: look.notchHeight),
            bottomTrailingRadius: DroppyShellMetrics.closedNotchBottomRadius(height: look.notchHeight),
            topTrailingRadius: 0,
            style: .continuous
        )
        .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        .allowsHitTesting(false)
    }
}
