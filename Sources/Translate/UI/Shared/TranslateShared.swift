import AppKit
import DroppyKit
import SwiftUI

/// Shared pieces of the shelf and result page: the status line, the language
/// menu, a round tile button, and the tile and accessibility styling.
@MainActor
func statusMessage(for model: TranslateModel) -> String? {
    let key: String?
    switch model.status {
    case .needsDownload:
        return String(
            format: L10n.tr("status.downloadPair"),
            model.name(for: model.preparedSource),
            model.name(for: model.targetID)
        )
    case .unsupported:
        return String(
            format: L10n.tr("status.unsupportedPair"),
            model.name(for: model.preparedSource),
            model.name(for: model.targetID)
        )
    case .undetected: key = "undetected"
    case .failed: key = "failed"
    case .osTooOld: key = "old"
    case .sameLanguage: key = "same"
    case .idle, .translating: key = nil
    }
    return key.map { L10n.tr("status.\($0)") }
}

@MainActor
func sourceLabel(for model: TranslateModel) -> String {
    guard model.sourceID == TranslateModel.auto else { return model.name(for: model.sourceID) }
    guard let detected = model.detected else { return L10n.tr("auto") }
    return model.name(for: detected)
}

/// The language row's label. The chip lights the half, so the words stay where
/// the layout put them.
struct PillLanguageLabel: View {
    var text: String
    /// The row's hovered side takes the theme highlight colour.
    var highlighted = false
    var fontSize: CGFloat = 13
    /// The edge of its half the label hugs. The panel centres each label in
    /// its own half; the shelf's shared pill stays centred too.
    var alignment: Alignment = .center
    /// The air the label keeps from that edge.
    var edgeInset: CGFloat = 0

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(
                highlighted
                    ? AdaptiveColors.selectionBlueAuto
                    : AdaptiveColors.notchSurfacePrimaryText.opacity(0.92)
            )
            .cardTextShadow()
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, edgeInset)
            .frame(maxWidth: .infinity, minHeight: LanguageMenu.pillRowHeight, alignment: alignment)
            .contentShape(Rectangle())
    }
}

struct LanguageMenu: View {
    @ObservedObject var model: TranslateModel
    var selection: Binding<String>
    var includesAuto: Bool
    var label: String
    /// The edge panel's row draws one shared capsule behind both menus, so the
    /// label brings no glass chrome of its own.
    var inPillRow = false
    /// The row's hovered side takes the theme highlight colour.
    var highlighted = false
    /// The edge panel draws its row larger than the shelf's small pill.
    var fontSize: CGFloat = 13
    /// The edge panel centres each label in its own half of the row.
    var alignment: Alignment = .center
    /// The air the panel's label keeps from its half's edges.
    var edgeInset: CGFloat = 0
    /// The edge panel's chip lights this control. The label stands on the
    /// row's glass, so the mark leaves the words where they are.
    var chipTarget: SidePanelChipTarget? = nil
    /// The languages whose pair is downloaded. Nil keeps every supported one.
    var availableIDs: Set<String>? = nil
    /// Draws a card's lone picker at the footer's measured height, wearing the
    /// row's own label so it reads as the same control as the row's languages.
    var footerPill = false

    /// The edge panel's row height, shared with its capsule background. It is
    /// the footer's pill height, so a language pill and the Paste pill read as
    /// one size.
    static let pillRowHeight: CGFloat = PanelFooterMetrics.disc

    @Environment(\.sidePanelChip) private var chip

    var body: some View {
        // Keep AppKit's native menu tracking; only the trigger is styled.
        Group {
            if inPillRow {
                menu
                    .menuIndicator(.hidden)
                    .buttonStyle(PanelPressStyle())
            } else if footerPill {
                menu
                    .menuIndicator(.hidden)
                    .buttonStyle(PanelPressStyle())
                    // Outside the menu's own inset, so the glass is the copy
                    // pill's height to the point rather than the kit's 30.3.
                    .frame(height: PanelFooterMetrics.disc)
                    .contentShape(Capsule(style: .continuous))
                    .background {
                        Color.clear
                            .droppyGlassControlChrome(shape: AnyShape(Capsule(style: .continuous)))
                    }
            } else {
                menu
                    .menuIndicator(.hidden)
                    .buttonStyle(DroppyQuietButtonStyle(size: .small))
            }
        }
    }

    /// The rows the menu offers: downloaded languages, plus the current choice
    /// so the trigger and its list never disagree.
    static func offered(
        _ languages: [LanguageOption],
        installed: Set<String>?,
        current: String
    ) -> [LanguageOption] {
        guard let installed else { return languages }
        return languages.filter { installed.contains($0.id) || $0.id == current }
    }

    private var offeredLanguages: [LanguageOption] {
        Self.offered(model.languages, installed: availableIDs, current: selection.wrappedValue)
    }

    private var pillLabel: some View {
        PillLanguageLabel(
            text: label,
            highlighted: highlighted,
            fontSize: fontSize,
            alignment: alignment,
            edgeInset: edgeInset
        )
    }

