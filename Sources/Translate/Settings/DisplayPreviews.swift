import AppKit
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

/// The droplet's own surface, cut to the card's outline, on the preview's
/// wallpaper stage so the glass melts from the desktop the user actually has.
/// The side panel's picture carries the panel's own shade and dark edge.
private struct PreviewCardFace: View {
    let shape: AnyShape
    var panelEdge = false

    var body: some View {
        SidePanelCardSurface(
            shape: shape,
            shade: panelEdge ? SidePanelCardSurface.panelShade : 0,
            edgeOpacity: panelEdge ? SidePanelCardSurface.panelEdgeOpacity : 0,
            keepsBodyRim: panelEdge
        )
    }
}

/// The host's floating-panel surface, on the preview's wallpaper stage so a
/// glass theme melts from the desktop rather than from the settings page.
private struct PreviewPanelFace: View {
    var body: some View {
        DroppyPanelSurface(cornerRadius: panelRadius)
    }
}

/// The desktop picture behind the picture's surface. A wallpaper that is not a
/// still image (a solid colour or an aerial) leaves the black, so the glass
/// still has something to melt from.
private struct WallpaperFill: View {
    let image: NSImage?
    let shape: AnyShape

    var body: some View {
        GeometryReader { geo in
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    Color.black
                }
            }
            .clipShape(shape)
        }
    }
}

/// The user's current desktop picture, read from the screen the settings
/// window is on. Nil when the wallpaper is not a file-backed still image.
@MainActor
private enum DesktopWallpaper {
    static func current() -> NSImage? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first,
              let url = NSWorkspace.shared.desktopImageURL(for: screen)
        else { return nil }
        return NSImage(contentsOf: url)
    }
}

/// One destination drawn inside the host's shell and surface. Inert: the
/// pickers above choose, and nothing here changes a setting.
struct ResultDisplayPreview: View {
    let display: ResultDisplay
    @ObservedObject var model: TranslateModel

    /// The widest a picture draws; the stage around it fills the settings
    /// column, so every place reads at one size.
    static let stageWidth: CGFloat = 440
    /// The air the picture keeps above and below it on the stage.
    private static let stageAir: CGFloat = 20
    /// The stage's free corners; the screen edge stays square.
    private static let stageRadius: CGFloat = DroppyRadius.lx

    @State private var wallpaper: NSImage?

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
        let height = Self.surfaceHeight(display, model: preview, look: look)
        // The edge panel hangs from a screen edge, so the picture sits on the
        // stage's own edge instead of floating away from it.
        let edge: Alignment = display == .sidePanel
            ? (look.side == .left ? .leading : .trailing)
            : .center
        return drawing(preview, look: look)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            // Scale after layout so the shell and its contents keep their
            // proportions together.
            .scaleEffect(scale, anchor: .center)
            .frame(width: width * scale, height: height * scale, alignment: .top)
            .padding(.vertical, Self.stageAir)
            .frame(maxWidth: .infinity, alignment: edge)
            // Every surface shares one stage, so the wallpaper behind the
            // examples is the same size whichever destination is chosen.
            .frame(height: Self.stageHeight(model: preview, look: look), alignment: .center)
            // The stage fills the settings column, so the wallpaper shows
            // around the picture instead of only under it.
            .background {
                WallpaperFill(image: wallpaper, shape: stageShape(look: look))
            }
            .onAppear {
                if wallpaper == nil { wallpaper = DesktopWallpaper.current() }
            }
    }

    /// The stage's outline: a card, with the side panel's screen edge square.
    private func stageShape(look: PreviewLook) -> AnyShape {
        guard display == .sidePanel else {
            return AnyShape(RoundedRectangle(cornerRadius: Self.stageRadius, style: .continuous))
        }
        let radius = Self.stageRadius
        return AnyShape(UnevenRoundedRectangle(
            topLeadingRadius: look.side == .left ? 0 : radius,
            bottomLeadingRadius: look.side == .left ? 0 : radius,
            bottomTrailingRadius: look.side == .left ? radius : 0,
            topTrailingRadius: look.side == .left ? 0 : radius,
            style: .continuous
        ))
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

    /// The picture's own height; the stage below takes the tallest of the
    /// three, so switching destination never changes the wallpaper's size.
    @MainActor
    private static func surfaceHeight(
        _ display: ResultDisplay,
        model: TranslateModel,
        look: PreviewLook
    ) -> CGFloat {
        switch display {
        case .normal:
            let widget = ShelfWidgetSurfacePreview.widgetSize(for: model, look: look)
            return ShelfWidgetSurfacePreview.previewSize(widgetSize: widget, look: look).height
        case .panel:
            return PreviewSample.bodyHeight(model)
        case .sidePanel:
            return SidePanel.cardHeight(forBody: PreviewSample.bodyHeight(model))
        }
    }

    /// The one stage all three surfaces share, in the current look and page,
    /// so the wallpaper is drawn at the same size in every picture.
    @MainActor
    private static func stageHeight(model: TranslateModel, look: PreviewLook) -> CGFloat {
        ResultDisplay.allCases.reduce(Self.stageAir * 2) { tallest, display in
            let width = surfaceWidth(display, model: model, look: look)
            let height = surfaceHeight(display, model: model, look: look)
            return max(tallest, height * scale(forWidth: width) + Self.stageAir * 2)
        }
    }

    /// No picture draws wider than the column's worth; the stage around it
    /// fills the column.
    private static func scale(forWidth width: CGFloat) -> CGFloat {
        guard width > 0 else { return 1 }
        return min(1, stageWidth / width)
    }

    @ViewBuilder
    private func drawing(
        _ preview: TranslateModel,
        look: PreviewLook
    ) -> some View {
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
            PreviewPanelFace()
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
                y: SidePanelCardShape.filletExtent + SidePanelContentView.inset
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
            shape: AnyShape(SidePanelUnifiedShape(reveal: 1, stretch: 1)),
            panelEdge: true
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
            height: contentHeight(for: model) + SidePanelContentView.shelfContentInsetBudget
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

    /// The room inside the widget's own padding: the whole rectangle less the
    /// 8pt it keeps top and bottom under a notch.
    private var contentHeight: CGFloat {
        Self.widgetSize(for: model, look: look).height - Self.verticalInset(look) * 2
    }

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