    private var menu: some View {
        Menu {
            if includesAuto {
                Button(L10n.tr("auto")) { selection.wrappedValue = TranslateModel.auto }
                Divider()
            }
            ForEach(offeredLanguages) { language in
                Button(language.menuName) { selection.wrappedValue = language.id }
            }
            if model.canDownloadLanguages {
                Divider()
                Button(L10n.tr("language.download")) {
                    model.openLanguageDownloadSettings()
                }
            }
        } label: {
            if inPillRow {
                pillLabel
            } else if footerPill {
                // The pill is as wide as its word, not the card: the label's
                // stretch fills a half in the row, but here there is no half.
                pillLabel.fixedSize(horizontal: true, vertical: false)
            } else {
                Text(label)
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText.opacity(0.92))
                    .cardTextShadow()
            }
        }
    }
}

/// The panel footer's controls: the more disc and the air inside it.
enum PanelFooterMetrics {
    /// The dots' box inside the disc, so they never touch its rim.
    static let control: CGFloat = 24
    /// The more disc's glass. The chip marks it edge to edge, so the hover is
    /// the button's own circle rather than a smaller mark inside it.
    static let disc: CGFloat = 30
    /// The rim the dots keep inside the disc, and the rim a language label
    /// keeps around its mark.
    static var chipInset: CGFloat { (disc - control) / 2 }
    /// The air above the disc, between it and the boxes or the open menu.
    static let rim: CGFloat = 6
    /// The footer's height, shared so the menu's glass can start on the disc.
    static var footerHeight: CGFloat { disc + rim }
    /// The engine capsule: a little shorter than the disc, so the footer's
    /// trailing control reads as a chip rather than a second disc.
    static let engineHeight: CGFloat = 24
}

/// The more disc's glyph, drawn once on the button's own glass.
struct PanelMoreGlyph: View {
    var iconFont: CGFloat
    /// Turns the dots upright while the menu is open, the way the disc would
    /// turn to face the tools above it.
    var rotation: Double = 0

    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: iconFont))
            .foregroundStyle(AdaptiveColors.primaryTextAuto.opacity(0.92))
            .rotationEffect(.degrees(rotation))
    }
}

/// Collapsed to a 3-dot disc; tap slides capture/select/pin out. The shelf fans
/// sideways, the edge panel opens upward. The disc stays put, so show/hide is a
/// glide; pin toggles immediately because the host rebuild resets this view.
struct ToolbarCapsule: View {
    /// Which way the tools fan out. The shelf keeps them beside the disc; the
    /// edge panel opens them upward from its footer.
    enum Fan { case trailing, leading, up }

    @ObservedObject var model: TranslateModel
    var requestCapture: () -> Void = {}
    var requestSelection: () -> Void = {}
    var cancelSelection: () -> Void = {}
    var fan: Fan = .trailing
    /// The edge panel's footer is larger than the shelf's row; the discs, the
    /// glass and the glyphs follow this.
    var scale: CGFloat = 1
    /// The edge panel opens the tools on hover; the shelf keeps the click.
    var onMoreHover: ((Bool) -> Void)?
    /// The edge panel's chip marks this control.
    var chipTarget: SidePanelChipTarget? = nil
    @State private var expanded = false
    @Environment(\.sidePanelChip) private var chip

    /// Match the language label's timing for show, hide and rotation.
    private static let transitionAnim = DroppyAnimation.state
    private var buttonHeight: CGFloat { 20 * scale }
    private var verticalChromePadding: CGFloat { 10 * scale }

    private var pillWidth: CGFloat { 24 * scale }
    private var labelWidth: CGFloat { 8 * scale }
    private var iconHeight: CGFloat { 8 * scale }
    private var buttonSpacing: CGFloat { 4 * scale }
    private var collapsedBackgroundExtraWidth: CGFloat { 6 * scale }
    private var expandedBackgroundExtraWidth: CGFloat { 10 * scale }
    private var slotOffset: CGFloat { pillWidth + buttonSpacing }
    private var rowWidth: CGFloat { 3 * pillWidth + 2 * buttonSpacing }
    /// The collapsed disc's diameter: the tool height plus the chrome's air.
    /// The panel's disc is larger than its chip, so the mark sits inside it.
    private var discDiameter: CGFloat {
        fan == .up ? PanelFooterMetrics.disc : buttonHeight + verticalChromePadding
    }
    /// The glyphs ride the kit's small style, so its 12pt needs the same lift.
    private var iconFont: CGFloat { 12 * scale }

    /// Collapsed offset factor: 0 in place, ±1 back at the chained start slot.
    private func restOffset(expanded: Bool) -> CGFloat {
        if expanded { return 0 }
        return fan == .trailing ? 1 : -1
    }

    /// Stagger show pin → select → capture; hide together so buttons and
    /// background finish on the same clock. Step 0 = pin, 2 = capture.
    private static func animFor(expanded: Bool, step: Int) -> Animation {
        expanded ? transitionAnim.delay(Double(step) * 0.08) : transitionAnim
    }

    var body: some View {
        if fan == .up {
            panelMore
        } else {
            HStack(spacing: buttonSpacing) {
                if fan == .leading { shelfMoreButton }
                toolsRow
                if fan == .trailing { shelfMoreButton }
            }
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .frame(
                            width: geometry.size.width + (expanded ? expandedBackgroundExtraWidth : collapsedBackgroundExtraWidth),
                            height: buttonHeight + verticalChromePadding
                        )
                        .droppyGlassControlChrome(shape: AnyShape(Capsule()))
                        .offset(
                            // Collapsed, the chrome is centred on the disc; expanded,
                            // it overhangs the whole row evenly.
                            x: expanded
                                ? -expandedBackgroundExtraWidth / 2
                                : (fan == .trailing
                                    ? geometry.size.width - pillWidth / 2
                                    : pillWidth / 2)
                                    - (geometry.size.width + collapsedBackgroundExtraWidth) / 2,
                            y: -verticalChromePadding / 2
                        )
                }
            }
            .animation(Self.transitionAnim, value: expanded)
            .offset(x: fan == .trailing ? -5 : 0, y: 0)
        }
    }

    /// The tools that fan out from the disc, in one frame whose width drives
    /// the glide.
    private var toolsRow: some View {
        HStack(spacing: buttonSpacing) {
            captureTool
                .opacity(expanded ? 1 : 0)
                .offset(x: slotOffset * restOffset(expanded: expanded))
                .animation(Self.animFor(expanded: expanded, step: 2), value: expanded)

            selectTool
                .opacity(expanded ? 1 : 0)
                .offset(x: slotOffset * restOffset(expanded: expanded))
                .animation(Self.animFor(expanded: expanded, step: 1), value: expanded)

            pinTool
                .opacity(expanded ? 1 : 0)
                .offset(x: slotOffset * restOffset(expanded: expanded))
                .animation(Self.animFor(expanded: expanded, step: 0), value: expanded)
        }
        .allowsHitTesting(expanded)
        .accessibilityHidden(!expanded)
        .frame(
            width: expanded ? rowWidth : 0,
            alignment: fan == .trailing ? .trailing : .leading
        )
    }

    /// The panel's trigger: one round glass disc. Its menu overlays the card, so
    /// a wide menu never moves the footer. Hover opens it and the disc stays in
    /// sight, turning its dots upright.
    private var panelMore: some View {
        Button {
            if onMoreHover == nil {
                model.isToolbarExpanded.toggle()
            } else {
                model.isToolbarExpanded = true
            }
        } label: {
            ZStack {
                Color.clear
                    .frame(width: discDiameter, height: discDiameter)
                PanelMoreGlyph(
                    iconFont: iconFont,
                    rotation: model.isToolbarExpanded ? 90 : 0
                )
                    // Centred in the chip's frame, so the two copies land on
                    // the same pixels when the pointer takes over.
                    .frame(
                        width: discDiameter - PanelFooterMetrics.chipInset * 2,
                        height: discDiameter - PanelFooterMetrics.chipInset * 2
                    )
                    .animation(DroppyAnimation.state, value: model.isToolbarExpanded)
            }
            .contentShape(Circle())
            .onHover {
                onMoreHover?($0)
            }
        }
        .buttonStyle(PanelPressStyle())
        // The glass sits outside the button's style so the chip marks the disc
        // edge to edge on a frame that never moves.
        .background {
            Color.clear
                .droppyGlassControlChrome(shape: AnyShape(Circle()))
        }
        // The chip marks the disc edge to edge, so the slide effect is the
        // button's own glass.
        .chipTarget(chipTarget)
        .arrowCursorRegion()
        .a11y("a11y.more")
    }

    private var captureTool: some View {
        Button {
            requestCapture()
        } label: {
            Group {
                if model.captureState == .recognizing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "camera.viewfinder")
                }
            }
            .font(.system(size: iconFont))
            .frame(width: labelWidth, height: iconHeight)
        }
        .translateIconPill(height: buttonHeight, width: pillWidth)
        .a11y("a11y.capture")
        .help(L10n.tr("a11y.capture"))
        .disabled(model.captureState != .idle || !model.canCapture)
    }

    private var selectTool: some View {
        Button {
            if model.selectState == .armed {
                cancelSelection()
            } else {
                requestSelection()
            }
        } label: {
            Group {
                if model.selectState == .pulling {
                    ProgressView().controlSize(.small)
                } else if model.selectState == .armed {
                    Image(systemName: "xmark")
                } else {
                    Image(systemName: "character.cursor.ibeam")
                }
            }
            .font(.system(size: iconFont))
            .frame(width: labelWidth, height: iconHeight)
        }
        .translateIconPill(height: buttonHeight, width: pillWidth)
        .a11y("a11y.select")
        .help(L10n.tr(model.selectState == .armed ? "a11y.cancelSelect" : "a11y.select"))
        .disabled(model.selectState == .pulling || (model.selectState != .armed && !model.canSelect))
    }

    private var pinTool: some View {
        Button {
            model.togglePin()
        } label: {
            Image(systemName: model.isPinned ? "pin.fill" : "pin")
                .font(.system(size: iconFont, weight: model.isPinned ? .semibold : .regular))
                .foregroundStyle(model.isPinned ? AdaptiveColors.notchSurfacePrimaryText : AdaptiveColors.notchSurfaceSecondaryText)
                .frame(width: labelWidth, height: iconHeight)
                .scaleEffect(model.isPinned ? 1.2 : 1)
                .rotationEffect(.degrees(model.isPinned ? 0 : 45))
                .contentTransition(.symbolEffect(.replace))
                .animation(DroppyAnimation.state, value: model.isPinned)
        }
        .translateIconPill(height: buttonHeight, width: pillWidth)
        .a11y("a11y.pin")
        .disabled(!model.canPin)
    }

    /// The shelf's disc is a small pill in the row's own glass.
    private var shelfMoreButton: some View {
        Button(action: toggleMore) {
            Image(systemName: "ellipsis")
                .font(.system(size: iconFont))
                .frame(width: labelWidth, height: iconHeight)
                .rotationEffect(.degrees(expanded ? 90 : 0))
                .animation(Self.transitionAnim, value: expanded)
        }
        .translateIconPill(height: buttonHeight, width: pillWidth)
        .a11y("a11y.more")
        .onAppear { expanded = model.isToolbarExpanded }
    }

    private func toggleMore() {
        expanded.toggle()
        model.isToolbarExpanded = expanded
    }
}

/// The menu's glass, one footer taller than the menu so its seed lands on the
/// disc below. At rest the extra strip is clear; while opening or closing it
/// carries the glass out of the button.
struct PanelMenuMorphShape: Shape {
    var progress: CGFloat
    /// The travel from the disc's bottom to the menu's: the footer's height.
    var lift: CGFloat
    var cornerRadius: CGFloat = 20
    var seed: CGFloat = PanelFooterMetrics.disc

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let p = min(max(progress, 0), 1)
        let seed = min(self.seed, rect.width, rect.height)
        let start = CGRect(
            x: rect.minX,
            y: rect.maxY - seed,
            width: seed,
            height: seed
        )
        let end = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: max(rect.height - lift, seed)
        )
        let frame = CGRect(
            x: start.minX + (end.minX - start.minX) * p,
            y: start.minY + (end.minY - start.minY) * p,
            width: start.width + (end.width - start.width) * p,
            height: start.height + (end.height - start.height) * p
        )
        let radius = seed / 2 + (cornerRadius - seed / 2) * p
        return Path(roundedRect: frame, cornerRadius: radius, style: .continuous)
    }
}

/// The panel's more menu: one glass panel, one labeled row per tool. The chip
/// marks the row under the pointer, so the menu draws no glass of its own. It
/// overlays the footer, so the controls never move.
struct PanelMoreMenu: View {
    @ObservedObject var model: TranslateModel
    /// The footer keeps the menu mounted while it folds, so the glass can slide
    /// back into the disc instead of disappearing in one frame.
    var open: Bool
    var requestCapture: () -> Void = {}
    var requestSelection: () -> Void = {}
    var cancelSelection: () -> Void = {}
    /// Reports the pointer over the panel, so the footer's disc can hand the
    /// open menu to it without a gap in between closing it.
    var onHover: ((Bool) -> Void)?
    /// The window the menu belongs to pins itself; the shelf leaves this nil
    /// and pins the shelf through the model.
    var pinned: Bool? = nil
    var onPin: (() -> Void)? = nil

    @State private var progress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The rows, in the order the menu stacks them: settings at the bottom,
    /// over the disc, and capture at the top.
    static let targets: [SidePanelChipTarget] = [
        .menuCapture, .menuSelect, .menuPin, .menuSettings
    ]

    /// The menu's height over the footer: its rows, the air between them and
    /// the inset on either edge.
    static let height: CGFloat =
        CGFloat(targets.count) * PanelToolRow.height
        + CGFloat(targets.count - 1) * rowSpacing
        + edgeInset * 2

    /// One column: the four tools stack over the more disc, like a menu.
    var width: CGFloat {
        PanelToolRow.width + Self.edgeInset * 2
    }
    /// The air a menu row keeps from the next. The chip sits on the row itself,
    /// so the gap only separates the rows; it never has to clear a second glass.
    private static let rowSpacing: CGFloat = DroppySpacing.xsm
    private static let edgeInset: CGFloat = DroppySpacing.xs

    var body: some View {
        tools
            .padding(Self.edgeInset)
            .frame(width: width)
            // The words wait for the circle to open, so the first thing the
            // pointer sees is the glass coming out of the disc.
            .opacity(rowOpacity)
            .background {
                PanelMenuGlass(progress: glassProgress)
                    .allowsHitTesting(false)
            }
            // The panel's own tracking area marks the rows; this only tells the
            // footer whether the pointer is still inside the open menu.
            .onContinuousHover { phase in
                guard open else { return }
                switch phase {
                case .active:
                    onHover?(true)
                case .ended:
                    onHover?(false)
                }
            }
            // The menu stays mounted so it has somewhere to fold back into;
            // the footer only flips `open`.
            .onAppear {
                if open {
                    withAnimation(DroppyAnimation.state) { progress = 1 }
                }
            }
            .onChange(of: open) { _, now in
                withAnimation(DroppyAnimation.state) {
                    progress = now ? 1 : 0
                }
            }
            .allowsHitTesting(open)
            .accessibilityHidden(!open)
            // Reduce Motion keeps the fade but drops the slide: the glass is
            // already the menu's shape, so only the menu's opacity moves.
            .opacity(reduceMotion ? (open ? 1 : 0) : 1)
            .animation(reduceMotion ? DroppyAnimation.state : nil, value: open)
    }

    private var tools: some View {
        VStack(spacing: Self.rowSpacing) {
            tool(.menuCapture, action: requestCapture)
            tool(.menuSelect, action: selectAction)
            tool(.menuPin, action: onPin ?? model.togglePin)
            tool(.menuSettings, action: model.openSettings)
        }
    }

    @ViewBuilder
    private func tool(_ target: SidePanelChipTarget, action: @escaping () -> Void) -> some View {
        if let content = Self.content(
            for: target,
            model: model,
            pinned: pinned,
            pinDisabled: onPin == nil ? !model.canPin : false
        ) {
            PanelToolRow(
                content: content,
                target: open ? target : nil,
                action: action
            )
        }
    }

    private var selectAction: () -> Void {
        {
            if model.selectState == .armed {
                cancelSelection()
            } else {
                requestSelection()
            }
        }
    }

    /// The ink of one row, so the menu and the chip's copy above its glass
    /// never drift apart.
    static func content(
        for target: SidePanelChipTarget,
        model: TranslateModel,
        pinned: Bool? = nil,
        pinDisabled: Bool = false
    ) -> PanelToolRowContent? {
        let showsPinned = pinned ?? model.isPinned
        switch target {
        case .menuCapture:
            return PanelToolRowContent(
                symbol: "camera.viewfinder",
                label: L10n.tr("tool.capture"),
                help: L10n.tr("a11y.capture"),
                a11yKey: "a11y.capture",
                busy: model.captureState == .recognizing,
                disabled: model.captureState != .idle || !model.canCapture
            )
        case .menuSelect:
            let armed = model.selectState == .armed
            return PanelToolRowContent(
                symbol: armed ? "xmark" : "character.cursor.ibeam",
                label: L10n.tr(armed ? "tool.cancel" : "tool.select"),
                help: L10n.tr(armed ? "a11y.cancelSelect" : "a11y.select"),
                a11yKey: armed ? "a11y.cancelSelect" : "a11y.select",
                busy: model.selectState == .pulling,
                disabled: model.selectState == .pulling || (!armed && !model.canSelect)
            )
        case .menuPin:
            return PanelToolRowContent(
                symbol: showsPinned ? "pin.fill" : "pin",
                label: L10n.tr(showsPinned ? "tool.unpin" : "tool.pin"),
                help: L10n.tr("a11y.pin"),
                a11yKey: "a11y.pin",
                disabled: pinDisabled,
                rotation: showsPinned ? 0 : 45
            )
        case .menuSettings:
            return PanelToolRowContent(
                symbol: "gearshape",
                label: L10n.tr("tool.settings"),
                help: L10n.tr("a11y.settings"),
                a11yKey: "a11y.settings"
            )
        default:
            return nil
        }
    }

    private var glassProgress: CGFloat {
        reduceMotion ? 1 : progress
    }

    private var rowOpacity: Double {
        if reduceMotion { return 1 }
        let p = min(max(progress, 0), 1)
        let start: CGFloat = 0.35
        return Double(min(max((p - start) / (1 - start), 0), 1))
    }
}

/// The menu's glass, drawn one footer taller than the menu so its seed lands
/// on the disc below. At rest the extra strip is outside the shape and stays
/// clear; on the way open and closed it carries the glass out of the button.
private struct PanelMenuGlass: View, @MainActor Animatable {
    var progress: CGFloat

    /// `AnyShape` carries no animatable data, so the chrome's morph is rebuilt
    /// from an interpolated progress on every frame instead of snapping.
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    private var lift: CGFloat { PanelFooterMetrics.footerHeight }

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .frame(width: proxy.size.width, height: proxy.size.height + lift)
                .droppyGlassControlChrome(
                    shape: AnyShape(PanelMenuMorphShape(progress: progress, lift: lift))
                )
                // The disc's own glass comes first; the menu's joins once it
                // starts opening, so the two never stack.
                .opacity(Double(min(max(progress, 0) / 0.18, 1)))
        }
    }
}

/// What one row of the more menu draws: its glyph, its word and the state it
/// shows. The menu's row and the chip's copy above the glass both read it.
struct PanelToolRowContent {
    var symbol: String
    var label: String
    var help: String
    var a11yKey: String
    var busy = false
    var disabled = false
    var rotation: Double = 0
}

/// The row's ink: the glyph and its word, laid out once. The row draws it small
/// and dim; the chip draws the same view above its glass, so the two match.
struct PanelToolRowLabel: View {
    var content: PanelToolRowContent
    var opacity: Double

    var body: some View {
        HStack(spacing: 7) {
            Group {
                if content.busy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: content.symbol)
                        .rotationEffect(.degrees(content.rotation))
                }
            }
            .font(.system(size: 13, weight: .medium))
            .frame(width: 15)

            Text(content.label)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .foregroundStyle(AdaptiveColors.primaryTextAuto.opacity(opacity))
        .padding(.horizontal, 8)
    }
}

/// One tool in the panel's more menu: the glyph and its word in a row. The
/// chip marks the row in its own frame.
private struct PanelToolRow: View {
    var content: PanelToolRowContent
    /// Nil while the menu is folded: a hidden row must not publish a chip frame
    /// the pointer can find behind the card.
    var target: SidePanelChipTarget?
    var action: () -> Void

    @Environment(\.sidePanelChip) private var chip

    static let width: CGFloat = 98
    static let height: CGFloat = 30

    var body: some View {
        Button(action: action) {
            PanelToolRowLabel(
                content: content,
                opacity: content.disabled
                    ? 0.4
                    : (target != nil && chip?.target == target ? 1 : 0.78)
            )
            .frame(width: Self.width, height: Self.height)
            .contentShape(Capsule())
        }
        .buttonStyle(PanelPressStyle())
        .chipTarget(target)
        .arrowCursorRegion()
        .help(content.help)
        .a11y(content.a11yKey)
        .disabled(content.disabled)
    }
}

struct TileIconButton: View {
    var symbol: String
    var a11yKey: String
    var diameter: CGFloat = 24
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: diameter, height: diameter)
        }
        .translateCircle(diameter: diameter)
        .a11y(a11yKey)
    }
}

/// The seam wraps the swap button: both tiles cut concentric bites around it,
/// joined to the straight seam by symmetric flares. `titleTab` adds a shallow
/// dip on the top edge for the Translate label.
enum TileMetrics {
    static let cornerRadius: CGFloat = 15
}

struct SeamNotchShape: Shape {
    enum Edge { case top, bottom }
    /// The swap pocket's edge; nil for a plain edge.
    var edge: Edge?
    /// A centred dip on the top edge, independent of `edge`.
    var titleTab: Bool = false
    var cornerRadius: CGFloat = TileMetrics.cornerRadius
    /// The pocket's radius, centred one seam-half-gap beyond the edge, so the
    /// visible rim is symmetric by construction.
    var notchRadius: CGFloat = 24
    /// Entry flare: the straight eases into the circle over this run with
    /// matched end tangents, so the joint has no kink.
    var mouthRadius: CGFloat = 14
    /// The button centre beyond the tile edge; keep in sync with the widget
    /// gap (spacing 1.5 + collapsed swap row).
    var seamOffset: CGFloat = 3.5
    var titleHalfWidth: CGFloat = 55
    var titleDepth: CGFloat = 12

    /// Only the pocket animates (open ↔ closed on expand); the rest stays
    /// fixed so the shape interpolates instead of popping.
    var animatableData: CGFloat {
        get { notchRadius }
        set { notchRadius = newValue }
    }

    /// One smooth bowl between rims: mirrored cubics with horizontal tangents
    /// at both rims and at the centre.
    private func bowl(into path: inout Path, edgeY: CGFloat, cx: CGFloat, halfWidth w: CGFloat, depth d: CGFloat, yDir: CGFloat, xDir: CGFloat) {
        let deepY = edgeY + yDir * d
        path.addCurve(to: CGPoint(x: cx, y: deepY),
                      control1: CGPoint(x: cx - xDir * w * 0.5, y: edgeY),
                      control2: CGPoint(x: cx - xDir * w * 0.5, y: deepY))
        path.addCurve(to: CGPoint(x: cx + xDir * w, y: edgeY),
                      control1: CGPoint(x: cx + xDir * w * 0.5, y: deepY),
                      control2: CGPoint(x: cx + xDir * w * 0.5, y: edgeY))
    }

    /// A true circle around the button, joined to the straight seam by
    /// tangent-matched flares so the boundary never bulges outside the edge.
    private func ringPocket(into path: inout Path, edgeY: CGFloat, cx: CGFloat, radius r: CGFloat, offset o: CGFloat, dipsDown: Bool) {
    let s: CGFloat = dipsDown ? 1 : -1
    let dir: CGFloat = s
    let rho = mouthRadius                       // fillet radius
    // Horizontal distance from the centre to where the straight edge bends.
    let X = sqrt((r + rho) * (r + rho) - (rho + o) * (rho + o))

    // Local coordinates: u along the path, v into the tile.
    func pt(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
        CGPoint(x: cx + dir * u, y: edgeY + s * v)
    }
    func arc(cu: CGFloat, cv: CGFloat, rad: CGFloat, from a0: CGFloat, to a1: CGFloat) {
        let n = max(1, Int(ceil(abs(a1 - a0) / (.pi / 2))))
        let da = (a1 - a0) / CGFloat(n)
        let kk = 4 / 3 * tan(da / 4) * rad
        var a = a0
        for _ in 0..<n {
            let b = a + da
            let p0 = (cu + rad * cos(a), cv + rad * sin(a))
            let p3 = (cu + rad * cos(b), cv + rad * sin(b))
            let c1 = (p0.0 - kk * sin(a), p0.1 + kk * cos(a))
            let c2 = (p3.0 + kk * sin(b), p3.1 - kk * cos(b))
            path.addCurve(to: pt(p3.0, p3.1),
                          control1: pt(c1.0, c1.1),
                          control2: pt(c2.0, c2.1))
            a = b
        }
    }

    path.addLine(to: pt(-X, 0))
    // 1) Left fillet: straight edge → circle.
    arc(cu: -X, cv: rho, rad: rho, from: -.pi / 2, to: atan2(-(o + rho), X))
    // 2) Circle around the button, through its deepest point.
    arc(cu: 0, cv: -o, rad: r, from: atan2(rho + o, -X), to: atan2(rho + o, X))
    // 3) Right fillet: circle → straight edge.
    arc(cu: X, cv: rho, rad: rho, from: atan2(-(o + rho), -X), to: -.pi / 2)
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let minX = rect.minX, minY = rect.minY, maxX = rect.maxX, maxY = rect.maxY
        let radius = min(cornerRadius, rect.width / 2, rect.height / 2)
        let cx = rect.midX
        let nw = min(notchRadius, max(0, rect.width / 2 - radius - 2))
        let k = 0.5522847498 * radius
        // Title tab: wide and shallow, clamped clear of the corners.
        let tw = min(titleHalfWidth, max(0, rect.width / 2 - radius - 10))

        /// Top edge west→east with the optional title dip.
        func topEdge() {
            if titleTab, tw > 0, titleDepth > 0 {
                path.addLine(to: CGPoint(x: cx - tw, y: minY))
                bowl(into: &path, edgeY: minY, cx: cx, halfWidth: tw, depth: titleDepth, yDir: 1, xDir: 1)
            } else {
                path.addLine(to: CGPoint(x: maxX - radius, y: minY))
            }
        }

        path.move(to: CGPoint(x: minX + radius, y: minY))
        // The seam's pocket sits on the edge it runs along; the title dip only
        // belongs to a surface with no seam at all.
        if edge == .top, nw > 0 {
            ringPocket(into: &path, edgeY: minY, cx: cx, radius: nw, offset: min(seamOffset, nw * 0.5), dipsDown: true)
        }
        if edge == nil {
            topEdge()
        } else {
            path.addLine(to: CGPoint(x: maxX - radius, y: minY))
        }
        path.addCurve(to: CGPoint(x: maxX, y: minY + radius),
                      control1: CGPoint(x: maxX - radius + k, y: minY),
                      control2: CGPoint(x: maxX, y: minY + radius - k))
        path.addLine(to: CGPoint(x: maxX, y: maxY - radius))
        path.addCurve(to: CGPoint(x: maxX - radius, y: maxY),
                      control1: CGPoint(x: maxX, y: maxY - radius + k),
                      control2: CGPoint(x: maxX - radius + k, y: maxY))
        if edge == .bottom, nw > 0 {
            ringPocket(into: &path, edgeY: maxY, cx: cx, radius: nw, offset: min(seamOffset, nw * 0.5), dipsDown: false)
        }
        path.addLine(to: CGPoint(x: minX + radius, y: maxY))
        path.addCurve(to: CGPoint(x: minX, y: maxY - radius),
                      control1: CGPoint(x: minX + radius - k, y: maxY),
                      control2: CGPoint(x: minX, y: maxY - radius + k))
        path.addLine(to: CGPoint(x: minX, y: minY + radius))
        path.addCurve(to: CGPoint(x: minX + radius, y: minY),
                      control1: CGPoint(x: minX, y: minY + radius - k),
                      control2: CGPoint(x: minX + radius - k, y: minY))
        path.closeSubpath()
        return path
    }
}

/// A glass surface with the swap pocket cut out of it, so the card's own
/// surface shows through the hole instead of a fill of ours.
struct GlassPocketMask: View {
    var shape: AnyShape
    /// The disc's centre from the surface's top edge; nil leaves the glass whole.
    var centreY: CGFloat?
    var radius: CGFloat = 0
    var topFillet: CGFloat = 0
    var bottomFillet: CGFloat = 0
    /// 1 erases the pocket, 0 leaves the glass in place.
    var erase: Double = 1

    var body: some View {
        ZStack {
            shape.fill(.white)
            if let centreY {
                DiscCutShape(
                    centreY: centreY,
                    radius: radius,
                    topFillet: topFillet,
                    bottomFillet: bottomFillet
                )
                .fill(.black)
                .opacity(erase)
                .blendMode(.destinationOut)
            }
        }
        .compositingGroup()
    }
}

/// The air and the edge fade every box's words share: the shelf's input, the
/// edge panel's input and result, and the floating panel's two boxes.
enum PanelTileText {
    /// Air from a box's side rim. The text views add their 5pt paragraph
    /// indent, so a line starts 13pt from the rim.
    static let sideInset: CGFloat = DroppySpacing.sm
    /// Air above and below the words. The top band is the fade's own height,
    /// so the first line is sharp while the box rests at its top.
    static let verticalAir: CGFloat = 16
    /// The soft band at each rim: the input's 10% at its resting height,
    /// capped so a tall result keeps the same 16pt rim.
    static func fadeBand(for height: CGFloat) -> CGFloat {
        min(verticalAir, height * 0.1)
    }
}

/// The mask that fades a box's words where they meet its glass.
struct PanelTileEdgeFade: View {
    var body: some View {
        GeometryReader { geometry in
            let band = PanelTileText.fadeBand(for: geometry.size.height)
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: band)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: band)
            }
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// Fades this view's top and bottom rim, as a box does with its words.
    func panelTileEdgeFade() -> some View {
        mask { PanelTileEdgeFade() }
    }
}

/// The short capsule that parts the original from its translation, centred in
/// the gap the two boxes already leave.
struct PanelSeamDivider: View {
    var gap: CGFloat

    /// A 3pt dash still reads as a seam, and the centre is counted with it.
    private static let thickness: CGFloat = 3

    var body: some View {
        Capsule(style: .continuous)
            .fill(AdaptiveColors.overlayAuto(0.18))
            .frame(width: 250, height: Self.thickness)
            .frame(maxWidth: .infinity)
            // The overlay pins the capsule's bottom to the box's edge, so half
            // the gap plus half the capsule puts its centre in the gap.
            .offset(y: (gap + Self.thickness) / 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The dark halo under the card's text. Over clear glass the wallpaper shows
/// through the card, and a white glyph alone loses its edge on a bright one.
enum CardTextShadow {
    static let color = Color.black.opacity(0.95)
    static let radius: CGFloat = 4
    static let y: CGFloat = 1.5

    static var nsShadow: NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.95)
        shadow.shadowBlurRadius = radius
        shadow.shadowOffset = NSSize(width: 0, height: -y)
        return shadow
    }
}

extension NSTextView {
    /// The same halo the card's SwiftUI text carries, on every glyph.
    func applyCardTextShadow() {
        typingAttributes[.shadow] = CardTextShadow.nsShadow
        let range = NSRange(location: 0, length: (string as NSString).length)
        textStorage?.addAttribute(.shadow, value: CardTextShadow.nsShadow, range: range)
    }
}

/// Keeps an open panel's glass bright while another app has the keyboard:
/// `acquireKeyAppearance` clears macOS's frost for a non-key window without
/// taking focus. Private selector, so older systems keep the inactive face.
@MainActor
final class PanelKeyAppearance {
    private unowned let panel: NSWindow
    private var held = false

    init(panel: NSWindow) {
        self.panel = panel
    }

    /// The pin decides whether the card stays open, not how it looks: an open
    /// card keeps its face. It is released only when the card folds or hides.
    static func shouldHold(pinned: Bool, shown: Bool) -> Bool {
        shown
    }

    /// Re-asserts on every call: AppKit can drop the appearance as the app and
    /// its windows change key, so the flag alone would leave the card frosted.
    func hold(_ hold: Bool) {
        let selector = NSSelectorFromString(hold ? "acquireKeyAppearance" : "resignKeyAppearance")
        guard panel.responds(to: selector) else { return }
        if hold {
            held = true
            _ = panel.perform(selector)
        } else if held {
            held = false
            _ = panel.perform(selector)
        }
    }
}

/// Restores the light macOS removes from glass in a non-key window when
/// `acquireKeyAppearance` is unavailable: every glass layer dims by a flat
/// 24/255. Read `appearsActive`, not the app's state.
struct PanelGlassLift: ViewModifier {
    @Environment(\.appearsActive) private var appearsActive
    @StateObject private var theme = HostThemeStore()

    func body(content: Content) -> some View {
        content
            .brightness(lift)
            .animation(.easeInOut(duration: 0.2), value: appearsActive)
    }

    /// A black card has no glass to lose the light, and the lift would turn it
    /// grey.
    private var lift: Double {
        guard !appearsActive, theme.current != .black else { return 0 }
        return Self.dimCompensation
    }

    /// The measured drop: the card loses exactly this much in every channel.
    static let dimCompensation: Double = 24.0 / 255.0
}

extension View {
    func a11y(_ key: String) -> some View {
        help(L10n.tr(key)).accessibilityLabel(L10n.tr(key))
    }

    func panelGlassLift() -> some View {
        modifier(PanelGlassLift())
    }

    func cardTextShadow() -> some View {
        shadow(color: CardTextShadow.color, radius: CardTextShadow.radius, y: CardTextShadow.y)
    }

    /// The language row's raised hover capsule, reused on the panel's boxes.
    /// It sits above the tile's glass and under the text: glass over glass
    /// disappears, so it uses the kit's hover wash in the tile's own shape.
    func tileHoverChrome(
        _ hovering: Bool,
        cornerRadius: CGFloat,
        pocket: SidePanelBoxCut? = nil
    ) -> some View {
        background {
            let shape = AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            if let pocket {
                Color.clear
                    .droppyGlassControlChrome(shape: shape, isHovering: true)
                    .mask {
                        GlassPocketMask(
                            shape: shape,
                            centreY: pocket.centreY,
                            radius: pocket.radius,
                            topFillet: pocket.fillet
                        )
                    }
                    .opacity(hovering ? 1 : 0)
                    .animation(DroppyAnimation.state, value: hovering)
                    .allowsHitTesting(false)
            } else {
                Color.clear
                    .droppyGlassControlChrome(shape: shape, isHovering: true)
                    .opacity(hovering ? 1 : 0)
                    // The edge panel's boxes light on the chip's clock, so a box
                    // and a control share one crossfade.
                    .animation(DroppyAnimation.state, value: hovering)
                    .allowsHitTesting(false)
            }
        }
    }
}
