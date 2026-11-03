import DroppyKit
import SwiftUI

/// The expanded edge panel: a language row with the swap disc sunk into its
/// bottom edge, and the shelf's source tile underneath.
struct SidePanelContentView: View {
    @ObservedObject var model: TranslateModel
    /// The panel's sliding chip. The panel owns it, so it can watch the
    /// pointer and bloom the chip over a held control.
    @ObservedObject var chip: SidePanelChipState
    /// The handle's amount. The panel owns it, so the mark on the lobe rides
    /// the lobe while it comes out of the card.
    @ObservedObject var grip: SidePanelGripState
    /// The edge panel's own pin. The shelf has no window to pin, so its menu
    /// keeps the model's shelf hold.
    @ObservedObject var pin: SidePanelPinState
    var requestCapture: () -> Void = {}
    var requestSelection: () -> Void = {}
    var cancelSelection: () -> Void = {}
    /// The pointer is on the handle, or a drag holds it. The panel grows the
    /// card's own outline.
    var onGripOut: (Bool) -> Void = { _ in }
    /// The shelf's card cannot grow, so its handle keeps the bar inside the
    /// card and skips the tab that hangs below the panel's edge.
    var keepsGripInsideCard = false
    /// The floating panel is sized by its content, so it carries no handle.
    var showsGrip = true
    /// True while the display setting shows the translation alone: the
    /// original's box starts folded away. A fitting mount reads the setting
    /// live, so the edge panel follows the picker; the shelf keeps its own.
    var translationOnly = false
    /// The setting as it stands now; the shelf follows it too, so every
    /// surface shows the result face the same way.
    private var translationOnlyNow: Bool {
        !model.resultPage.showsOriginal
    }
    /// The panel fits its result box to the words in every mode; the shelf
    /// keeps the resting box under the input.
    var fitsResult = false
    var glassTiles = true
    /// The tallest body this mount may draw; the shelf's fixed slot and the
    /// edge panel's cap set it.
    var maxBodyHeight = SidePanelContentView.maxPanelBodyHeight
    /// The shortest the input box may get. The shelf keeps the common floor;
    /// the panels pass their own.
    var boxFloor = SidePanelContentView.minBoxHeight
    /// The tallest the input box may get before it scrolls.
    var boxCap = SidePanelContentView.panelMaxBoxHeight
    /// The shelf narrows the language row when it shares a grouped slot.
    var rowWidth = SidePanelContentView.defaultRowWidth
    /// The widget rectangle's width. The shelf fits its result to the words at
    /// the width they will wrap at; the panels use their own card width.
    var mountWidth: CGFloat = 0
    /// Reports the widget rectangle the shelf content needs, without the
    /// host's content inset. The shelf budgets that inset and resizes.
    var onShelfContentHeight: (CGFloat) -> Void = { _ in }
    var onShelfGripTap: (() -> Void)?
    /// Starts a translation. The shelf raises its card so the result has room;
    /// the panel keeps its own submit.
    var onSubmit: (() -> Void)?
    /// Empties the boxes from the footer. The shelf also folds its card back
    /// to the opening step, which the content cannot do itself.
    var onClear: (() -> Void)?

    /// Pins the edge panel's window. Nil on the shelf, whose menu pins the
    /// shelf through the model instead.
    var onPin: (() -> Void)?

    /// The card height this content needs; the window sizes itself to it.
    /// `animated` is false on first layout and while the grip is dragged.
    var onBodyHeight: (CGFloat, Bool) -> Void = { _, _ in }

    /// One line of text plus the editor's insets, so the empty box still has
    /// air above and below the placeholder. The panel's short box.
    static let minBoxHeight: CGFloat = 94
    /// Beyond this the panel's editor scrolls instead of growing.
    static let maxBoxHeight: CGFloat = 154
    /// The default box cap for a mount that does not set its own; with the
    /// resting result it makes the tallest default card.
    static let panelMaxBoxHeight: CGFloat = 151

    /// The input floor shared by the shelf, edge panel and floating panel: the
    /// card grows by this box. It keeps the footer low enough for the open more
    /// menu to fit above it.
    static var shelfBoxFloor: CGFloat {
        PanelMoreMenu.height - (LanguageMenu.pillRowHeight + rowGap)
    }
    static let shelfBoxCap: CGFloat = 150
    /// The cap's own floor: a taller input can never squeeze the answer below
    /// it.
    static let shelfResultFloor: CGFloat = 130
    /// What a full card leaves for the result: the 478pt card minus the
    /// inset, header, gaps and footer.
    static let shelfResultMax: CGFloat = 380
    /// The 16pt a notch card spends on its corner inset. The descriptor
    /// includes it, so the content adds it when it reports its rectangle.
    static let shelfContentInsetBudget: CGFloat = DroppySpacing.sm * 2

    /// The card a shelf input and result need. A zero result is the bare
    /// input; a full card has no input and spends its room on the result.
    static func shelfCardHeight(input: CGFloat, result: CGFloat) -> CGFloat {
        let resultSection = result > 0 ? resultGap + result : 0
        return shelfContentInsetBudget + LanguageMenu.pillRowHeight + rowGap
            + input + resultSection + footerHeight
    }

    /// The opening card: the input's floor and no result.
    static var shelfOpeningCardHeight: CGFloat {
        shelfCardHeight(input: shelfBoxFloor, result: 0)
    }

    /// The tallest result beside an input of `input` points; with no input, the
    /// result takes the full card.
    static func shelfResultCap(input: CGFloat) -> CGFloat {
        max(shelfResultFloor, shelfResultMax - input)
    }

    /// The floating panel uses the same card, so it shares the floor. Its box
    /// scrolls at 150 to stay compact beside a capture.
    static var floatingBoxFloor: CGFloat { shelfBoxFloor }
    static let floatingBoxCap: CGFloat = 150

    /// Equal air above and below the text, so one line lands on mid-height and
    /// the paste and clear discs sit inside the bottom inset.
    private static let editorTopInset: CGFloat = 37.5
    private static let editorBottomInset: CGFloat = 37.5
    /// The translation box under the input at its resting height; the grip
    /// under the card stretches it taller. Below both sits the control strip.
    /// With the shelf's 94pt short box it makes the second card 440pt.
    static let resultBoxHeight: CGFloat = 244
    /// The floating panel's result box fits its words between these, so a short
    /// sentence leaves no empty slab. Beside the input it is at least the input's
    /// height, so the pair reads one size.
    static var floatingResultFloor: CGFloat { floatingBoxFloor }
    static let floatingResultCap: CGFloat = 400
    /// The translation alone is fitted to its words up to this height, on the
    /// shelf and both panels. Past it the box scrolls.
    static let fittedResultCap: CGFloat = 380
    /// The transparent band below the card's face. The window grows by it, and
    /// the drag tab hangs in it.
    static let gripStrip: CGFloat = 36
    /// How far the content reaches below its boxes: the grip strip plus 8pt.
    /// A control outside its hosting view takes no click, so the view covers the tab.
    static let pillStrip: CGFloat = gripStrip + 8
    /// The air the seam between the boxes keeps; the divider sits in its middle.
    /// Odd, so the 3pt capsule splits it into whole points on a 1x display
    /// instead of rounding to 3 above and 2 below.
    private static let resultGap: CGFloat = 9
    /// The footer holds the more disc plus the rim that separates it from the
    /// box above — the same 6pt as the header's.
    private static let footerHeight: CGFloat = PanelFooterMetrics.footerHeight
    /// The panel's body text, its labels and its secondary text.
    static let bodyFontSize: CGFloat = 14
    static let labelFontSize: CGFloat = 13
    /// The width the boxes draw into on every surface, so the pair reads one
    /// size wherever it appears.
    static let boxWidth: CGFloat = 425
    /// Air a solo shelf card adds between its edge and its boxes. The host gives
    /// a notch card 8pt and an island card none; the widget levels both.
    static let shelfBoxInset: CGFloat = DroppySpacing.sm
    /// The solo card the widget declares: the boxes plus the widget's air.
    static var shelfSoloWidth: CGFloat { boxWidth + shelfBoxInset * 2 }
    /// The language row's width, symmetric around the swap disc. Narrower than
    /// the boxes, so the pair reads as two labels around the disc, not a bar.
    /// The solo shelf's 14pt labels shrink no further than 0.8 before clipping.
    static let defaultRowWidth: CGFloat = 226
    /// The air a label keeps from its half's edges. Each half centres on the swap
    /// disc, so the pair frames it. It also keeps the solo shelf's 14pt
    /// "Auto detect" whole while the label shrinks.
    private static let pillEdgeInset: CGFloat = 8
    /// The pocket cut around the swap disc; its radius leaves a 6pt rim
    /// between the pocket and the 36pt disc.
    static let discRadius: CGFloat = 24
    static let buttonDiameter: CGFloat = 36
    /// Gap between the pill row and the text box.
    private static let rowGap: CGFloat = 6
    /// Rounds the mouths that meet the seam.
    private static let seamFillet: CGFloat = 10
    /// One corner for both boxes, so the input and the result read as a pair.
    static let boxRadius: CGFloat = 28
    /// The result page's close, in the row above its box. Nil hides it.
    var onClose: (() -> Void)?

    /// The text box follows its content between these two states.
    @State private var inputHeight: CGFloat
    /// The result's stretch out of the input: 0 closed, 1 settled.
    @State private var resultReveal: CGFloat
    /// The result box's height. The grip under it drags it between the default
    /// and whatever still fits the tallest card.
    @State private var resultHeight: CGFloat = SidePanelContentView.resultBoxHeight
    @State private var gripHover = false
    /// The grip's drag, while one is in flight.
    @State private var gripDrag: GripDrag?
    /// How far the input has folded into the result, 0…1. The result page gives
    /// the input's space to the result, so the card stays at its tallest.
    @State private var inputFold: CGFloat = 0
    /// The kit's slide animation reads Reduce Motion; the mark's spring is ours.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// A drag on the handle: where it started, where the input begins to fold,
    /// how far it has pulled, and the dead band that absorbs the click slop.
    private struct GripDrag {
        var startHeight: CGFloat
        /// The result height where the input begins to fold. Stored per drag so
        /// a box that is already folded unfolds from the same seam.
        var foldStart: CGFloat
        var pulled: CGFloat
        /// The 6pt removed from the first movement, signed by the direction the
        /// drag started in, so reversing does not jump by twice the slop.
        var deadband: CGFloat
        /// A fold needs a result to read: a status stops at the resting height
        /// instead of stretching for text that never came.
        var hasResult: Bool
        /// The content setting already folded the original, so the pull grows
        /// the result instead of unfolding the input.
        var foldsBySetting: Bool
        var started = false
        /// A pull that reached the fold already asked for the translation; one
        /// drag never asks twice.
        var translateStarted = false
    }
    /// The pointer is on the footer's more disc, or inside its open menu.
    @State private var pointerOnMore = false
    @State private var pointerInMenu = false
    /// The menu follows the pointer; this covers the gap between the disc and
    /// the panel, so crossing it never closes the menu.
    @State private var moreCloseTask: Task<Void, Never>?

    /// `boxHeight` seeds the first frame; the editor takes over after its first
    /// layout.
    init(
        model: TranslateModel,
        chip: SidePanelChipState,
        grip: SidePanelGripState = SidePanelGripState(),
        pin: SidePanelPinState = SidePanelPinState(),
        requestCapture: @escaping () -> Void = {},
        requestSelection: @escaping () -> Void = {},
        cancelSelection: @escaping () -> Void = {},
        boxHeight: CGFloat? = nil,
        boxFloor: CGFloat = SidePanelContentView.minBoxHeight,
        boxCap: CGFloat = SidePanelContentView.panelMaxBoxHeight,
        /// The held drag a render test cannot produce; seeds the grip so the
        /// armed clear state can be photographed.
        gripPull: CGFloat? = nil,
        /// The settled fold state: the input is folded away and the result
        /// keeps its fitted height. `fold` also seeds a half-fold for a render
        /// test.
        fold: CGFloat = 0,
        translationOnly: Bool = false,
        fitsResult: Bool = false,
        keepsGripInsideCard: Bool = false,
        showsGrip: Bool = true,
        glassTiles: Bool = true,
        maxBodyHeight: CGFloat = SidePanelContentView.maxPanelBodyHeight,
        rowWidth: CGFloat = SidePanelContentView.defaultRowWidth,
        mountWidth: CGFloat = 0,
        onShelfGripTap: (() -> Void)? = nil,
        onSubmit: (() -> Void)? = nil,
        onClear: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil,
        onGripOut: @escaping (Bool) -> Void = { _ in },
        onPin: (() -> Void)? = nil,
        onBodyHeight: @escaping (CGFloat, Bool) -> Void = { _, _ in },
        onShelfContentHeight: @escaping (CGFloat) -> Void = { _ in }
    ) {
        _model = ObservedObject(wrappedValue: model)
        _chip = ObservedObject(wrappedValue: chip)
        _grip = ObservedObject(wrappedValue: grip)
        _pin = ObservedObject(wrappedValue: pin)
        self.requestCapture = requestCapture
        self.requestSelection = requestSelection
        self.cancelSelection = cancelSelection
        self.onGripOut = onGripOut
        self.onPin = onPin
        self.keepsGripInsideCard = keepsGripInsideCard
        self.showsGrip = showsGrip
        self.translationOnly = translationOnly
        self.fitsResult = fitsResult
        self.glassTiles = glassTiles
        self.maxBodyHeight = maxBodyHeight
        self.boxFloor = boxFloor
        self.boxCap = boxCap
        self.rowWidth = rowWidth
        self.mountWidth = mountWidth
        self.onShelfGripTap = onShelfGripTap
        self.onSubmit = onSubmit
        self.onClear = onClear
        self.onClose = onClose
        self.onBodyHeight = onBodyHeight
        self.onShelfContentHeight = onShelfContentHeight
        let box = boxHeight ?? boxFloor
        let settled = min(max(fold, 0), 1)
        // The panel opens on a result the user asked to see alone: the input
        // starts folded, so the first frame is the card they chose. A status
        // takes the same card, and an empty box keeps the input it is about.
        let fold = settled > 0 || !translationOnly || !Self.showsResult(for: model)
            ? settled
            : 1
        // The fitted mount's resting result: the words' own height on the
        // panels, the shelf's fixed box otherwise. The translation alone
        // carries the target picker and equal air around its words.
        let aloneResult = fitsResult
            && (translationOnly || !model.resultPage.showsOriginal)
            && !model.output.isEmpty
        let aloneStatus = (translationOnly || !model.resultPage.showsOriginal)
            && Self.showsResult(for: model)
        // The shelf's fixed box is its own; the panels open level with the
        // input, so a short answer is not a shorter box beside it.
        let restingResult: CGFloat = fitsResult
            ? Self.restingResultHeight(
                for: model,
                alone: aloneResult || aloneStatus,
                matching: box
            )
            : Self.resultBoxHeight
        _inputHeight = State(initialValue: box)
        _inputFold = State(initialValue: fold)
        // The card that shows the translation alone opens at the words' own
        // height, so a short result leaves no empty box under it. The floating
        // panel fits every result, status included.
        _resultHeight = State(
            initialValue: fitsResult
                ? restingResult
                : fold > 0 && translationOnly && !model.output.isEmpty
                    ? Self.fittedResultHeight(text: model.output)
                    : Self.resultBoxHeight + box * fold
        )
        _resultReveal = State(
            initialValue: Self.showsResult(for: model) ? 1 : 0
        )
        _gripDrag = State(
            initialValue: gripPull.map {
                GripDrag(
                    startHeight: $0,
                    foldStart: max($0, restingResult),
                    pulled: $0,
                    deadband: 0,
                    hasResult: false,
                    foldsBySetting: false
                )
            }
        )
    }

    private var pillHeight: CGFloat { LanguageMenu.pillRowHeight }

    /// The card's vertical content inset: the island's 16pt shelf inset plus
    /// the 1.5pt widget slot, rounded to a whole point.
    static var inset: CGFloat {
        (DroppyShellMetrics.shelfContentInsets(usesNotchStyle: false).leading
            + DroppyShellMetrics.shelfWidgetSlotInset).rounded()
    }

    /// The card's side margin: the host's shelf inset, the widget slot and the
    /// air the solo shelf widget keeps around its boxes, so the panel's boxes
    /// line up with the shelf's.
    static var sideInset: CGFloat {
        (DroppyShellMetrics.shelfContentInsets(usesNotchStyle: false).leading
            + DroppyShellMetrics.shelfWidgetSlotInset + shelfBoxInset).rounded()
    }

    /// The card body holding the header, a `box`-point input and, when shown, the
    /// result and footer. The input tucks under the disc. `resultReveal` shrinks
    /// the result from its seam, so it grows downward instead of sliding.
    static func bodyHeight(
        forBox box: CGFloat,
        result: Bool = false,
        resultHeight: CGFloat = SidePanelContentView.resultBoxHeight,
        resultReveal: CGFloat = 1
    ) -> CGFloat {
        let resultSection = result ? resultGap + resultHeight * resultReveal : 0
        return inset * 2 + LanguageMenu.pillRowHeight + rowGap + box
            + footerHeight + resultSection
    }

    /// True once there is something to read: a result, a status or a notice.
    static func showsResult(for model: TranslateModel) -> Bool {
        model.page != .input
    }

    /// The hosting view that draws a body of `body`: the card's vertical
    /// content inset above and below, plus the strip the drag tab hangs in.
    static func contentHeight(forBody body: CGFloat) -> CGFloat {
        body - inset * 2 + pillStrip
    }

    static var maxBodyHeight: CGFloat { bodyHeight(forBox: maxBoxHeight) }
    /// The floating panel's own floors and cap: its shorter input and fitted
    /// result, with no fillet or grip strip on the window.
    static var floatingMinBodyHeight: CGFloat { bodyHeight(forBox: floatingBoxFloor) }
    static var floatingMaxBodyHeight: CGFloat {
        bodyHeight(forBox: floatingBoxCap, result: true, resultHeight: floatingResultCap)
    }
    /// The tallest default card, with the result box open; the panels pass
    /// their own cap.
    static var maxPanelBodyHeight: CGFloat {
        bodyHeight(forBox: panelMaxBoxHeight, result: true)
    }

    /// The width the floating panel's boxes draw into: its card minus the
    /// content inset on each side.
    static var panelContentWidth: CGFloat { boxWidth }
    /// Air above the result's words and under them, as the result scroll view
    /// lays them out.
    static let resultTextTop: CGFloat = 23
    static let resultTextBottom: CGFloat = 48

    /// The result box fitted to its words, for a card that shows the
    /// translation alone. Its floor keeps the open more menu's top row whole.
    static func fittedResultHeight(text: String) -> CGFloat {
        let width = max(80, panelContentWidth - PanelTileText.sideInset * 2 - 10)
        let height = resultTextTop * 2 + resultTextHeight(text, width: width)
        return min(fittedResultCap, max(aloneResultFloor, height))
    }

    /// The lone result opens at the floor the open more menu leaves it, so the
    /// menu's top row stays whole and a short translation is not a slab.
    static var aloneResultFloor: CGFloat { menuFloor }

    /// The shortest a result may be while the more menu still opens inside
    /// the card's content.
    static var menuFloor: CGFloat {
        PanelMoreMenu.height - LanguageMenu.pillRowHeight - rowGap - resultGap
    }

    /// The floating panel's result box: resting air, capped at 400 so long text
    /// scrolls. `alone` uses the shelf's 380 cap; `matching` makes the box at
    /// least the input's height, so a short answer leaves the pair level.
    static func floatingFittedResultHeight(
        text: String,
        width: CGFloat = 0,
        alone: Bool = false,
        matching input: CGFloat = 0
    ) -> CGFloat {
        let contentWidth = width > 0 ? width : panelContentWidth
        let textWidth = max(80, contentWidth - PanelTileText.sideInset * 2 - 10)
        let height = (alone ? resultTextTop * 2 : resultTextTop + resultTextBottom)
            + resultTextHeight(text, width: textWidth)
        if alone { return min(fittedResultCap, max(aloneResultFloor, height)) }
        return min(floatingResultCap, max(max(floatingResultFloor, input), height))
    }

    /// The result box at rest: the words, or the status and controls. Beside the
    /// input it is never shorter than the input, so the pair stays level.
    static func restingResultHeight(
        for model: TranslateModel,
        alone: Bool,
        matching input: CGFloat,
        width: CGFloat = 0
    ) -> CGFloat {
        if model.output.isEmpty {
            let fitted = fittedStatusHeight(for: model, width: width, alone: alone)
            return alone ? fitted : max(input, fitted)
        }
        return floatingFittedResultHeight(
            text: model.output,
            width: width,
            alone: alone,
            matching: input
        )
    }

    /// The status box: the message and recovery controls with equal air. A result
    /// beside it keeps its own floor; a status alone takes the result page's floor
    /// so the more menu fits above it.
    @MainActor
    static func fittedStatusHeight(
        for model: TranslateModel,
        width: CGFloat = 0,
        alone: Bool = false
    ) -> CGFloat {
        let message = model.notice ?? statusMessage(for: model) ?? ""
        let contentWidth = width > 0 ? width : panelContentWidth
        let textWidth = max(80, contentWidth - PanelTileText.sideInset * 2)
        var block = statusTextHeight(message, width: textWidth)
        if model.status == .translating, block == 0 {
            block = Self.statusRowHeight
        }
        if model.status == .needsDownload {
            block += Self.statusControlHeight + DroppySpacing.sm
        }
        if model.canRetryTranslation {
            block += Self.statusControlHeight + DroppySpacing.sm
        }
        let height = resultTextTop * 2 + block
        let fitted = min(floatingResultCap, height)
        return alone ? max(aloneResultFloor, fitted) : fitted
    }

    /// The progress row's height while a translation runs.
    private static let statusRowHeight: CGFloat = 20

    /// A small glass control's height, the download and retry buttons.
    private static let statusControlHeight: CGFloat = 30

    private static func statusTextHeight(_ text: String, width: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        let bounds = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: NSFont.systemFont(ofSize: labelFontSize),
                .paragraphStyle: paragraph
            ]
        )
        return ceil(bounds.height)
    }

    /// The wrapped height of a result at the panel's type size, measured the
    /// way the scroll view lays it out: character wrapping and a 5pt indent.
    static func resultTextHeight(_ text: String, width: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let paragraph = NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = 5
        paragraph.headIndent = 5
        paragraph.lineBreakMode = .byCharWrapping
        let bounds = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: NSFont.systemFont(ofSize: bodyFontSize),
                .paragraphStyle: paragraph
            ]
        )
        return ceil(bounds.height)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
            header
                .frame(height: pillHeight + Self.discRadius, alignment: .top)
                .zIndex(1)
                // The result page ends with the result on the whole card; the language
                // row clears out once the result is about to reach it.
                .opacity(headerOpacity)
                .allowsHitTesting(headerOpacity > 0)
            // The boxes ride the disc's pocket as one group: the tuck holds
            // even when the fold has shrunk the input to nothing.
            VStack(spacing: 0) {
                SourceTile(
                    model: model,
                    notch: nil,
                    showsLanguageMenu: false,
                    tileCornerRadius: Self.boxRadius,
                    editorTopInset: Self.editorTopInset,
                    editorBottomInset: Self.editorBottomInset,
                    onSubmit: onSubmit ?? model.translate,
                    onEditorHeight: { height in
                        // The shelf and the panel each name their own box cap;
                        // the card is sized from the same number.
                        let clamped = min(max(height, boxFloor), boxCap)
                        guard clamped != inputHeight else { return }
                        // The whole stack moves with the box: the header stays
                        // put, the footer travels, and the box's top never dips.
                        withAnimation(DroppyAnimation.state) {
                            inputHeight = clamped
                        }
                    },
                    showsInlineTools: false,
                    bodyFontSize: Self.bodyFontSize,
                    maxEditorHeight: keepsGripInsideCard
                        ? (showsResult ? boxCap : closedInputHeight)
                        : boxCap,
                    scrollerCap: keepsGripInsideCard
                        ? (showsResult ? boxCap : closedInputHeight)
                        : boxCap,
                    hoverChrome: true,
                    // Folded, the tile's frame is the input's old height while
                    // the result covers it; marking it would draw a wash over
                    // the result at a box that is no longer there.
                    chipTarget: faceFold == 0 && displayedBoxHeight > 0 ? .input : nil,
                    pocketCut: glassTiles ? Self.inputCut : nil
                )
                // On the result page the input is a shrinking top slice: the
                // result climbs over it, so the text is covered, never squashed.
                .frame(height: inputTileHeight, alignment: .top)
                .frame(height: displayedBoxHeight, alignment: .top)
                .clipped()
                .allowsHitTesting(faceFold == 0 && displayedBoxHeight > 0)
                // The pair reads as one field with a seam: the hairline sits in
                // the air under the input, and follows its edge while it folds.
                .overlay(alignment: .bottom) {
                    if showsSeamDivider {
                        PanelSeamDivider(gap: Self.resultGap)
                    }
                }
                // A grip drag mounts the box before the result arrives, so the
                // drag pulls the empty sheet out of the input instead of waiting
                // for the status and then dropping the whole box in.
                if showsResult || resultOnScreen {
                    resultBox
                        // A stowed box keeps its place but not its seam, so the
                        // footer sits where a bare input puts it. The gap appears
                        // only once the pull shows the box.
                        .padding(
                            .top,
                            resultOnScreen && visibleResultHeight > 0
                                ? (Self.resultGap - fullCardRise)
                                : 0
                        )
                }
            }
            .padding(
                .top,
                -(Self.discRadius - Self.rowGap) - Self.resultGap * faceFold
            )
            // The drop grows out of the input and pushes the footer down with
            // it; the extra height below is only visible while it stretches.
            footer
                .zIndex(2)
            Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(alignment: .bottom) {
                if showsGrip { gripHandle }
            }
            // The card is the sheet in front: content may not draw past its face,
            // even while the window catches up with a new body size. The chip
            // stays outside this clip so its spring can settle over the edge.
            .clipped()

            chipLayer
        }
        .coordinateSpace(name: SidePanelChipState.space)
        .environment(\.sidePanelChip, chip)
        // The panel's download pill asks the system for the pair itself; the
        // task lives with the card, so the sheet hangs over it.
        .translationPreparer(model)
        .onPreferenceChange(SidePanelChipFrameKey.self) { chip.frames = $0 }
        // One tracking area over the whole panel: the chip follows the pointer
        // from control to control.
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                // Republish only when the control changes, so moving inside one
                // does not redraw. The faded language row must not come back.
                let target = Self.target(
                    at: point,
                    frames: chip.frames,
                    marksHeader: headerOpacity > 0 && !showsResultPicker
                )
                if target != chip.target { chip.target = target }
            case .ended:
                // The pointer left the panel, so nothing is held any more.
                chip.target = nil
                chip.pressed = false
                pointerOnMore = false
                pointerInMenu = false
                closeMoreSoon()
            }
        }
        .animation(DroppyAnimation.state, value: model.isToolbarExpanded)
        .onChange(of: model.input) { _, _ in model.inputChanged() }
        .onChange(of: model.isToolbarExpanded) { _, open in
            // Every open starts clean: a close that removed the panel under the
            // pointer never reports `ended`, and a stale true would pin it open.
            pointerInMenu = false
            if open { return }
            moreCloseTask?.cancel()
            moreCloseTask = nil
        }
        .onChange(of: inputHeight) { _, height in
            if gripDrag != nil {
                reportGrip()
                return
            }
            if keepsGripInsideCard {
                reportShelfContentHeight()
                return
            }
            // Folded away, the input's height has no say in the card.
            guard inputFold == 0 else { return }
            // The pair rides the input: a taller box lifts the result with it,
            // and the answer only grows past it when its words need the room.
            let level = Self.restingResultHeight(
                for: model,
                alone: showsAlone,
                matching: height
            )
            if abs(level - resultHeight) > 0.5 {
                withAnimation(DroppyAnimation.state) { resultHeight = level }
            }
            // A taller input leaves less of the card's cap for the result.
            let cap = maxBodyHeight - Self.bodyHeight(forBox: height) - Self.resultGap
            if resultHeight > cap {
                withAnimation(DroppyAnimation.state) { resultHeight = cap }
            }
            onBodyHeight(
                Self.bodyHeight(forBox: height, result: showsResult, resultHeight: resultHeight),
                true
            )
        }
        .onChange(of: resultHeight) { _, height in
            // A grip drag is direct manipulation: the window follows the
            // pointer instead of easing toward it.
            if gripDrag != nil {
                reportGrip()
            } else {
                onBodyHeight(
                    Self.bodyHeight(
                        forBox: displayedBoxHeight,
                        result: showsResult,
                        resultHeight: height
                    ),
                    true
                )
            }
        }
        .onChange(of: showsResult) { _, shown in
            if gripDrag != nil {
                // The drag sets the height until the pointer lifts; the box
                // stays where the fingers pulled it.
                reportGrip()
                return
            }
            if fitsResult {
                settleResultHeight()
            } else if translationOnlyNow {
                settleTranslationOnly()
            } else if !shown, inputFold > 0 {
                withAnimation(DroppyAnimation.release) { inputFold = 0 }
            }
            onBodyHeight(
                Self.bodyHeight(
                    forBox: displayedBoxHeight,
                    result: shown,
                    resultHeight: resultHeight
                ),
                true
            )
            withAnimation(DroppyAnimation.state) {
                resultReveal = shown ? 1 : 0
            }
            reportShelfContentHeight()
        }
        // The picker above the picture changes the card under it without
        // recreating it, so the fold has to follow the setting here.
        .onChange(of: translationOnly) { _, _ in
            guard gripDrag == nil, showsResult else { return }
            settleResultHeight()
            reportBodyHeight()
        }
        // The live edge panel reads the same setting, and its content view is
        // built once, so the model is the one that tells it the picker moved.
        .onChange(of: model.resultPage) { _, _ in
            reportShelfContentHeight()
            guard fitsResult, gripDrag == nil, showsResult else { return }
            settleResultHeight()
            reportBodyHeight()
        }
        // A result that lands or changes refits the box to its words.
        .onChange(of: model.output) { _, _ in
            reportShelfContentHeight()
            guard gripDrag == nil, fitsResult || translationOnlyNow else { return }
            settleResultHeight()
            reportBodyHeight()
        }
        // A status is fitted too: the box holds the message and its controls,
        // not the resting slab a translation uses.
        .onChange(of: model.notice) { _, _ in
            reportShelfContentHeight()
            guard gripDrag == nil, fitsResult, showsResult else { return }
            settleResultHeight()
            reportBodyHeight()
        }
        .onChange(of: model.status) { _, _ in
            reportShelfContentHeight()
            guard gripDrag == nil, fitsResult, showsResult else { return }
            settleResultHeight()
            reportBodyHeight()
        }
        .onChange(of: mountWidth) { _, _ in
            reportShelfContentHeight()
        }
        .onAppear {
            resultReveal = showsResult ? 1 : 0
            onBodyHeight(
                Self.bodyHeight(
                    forBox: keepsGripInsideCard ? inputHeight : displayedBoxHeight,
                    result: showsResult,
                    resultHeight: resultHeight
                ),
                false
            )
            reportShelfContentHeight()
        }
    }

    /// The floating panel fits its box to whatever it holds: the translation,
    /// or the status message and its controls, never shorter than the input
    /// when both are shown.
    private func settleResultHeight() {
        guard fitsResult else {
            settleTranslationOnly()
            return
        }
        let folds = showsAlone
        let height = Self.restingResultHeight(
            for: model,
            alone: folds,
            matching: inputHeight
        )
        withAnimation(DroppyAnimation.release) {
            inputFold = folds ? 1 : 0
            resultHeight = height
        }
    }

    /// "Translation only" folds the original away and fits the result box to
    /// its words; every other choice gives the input its room back. The card
    /// ends where the text does instead of leaving an empty box under it.
    private func settleTranslationOnly() {
        let folds = translationOnlyNow && showsResult && !model.output.isEmpty
        withAnimation(DroppyAnimation.release) {
            inputFold = folds ? 1 : 0
            resultHeight = folds
                ? Self.fittedResultHeight(text: model.output)
                : Self.resultBoxHeight
        }
    }

    /// Tells the window the body the card now draws.
    private func reportBodyHeight(animated: Bool = true) {
        onBodyHeight(
            Self.bodyHeight(
                forBox: displayedBoxHeight,
                result: showsResult,
                resultHeight: resultHeight
            ),
            animated
        )
    }

    /// The shelf's opening card is the bare input; the result joins from the
    /// second step. A status with no translation still shows, so an error is
    /// never hidden behind a tap. The panel shows the result whenever it has one.
    private var showsResult: Bool {
        Self.showsResult(for: model)
    }

    /// The result box is on screen: a grip is holding it, or a pull has
    /// revealed it. A stowed status keeps its state but not its seam.
    private var resultOnScreen: Bool {
        if keepsGripInsideCard { return showsResult && resultReveal > 0 }
        return gripDrag != nil || resultReveal > 0
    }

    /// The part of the result box on screen right now: the pull while the grip
    /// is held, the settled box when it is open, nothing when it is closed.
    private var visibleResultHeight: CGFloat {
        if let gripDrag { return gripDrag.pulled }
        guard showsResult else { return 0 }
        return displayedResultHeight * resultReveal
    }

    /// The hairline between the original and its answer. It needs both boxes
    /// on the card: with the result alone the input has folded away, and with
    /// no answer yet there is no second box to part.
    private var showsSeamDivider: Bool {
        showsResult && resultOnScreen && resultReveal >= 1
            && displayedBoxHeight > 0 && visibleResultHeight > 0
    }

    /// The result height the current mount draws. The shelf derives it from
    /// its card step; the panel's grip writes it.
    private var displayedResultHeight: CGFloat {
        keepsGripInsideCard ? shelfResultHeight : resultHeight
    }

    /// The result box at rest: the panels fit it to the words, level with the
    /// input until the answer needs more room than the input gives it.
    private var restingResultHeight: CGFloat {
        guard fitsResult else { return Self.resultBoxHeight }
        return Self.restingResultHeight(
            for: model,
            alone: showsAlone,
            matching: inputHeight
        )
    }

    /// The input's height on screen: the fold takes it away a slice at a time
    /// while the result takes the space. The shelf's card trades the input
    /// for the result and gives it back as it grows.
    private var displayedBoxHeight: CGFloat {
        if keepsGripInsideCard { return shelfInputHeight }
        return inputHeight * (1 - inputFold)
    }

    /// The input tile's own frame. It stays whole and is clipped while the
    /// result climbs over it, but the shelf's closed box is the tall one.
    private var inputTileHeight: CGFloat {
        keepsGripInsideCard ? shelfInputHeight : inputHeight
    }

    /// The room the shelf card leaves for its boxes: the content the host
    /// actually hands over, minus the header and footer. The header band stays
    /// in the budget on every face; the result page covers it.
    private var shelfRoom: CGFloat {
        max(0, maxBodyHeight - (pillHeight + Self.rowGap + Self.footerHeight))
    }

    /// The input at the current step: the whole room while the result is out
    /// of the picture, the measured box beside the result, and nothing when
    /// the answer has the card to itself.
    private var shelfInputHeight: CGFloat {
        guard keepsGripInsideCard else { return inputHeight }
        guard showsResult else { return max(inputHeight, shelfRoom) }
        if showsAlone { return 0 }
        return min(max(inputHeight, boxFloor), boxCap)
    }

    /// The result takes whatever the input leaves, so the two always fill the
    /// card at the height the host gave them. At the content's own height this
    /// is the fitted result; while the host springs, it rides that height.
    private var shelfResultHeight: CGFloat {
        guard keepsGripInsideCard, showsResult else { return 0 }
        return max(0, shelfRoom - shelfInputHeight - Self.resultGap)
    }

    /// The height the shelf's input fills when no result is on screen: what
    /// the card leaves after the header and the footer.
    private var closedInputHeight: CGFloat {
        max(inputHeight, shelfRoom)
    }

    /// The input height the shelf's card should budget for: the editor's
    /// measured box, between the shelf's floor and cap. A full card has no
    /// input to budget, but an empty full card falls back to the opening one.
    private var shelfDesiredInputHeight: CGFloat {
        if showsAlone { return 0 }
        return min(max(inputHeight, boxFloor), boxCap)
    }

    /// The result height the shelf's card should budget for: fitted to the
    /// words or status, never shorter than the input beside it, and capped at
    /// 380 when the result is alone.
    private var shelfDesiredResultHeight: CGFloat {
        guard showsResult else { return 0 }
        let input = shelfDesiredInputHeight
        let cap = Self.shelfResultCap(input: input)
        if model.output.isEmpty {
            // The full face has no input above the footer, so the more menu
            // needs the floor to open whole.
            let fitted = Self.fittedStatusHeight(for: model, width: mountWidth)
            return min(cap, max(input, Self.menuFloor, fitted))
        }
        let fitted = Self.floatingFittedResultHeight(
            text: model.output,
            width: mountWidth,
            alone: showsAlone
        )
        return min(cap, max(input, fitted))
    }

    /// The widget rectangle the shelf content needs. The host draws a card
    /// 16pt taller on the notch for its corner inset; the island spends none.
    private var shelfDesiredContentHeight: CGFloat {
        let input = shelfDesiredInputHeight
        let result = shelfDesiredResultHeight
        let resultSection = result > 0 ? Self.resultGap + result : 0
        return pillHeight + Self.rowGap + input + resultSection + Self.footerHeight
    }

    private func reportShelfContentHeight() {
        guard keepsGripInsideCard else { return }
        onShelfContentHeight(shelfDesiredContentHeight)
    }

    /// How far the result climbs past the language row, measured from the seam
    /// it rests on: at full fold its top is the card's.
    private var faceFold: CGFloat {
        // The result page takes the card's top on every surface, so the
        // language row never sits above it looking like a second input card.
        if showsAlone { return 1 }
        return inputFold
    }

    /// The result page puts the target picker inside its box's top: the
    /// language row is gone, so it is the one language control left.
    private var showsResultPicker: Bool {
        showsAlone
    }

    /// The chosen content is the translation alone, and there is something to
    /// read: a translation, or a status that takes its box.
    private var showsAlone: Bool {
        translationOnlyNow && showsResult
    }

    private var fullCardRise: CGFloat {
        showsResultPicker ? 0 : (pillHeight + Self.rowGap) * faceFold
    }

    /// The soft band a held grip leaves on the box's face: the words near the
    /// moving edge blur, while the box's own rim stays sharp.
    static let resultEdgeBlur: CGFloat = 5
    private static let resultEdgeBlurBand: CGFloat = 28

    /// A control may only mark the chip while its box is fully open. A stowed
    /// box still lays its controls out, and a mark over one draws it back on
    /// screen above the box's own clip.
    static func marksChip(reveal: CGFloat) -> Bool {
        reveal >= 1
    }

    /// The result box on screen. Its glass takes the height the pull revealed,
    /// with its rounded rim as the moving edge; the words are clipped, not
    /// squeezed, and blur near the rim while the grip is held.
    private var resultBox: some View {
        let outline = Self.resultOutline
        let tile = PanelResultTile(
            model: model,
            isDragging: gripDrag != nil,
            reveal: resultReveal,
            fitsHeight: fitsResult || keepsGripInsideCard
        )
            // The fold gives the result the gap it ate at the seam, so its
            // bottom keeps the footer's air instead of riding up with it.
            .frame(height: displayedResultHeight + fullCardRise + Self.resultGap * faceFold)
            .frame(
                height: displayedResultHeight * resultReveal + fullCardRise
                    + Self.resultGap * faceFold,
                alignment: .top
            )
            .clipped()
        let box = ZStack(alignment: .top) {
            tile
                .mask(alignment: .bottom) {
                    ZStack(alignment: .bottom) {
                        Color.black
                        if gripDrag != nil {
                            LinearGradient(
                                colors: [.black, .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: Self.resultEdgeBlurBand)
                        }
                    }
                }
            if gripDrag != nil {
                tile
                    .blur(radius: Self.resultEdgeBlur)
                    .mask(alignment: .bottom) {
                        LinearGradient(
                            colors: [.clear, .black],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: Self.resultEdgeBlurBand)
                    }
                    .allowsHitTesting(false)
            }
        }
        // The rim the glass draws is the rim the words live in: a rect clip
        // would let a line show past the rounded corner.
        .clipShape(outline)
        // The mark covers what is on screen, not the whole box: a full-height
        // frame would let the chip's glass hang past the card's edge.
        .chipTarget(resultReveal >= 1 ? .result : nil)
        return box
    }

    /// The result page's language control: the target, in the same pill the
    /// card's row draws, so the one picker and the row's languages match.
    private var resultTargetMenu: some View {
        LanguageMenu(
            model: model,
            selection: $model.targetID,
            includesAuto: false,
            label: model.name(for: model.targetID),
            fontSize: headerFontSize,
            alignment: .center,
            edgeInset: headerEdgeInset,
            chipTarget: .resultTarget,
            availableIDs: model.installedTargetIDs,
            footerPill: true
        )
        .chipTarget(.resultTarget)
    }

    /// The language row stays usable until the result is about to reach it,
    /// then clears out of its way. The result page hands its language to the
    /// picker in the row above the box.
    private var headerOpacity: Double {
        if showsResultPicker { return 1 }
        let fade = min(max((faceFold - 0.7) / 0.3, 0), 1)
        return Double(1 - fade)
    }

    /// The first 6pt of a drag are the click's slop; past it the box follows
    /// the pointer. Up folds the result back into the input.
    private static let gripThreshold: CGFloat = 6
    /// How far the pointer must keep pulling up after the result is fully
    /// folded before letting go clears the text.
    static let gripClearPull: CGFloat = 24
    /// The drag handle is the collapsed tab's body on its side: a 104-long
    /// curve of 18 points, with a straight stem above it that stays buried in
    /// the card.
    static let gripWidth: CGFloat = 104
    static let gripCurveDepth: CGFloat = 18
    /// The stem is buried in the card when the handle shows, so its top never
    /// draws a line across the card's edge.
    static let gripTuck: CGFloat = 3
    /// At rest the tab's deepest point clears the card's edge by this much, so
    /// no black sliver peeks out under the face.
    static let gripHide: CGFloat = 2
    /// The stem plus the curve the card shows.
    static var gripDepth: CGFloat { gripCurveDepth + gripTuck }
    /// The tab rests hidden behind the card's face, so its bottom edge sits
    /// above the card's edge and only the bar shows inside the card.
    static var gripRise: CGFloat { gripCurveDepth + gripHide }
    /// Air under the curve: the hosting view reaches below the card's edge, so
    /// the curve hangs whole and only the stem stays buried.
    static var gripPadding: CGFloat { pillStrip - inset - gripCurveDepth }
    /// The curve starts this far above the card's edge, so the card's black
    /// covers the join. Two fills that meet on one line each cover half of the
    /// boundary pixel, and the background shows through the seam.
    static let gripOverlap: CGFloat = 1
    /// The bar is the whole resting affordance; the handle grows around it.
    static let gripRestBar = CGSize(width: 22, height: 3)
    static let gripOutBar = CGSize(width: 30, height: 4)
    /// The shelf's bar keeps a little air under it.
    static let shelfGripLift: CGFloat = 12
    static let gripHitSize = CGSize(width: gripWidth, height: gripStrip)

    /// The visible result height a drag of `translation` asks for. A negative
    /// value is the pull past a folded box, where the clear action arms; `full`
    /// lets the result grow by the input's height so the card keeps its size.
    static func gripHeight(
        start: CGFloat,
        translation: CGFloat,
        deadband: CGFloat,
        box: CGFloat,
        full: Bool = false,
        foldStart: CGFloat = SidePanelContentView.resultBoxHeight
    ) -> CGFloat {
        let ceiling = full
            ? max(start, foldStart + box)
            : foldStart
        let cap = max(start, ceiling)
        return min(start + translation - deadband, cap)
    }

    /// How much of the input the pull has folded into the result: 0 before the
    /// seam, 1 once the result has taken the input's height. The seam is fixed
    /// at drag start, so an already folded box unfolds from the same place.
    static func inputFold(
        pulled: CGFloat,
        box: CGFloat,
        full: Bool,
        foldStart: CGFloat = SidePanelContentView.resultBoxHeight
    ) -> CGFloat {
        guard full, box > 0 else { return 0 }
        return min(max(pulled - foldStart, 0) / box, 1)
    }

    /// The input fold a pull asks for. A card the display setting already
    /// folded keeps it folded, so the pull grows the result instead of
    /// bringing the original back.
    static func gripFold(
        pulled: CGFloat,
        box: CGFloat,
        full: Bool,
        foldStart: CGFloat,
        foldsBySetting: Bool
    ) -> CGFloat {
        guard !foldsBySetting else { return 1 }
        return inputFold(pulled: pulled, box: box, full: full, foldStart: foldStart)
    }

    /// A pull that reaches the resting box's height asks for the translation,
    /// like Return. A box that already reads is only resized, and a run in
    /// flight is not restarted under the pointer.
    static func startsTranslation(
        pulled: CGFloat,
        hasInput: Bool,
        hasOutput: Bool,
        isTranslating: Bool,
        resting: CGFloat = SidePanelContentView.resultBoxHeight
    ) -> Bool {
        pulled >= resting && hasInput && !hasOutput && !isTranslating
    }

    /// Pulls the result box `pulled` points out of the input; a negative pull
    /// folds it away. Only the slice on screen follows the pointer, so the text
    /// never squeezes. Past the seam the input folds too and the result climbs.
    private func applyGrip(
        _ pulled: CGFloat,
        full: Bool,
        foldStart: CGFloat,
        foldsBySetting: Bool
    ) {
        let visible = max(pulled, 0)
        let height = max(visible, restingResultHeight)
        let reveal = height > 0 ? min(1, visible / height) : 0
        let fold = Self.gripFold(
            pulled: pulled,
            box: inputHeight,
            full: full,
            foldStart: foldStart,
            foldsBySetting: foldsBySetting
        )
        if abs(resultHeight - height) > 0.5 { resultHeight = height }
        if abs(resultReveal - reveal) > 0.001 { resultReveal = reveal }
        if abs(inputFold - fold) > 0.001 { inputFold = fold }
        reportGrip()
    }

    /// The window body carries only the part of the result the drag pulled out,
    /// so the card edge stays under the pointer. Once the input folds, the two
    /// heights trade places and the card stays at its tallest.
    private func reportGrip() {
        guard let drag = gripDrag else { return }
        let visible = max(drag.pulled, 0)
        let height = max(visible, restingResultHeight)
        let reveal = height > 0 ? min(1, visible / height) : 0
        onBodyHeight(
            Self.bodyHeight(
                forBox: displayedBoxHeight,
                result: visible > 0,
                resultHeight: height,
                resultReveal: reveal
            ),
            false
        )
    }

    /// Lets go: the fold settles on whichever side the pointer was closer to.
    /// A result springs open, a status stows, and an empty box folds back into
    /// the input. A card already folded by the setting springs to the fitted box.
    private func settleGrip(_ drag: GripDrag) {
        // The setting and the words on the card decide what lands, not the
        // drag's start: a pull that asks for the translation and gets one
        // ends on the translation alone.
        if showsAlone {
            // A pull that brought the translation in settles on the fitted box;
            // a card that already held one keeps the height it was pulled to.
            let fullCard = drag.hasResult && drag.pulled > drag.foldStart + inputHeight / 2
            let height = fullCard ? drag.foldStart + inputHeight : restingResultHeight
            withAnimation(DroppyAnimation.release) {
                inputFold = 1
                resultHeight = height
                resultReveal = 1
            }
            onBodyHeight(
                Self.bodyHeight(forBox: 0, result: true, resultHeight: height),
                true
            )
            return
        }
        let stows = !showsResult
            || (model.output.isEmpty && drag.pulled < restingResultHeight / 2)
        if stows {
            stowResultBox()
            return
        }
        let fullCard = drag.hasResult && drag.pulled > drag.foldStart + inputHeight / 2
        let height = fullCard
            ? drag.foldStart + inputHeight
            : max(restingResultHeight, min(drag.pulled, drag.foldStart))
        withAnimation(DroppyAnimation.release) {
            inputFold = fullCard ? 1 : 0
            resultHeight = height
            resultReveal = 1
        }
        onBodyHeight(
            Self.bodyHeight(
                forBox: fullCard ? 0 : inputHeight,
                result: true,
                resultHeight: height
            ),
            true
        )
    }

    /// Folds the result box away and shrinks the card back to the input.
    private func stowResultBox() {
        withAnimation(DroppyAnimation.release) {
            inputFold = 0
            resultHeight = restingResultHeight
            resultReveal = 0
        }
        onBodyHeight(Self.bodyHeight(forBox: inputHeight), true)
    }

    /// The drag went past a folded result: the text and its result go, and the
    /// card settles back to the bare input.
    private func clearFromGrip() {
        model.clearInput()
        stowResultBox()
    }

    /// The control under the pointer. A second pass reaches 4pt into the 8pt
    /// gaps, so the chip never blinks between two controls.
    static func target(
        at point: CGPoint,
        frames: [SidePanelChipTarget: CGRect],
        marksHeader: Bool = true
    ) -> SidePanelChipTarget? {
        let frames = marksHeader ? frames : frames.filter { !$0.key.isHeader }
        return hit(point, frames: frames, slop: 0)
            ?? hit(point, frames: frames, slop: 4)
    }

    /// Menu rows report their chip frame inset from the row, so the hit test
    /// grows it back to the row and into the 5pt air between rows.
    private static let menuRowReach: CGFloat = 5.5

    /// The open menu sits above the more disc, so its rows take the mark
    /// before the disc below them.
    private static let chipOrder: [SidePanelChipTarget] =
        SidePanelChipTarget.allCases.filter(\.isMenu)
        + SidePanelChipTarget.allCases.filter { !$0.isMenu }

    private static func hit(
        _ point: CGPoint,
        frames: [SidePanelChipTarget: CGRect],
        slop: CGFloat
    ) -> SidePanelChipTarget? {
        for target in chipOrder {
            guard let frame = frames[target] else { continue }
            var region = target == .swap ? swapRegion(frames) : frame
            if target.isMenu {
                region = region.insetBy(dx: -menuRowReach, dy: -menuRowReach)
            }
            if region.insetBy(dx: -slop, dy: -slop).contains(point) {
                return target
            }
        }
        return nil
    }

    /// The swap disc's mark: the disc, grown into its pocket, and the gap
    /// between the two language pills bridged. Without the bridge a pointer
    /// crossing that gap marks nothing and the chip blinks on the way in.
    private static func swapRegion(_ frames: [SidePanelChipTarget: CGRect]) -> CGRect {
        guard let swap = frames[.swap] else { return .zero }
        var region = swap.insetBy(dx: -6, dy: -6)
        if let left = frames[.source], let right = frames[.target] {
            let minX = min(left.maxX, region.minX)
            let maxX = max(right.minX, region.maxX)
            let minY = min(region.minY, left.minY, right.minY)
            let maxY = max(region.maxY, left.maxY, right.maxY)
            let bridge = CGRect(
                x: minX,
                y: minY,
                width: maxX - minX,
                height: maxY - minY
            )
            region = region.union(bridge)
        }
        return region
    }

    // MARK: - The chip

    /// The panel's sliding effect: one mark that travels to the control under
    /// the pointer, wherever it sits in the panel.
    private var chipLayer: some View {
        ZStack(alignment: .topLeading) {
            boxWash
            glassMark
            chipInk
        }
        .allowsHitTesting(false)
        .animation(SidePanelChipState.slide(reduceMotion: reduceMotion), value: chip.target)
    }

    /// The pocket the swap disc cuts out of the input box. The chip's wash uses
    /// the same numbers, so the mark is the box and not a capsule over it.
    static var inputCut: SidePanelBoxCut {
        SidePanelBoxCut(centreY: -rowGap, radius: discRadius, fillet: seamFillet, corner: boxRadius)
    }

    /// Every box's outline: one corner for the input and the result.
    static var resultOutline: AnyShape {
        AnyShape(RoundedRectangle(cornerRadius: boxRadius, style: .continuous))
    }

    /// Whether the pointer is holding a marked control. A held box is not a
    /// button, so it keeps its resting wash.
    private var pressedMark: Bool {
        chip.pressed && chip.target?.isBox == false
    }

    /// The control the mark rests on, or the one it last marked.
    private var markedTarget: SidePanelChipTarget? {
        chip.target ?? chip.lastTarget
    }

    /// The two boxes aren't buttons: their words sit on the text itself, so the
    /// mark washes them neutrally and spills no light.
    private var markedIsControl: Bool {
        markedTarget?.isControl ?? false
    }

    /// The wash a marked control takes: faint enough to leave the control's
    /// own glass and ink readable.
    private var washFill: Color {
        chip.markFill(for: markedTarget)
    }

    /// The light the mark spills just outside the control's rim.
    private var markGlow: Color {
        chip.markGlow(for: markedTarget)
    }

    /// The mark under the pointer, lit in its own silhouette. A box takes the
    /// neutral wash the kit's glass carries. A button takes the same wash only
    /// where there is no Liquid Glass; above that, `glassMark` is the mark.
    @ViewBuilder
    private var boxWash: some View {
        if let rect = markedRect,
           markedTarget?.isBox == true || !SidePanelChipState.hasLiquidGlass {
            ZStack(alignment: .topLeading) {
                washShape
                    .stroke(markGlow, lineWidth: SidePanelChipState.markGlowWidth)
                    .blur(radius: SidePanelChipState.markGlowRadius)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                washShape
                    .fill(washFill)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            }
            .opacity(chip.target == nil ? 0 : 1)
            .animation(SidePanelChipState.slide(reduceMotion: reduceMotion), value: rect)
            .animation(DroppyAnimation.hoverQuick, value: pressedMark)
            .animation(DroppyAnimation.state, value: markedIsControl)
            .animation(DroppyAnimation.state, value: chip.target == nil)
        }
    }

    /// The silhouette the wash takes: the input keeps its disc pocket, the
    /// result is a plain box, and a menu row follows the menu's own corners.
    private var washShape: AnyShape {
        if let rect = markedRect, abs(rect.width - rect.height) < 0.5, markedIsControl {
            return AnyShape(Circle())
        }
        switch markedTarget {
        case .input:
            return AnyShape(SidePanelBoxChipShape(cut: Self.inputCut))
        case .result:
            return AnyShape(RoundedRectangle(cornerRadius: Self.boxRadius, style: .continuous))
        case .menuCapture, .menuSelect, .menuPin, .menuSettings:
            return AnyShape(Capsule(style: .continuous))
        default:
            return AnyShape(Capsule(style: .continuous))
        }
    }

    /// The mark under the pointer: one capsule of Liquid Glass, on macOS 26.
    /// The control's ink reads through it, so the glass needs no copy of it.
    @ViewBuilder
    private var glassMark: some View {
        if SidePanelChipState.hasLiquidGlass,
           let marked = markedTarget, !marked.isBox,
           let rect = markedRect {
            SidePanelChipGlass(rect: rect)
                .opacity(chip.target == nil ? 0 : 1)
                .animation(SidePanelChipState.slide(reduceMotion: reduceMotion), value: rect)
                .animation(DroppyAnimation.state, value: chip.target == nil)
        }
    }

    /// The marked control's own ink, redrawn above the glass so its glyph and
    /// words stay crisp. Each case mirrors the control it marks; a menu row
    /// reads the same content the row itself draws.
    @ViewBuilder
    private func chipInk(for target: SidePanelChipTarget) -> some View {
        switch target {
        case .source:
            PillLanguageLabel(
                text: sourceLabel(for: model),
                highlighted: true,
                fontSize: headerFontSize,
                alignment: .center,
                edgeInset: headerEdgeInset
            )
        case .target:
            PillLanguageLabel(
                text: model.name(for: model.targetID),
                highlighted: true,
                fontSize: headerFontSize,
                alignment: .center,
                edgeInset: headerEdgeInset
            )
        case .resultTarget:
            PillLanguageLabel(
                text: model.name(for: model.targetID),
                highlighted: true,
                fontSize: headerFontSize,
                alignment: .center,
                edgeInset: headerEdgeInset
            )
        case .swap:
            SidePanelSwapGlyph(spins: model.swapSpins, enabled: model.canSwap)
        case .more:
            PanelMoreGlyph(
                iconFont: 12,
                rotation: model.isToolbarExpanded ? 90 : 0
            )
        case .engine:
            PanelEngineLabel(
                model: model,
                compact: rowWidth < Self.defaultRowWidth,
                showsIcon: rowWidth < Self.defaultRowWidth
            )
        case .download:
            PanelDownloadLabel()
        case .copy:
            SidePanelPillLabel(symbol: footerActionSymbol, text: footerActionTitle)
        case .paste:
            SidePanelPillLabel(symbol: "clipboard.fill", text: L10n.tr("a11y.paste"))
        case .clear:
            PanelClearGlyph()
        case .close:
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AdaptiveColors.primaryTextAuto.opacity(0.92))
        case .menuCapture, .menuSelect, .menuPin, .menuSettings:
            if let content = PanelMoreMenu.content(
                for: target,
                model: model,
                pinned: onPin == nil ? nil : pin.isPinned,
                pinDisabled: onPin == nil ? !model.canPin : false
            ) {
                PanelToolRowLabel(
                    content: content,
                    opacity: content.disabled ? 0.4 : 1
                )
            }
        case .input, .result:
            EmptyView()
        }
    }

    @ViewBuilder
    private var chipInk: some View {
        if let target = chip.target,
           let frame = chip.frames[target],
           target.isControl {
            chipInk(for: target)
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
                .id(target)
                .transition(.opacity)
        }
    }

    /// Where the mark sits: the control under the pointer, or the one it last
    /// marked. The mark rides this frame, so every move is a slide.
    private var markedRect: CGRect? {
        chip.rect(resting: nil)
    }

    /// Opens the more menu while the pointer is on its disc or in the panel,
    /// and folds it once the pointer has left both.
    private func moreHover(_ hovering: Bool, inMenu: Bool) {
        if inMenu {
            pointerInMenu = hovering
        } else {
            pointerOnMore = hovering
        }
        if pointerOnMore || pointerInMenu {
            moreCloseTask?.cancel()
            moreCloseTask = nil
            if !model.isToolbarExpanded {
                model.isToolbarExpanded = true
            }
        } else {
            closeMoreSoon()
        }
    }

    /// Folds the menu a moment after the pointer has left it, so crossing the
    /// air between the disc and the menu never closes it.
    private func closeMoreSoon() {
        moreCloseTask?.cancel()
        moreCloseTask = nil
        guard model.isToolbarExpanded else { return }
        moreCloseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            model.isToolbarExpanded = false
        }
    }

    private var footer: some View {
        // More disc on the boxes' leading edge, engine picker on the trailing
        // one where menu rows cannot reach. Trash and the paste/copy pill sit
        // past the disc, so the action stays put when the boxes fold.
        HStack(alignment: .center, spacing: DroppySpacing.sm) {
            ToolbarCapsule(
                model: model,
                requestCapture: requestCapture,
                requestSelection: requestSelection,
                cancelSelection: cancelSelection,
                fan: .up,
                scale: 1,
                onMoreHover: { moreHover($0, inMenu: false) },
                chipTarget: .more
            )
            if hasContent {
                clearButton
                    .transition(.opacity)
            }
            footerAction
            Spacer(minLength: 0)
            PanelEngineMenu(
                model: model,
                compact: rowWidth < Self.defaultRowWidth
            )
        }
        .animation(DroppyAnimation.state, value: hasContent)
        .frame(height: Self.footerHeight, alignment: .bottom)
        .overlay(alignment: .bottomLeading) {
            // The rows start on the footer's top edge, so the disc stays in
            // sight under them and turns its dots upright. The menu stays
            // mounted so its glass can fold back into the disc.
            PanelMoreMenu(
                model: model,
                open: model.isToolbarExpanded,
                requestCapture: requestCapture,
                requestSelection: requestSelection,
                cancelSelection: cancelSelection,
                onHover: { moreHover($0, inMenu: true) },
                pinned: onPin == nil ? nil : pin.isPinned,
                onPin: onPin
            )
            .offset(y: -Self.footerHeight)
        }
    }

    /// One pill for both clipboard actions: paste until there is a result to
    /// copy, so the footer keeps one slot instead of growing a second control.
    private var footerAction: some View {
        SidePanelPillButton(
            symbol: footerActionSymbol,
            title: footerActionTitle,
            a11yKey: footerActionCopying
                ? (model.copied ? "a11y.copied" : "a11y.copy")
                : "a11y.paste",
            target: footerActionCopying ? .copy : .paste
        ) {
            if footerActionCopying {
                model.copyOutput()
            } else {
                model.pasteInput()
            }
        }
        .disabled(!footerActionCopying && !model.canPaste)
    }

    /// The footer pill reads as copy once there is a result, and as paste before
    /// that. The button and the chip's copy of its ink both read this.
    private var footerActionCopying: Bool {
        !model.output.isEmpty
    }

    private var footerActionSymbol: String {
        footerActionCopying
            ? (model.copied ? "checkmark" : "document.on.document")
            : "clipboard.fill"
    }

    private var footerActionTitle: String {
        L10n.tr(footerActionCopying ? "copy" : "a11y.paste")
    }

    /// Something the trash can clear: typed text, a result, or a status.
    private var hasContent: Bool {
        !model.input.isEmpty || Self.showsResult(for: model)
    }

    /// The footer's trash, in the same glass disc as the more control.
    private var clearButton: some View {
        Button {
            if let onClear {
                onClear()
            } else {
                model.clearInput()
            }
        } label: {
            ZStack {
                Color.clear
                    .frame(width: PanelFooterMetrics.disc, height: PanelFooterMetrics.disc)
                PanelClearGlyph()
            }
            .contentShape(Circle())
        }
        .buttonStyle(PanelPressStyle())
        .background {
            Color.clear
                .droppyGlassControlChrome(shape: AnyShape(Circle()))
        }
        .chipTarget(.clear)
        .arrowCursorRegion()
        .a11y("a11y.clear")
    }

    /// The drag handle. The panel's is the collapsed tab's silhouette on its
    /// side, part of the card's own outline; the shelf's card cannot grow, so
    /// it keeps only the bar inside the card.
    @ViewBuilder
    private var gripHandle: some View {
        if keepsGripInsideCard {
            shelfGrip
        } else {
            interactiveGrip
        }
    }

    /// The shelf's handle: the same resting bar. A tap translates the text on
    /// the opening card.
    private var shelfGrip: some View {
        let out = gripOut
        return ZStack(alignment: .bottom) {
            Color.clear
                .frame(width: Self.gripHitSize.width, height: Self.gripHitSize.height)
            Capsule(style: .continuous)
                .fill(Color(white: 0.55))
                .frame(
                    width: out ? Self.gripOutBar.width : Self.gripRestBar.width,
                    height: out ? Self.gripOutBar.height : Self.gripRestBar.height
                )
                .padding(.bottom, Self.shelfGripLift)
        }
        .contentShape(Rectangle())
        .onHover { gripHover = $0 }
        .onTapGesture { onShelfGripTap?() }
        .animation(DroppyAnimation.hover, value: out)
        .accessibilityElement()
        .accessibilityLabel(L10n.tr("a11y.translate"))
        .accessibilityHint(L10n.tr("a11y.shelfGripTranslateHint"))
        .help(L10n.tr("a11y.translate"))
    }

    private var interactiveGrip: some View {
        let out = gripOut
        return ZStack(alignment: .bottom) {
            ZStack {
                // The lobe belongs to the card's outline, so the glass covers
                // card and lobe in one layer. Only the mark is drawn here,
                // riding the same amount so it stays on the lobe.
                Capsule(style: .continuous)
                    .fill(AdaptiveColors.notchSurfaceTertiaryText)
                    .frame(
                        width: Self.gripRestBar.width
                            + (Self.gripOutBar.width - Self.gripRestBar.width) * grip.amount,
                        height: Self.gripRestBar.height
                            + (Self.gripOutBar.height - Self.gripRestBar.height) * grip.amount
                    )
                    .offset(y: Self.gripTuck / 2 - Self.gripRise * (1 - grip.amount))
            }
            .frame(width: Self.gripWidth, height: Self.gripDepth)
            // The hosting view reaches below the card's edge by the strip, so
            // the curve hangs whole under the face; only the stem stays buried.
            .padding(.bottom, Self.gripPadding + Self.gripOverlap)

            // A thin bar is a small target; the drag starts anywhere in the
            // strip under the card, including the bar's resting place inside it.
            Color.clear
                .frame(width: Self.gripHitSize.width, height: Self.gripHitSize.height)
                .contentShape(Rectangle())
                .onHover { gripHover = $0 }
                .gesture(gripGesture)
        }
        .onChange(of: out) { onGripOut($0) }
        .accessibilityElement()
        .accessibilityLabel(L10n.tr("a11y.grip"))
        .help(L10n.tr("a11y.grip"))
    }

    /// The handle is out while the pointer is on it, and stays out for a drag
    /// that pulls the card away from under it.
    private var gripOut: Bool { gripHover || gripDrag != nil }

    /// Pulling down brings the result out of the input, stretches it to the
    /// card's cap, then folds the input away; pulling up reverses it, and 24pt
    /// past the fold clears the text. A click does nothing.
    private var gripGesture: some Gesture {
        // Global, not local: the tab moves down with the card it grows, so a
        // local translation would cancel the pointer's movement and stall.
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                let start = visibleResultHeight
                var drag = gripDrag ?? GripDrag(
                    startHeight: start,
                    foldStart: max(start - inputHeight * inputFold, restingResultHeight),
                    pulled: start,
                    deadband: 0,
                    hasResult: !model.output.isEmpty,
                    foldsBySetting: showsAlone
                )
                if !drag.started {
                    let translation = value.translation
                    // Vertical only: this tab's drag is the result box's grip,
                    // so a sideways jitter must not fold it.
                    guard abs(translation.height) >= Self.gripThreshold else {
                        gripDrag = drag
                        return
                    }
                    drag.started = true
                    drag.deadband = translation.height < 0
                        ? -Self.gripThreshold
                        : Self.gripThreshold
                }
                // The pull is symmetric: down grows the result out of the
                // input, up folds it back under the pointer.
                drag.pulled = Self.gripHeight(
                    start: drag.startHeight,
                    translation: value.translation.height,
                    deadband: drag.deadband,
                    box: inputHeight,
                    full: drag.hasResult,
                    foldStart: drag.foldStart
                )
                // A pull that fills the resting box translates, so one gesture
                // opens the box and asks for text; a full box is only resized.
                if !drag.translateStarted,
                   Self.startsTranslation(
                       pulled: drag.pulled,
                       hasInput: model.canTranslate,
                       hasOutput: !model.output.isEmpty,
                       isTranslating: model.status == .translating,
                       resting: restingResultHeight
                   ) {
                    drag.translateStarted = true
                    model.translate()
                }
                gripDrag = drag
                applyGrip(
                    drag.pulled,
                    full: drag.hasResult,
                    foldStart: drag.foldStart,
                    foldsBySetting: drag.foldsBySetting
                )
            }
            .onEnded { _ in
                guard let drag = gripDrag else { return }
                gripDrag = nil
                // A click on the handle does nothing: only a drag moves the
                // box.
                if !drag.started { return }
                if drag.pulled <= -Self.gripClearPull {
                    clearFromGrip()
                } else {
                    settleGrip(drag)
                }
            }
    }

    private var header: some View {
        Group {
            if showsResultPicker {
                resultHeaderRow
            } else {
                headerRow
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The result page's own row, above its box: the target on the left and
    /// the card's close on the right.
    private var resultHeaderRow: some View {
        HStack(spacing: 0) {
            resultTargetMenu
            Spacer(minLength: DroppySpacing.sm)
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AdaptiveColors.primaryTextAuto.opacity(0.92))
                        .frame(width: PanelFooterMetrics.disc, height: PanelFooterMetrics.disc)
                        .contentShape(Circle())
                }
                .buttonStyle(PanelPressStyle())
                .background {
                    Color.clear
                        .droppyGlassControlChrome(shape: AnyShape(Circle()))
                }
                .chipTarget(.close)
                .arrowCursorRegion()
                .a11y("panel.dismiss")
            }
        }
        .frame(height: pillHeight)
    }

    /// A grouped shelf slot is narrower than the panel, so its labels and
    /// their air shrink with the row instead of clipping.
    private var halfWidth: CGFloat { (rowWidth - Self.discRadius * 2) / 2 }
    private var headerFontSize: CGFloat {
        rowWidth < Self.defaultRowWidth ? Self.labelFontSize : Self.bodyFontSize
    }
    private var headerEdgeInset: CGFloat {
        rowWidth < Self.defaultRowWidth ? 6 : Self.pillEdgeInset
    }

    /// The row capsule with the swap pocket cut through its glass, then the
    /// disc, its glyph and both menus. The chip only washes the marked control:
    /// labels and glyph already stand on glass.
    private var headerRow: some View {
        ZStack(alignment: .topLeading) {
            let capsule = AnyShape(Capsule(style: .continuous))
            Color.clear
                .frame(width: rowWidth, height: pillHeight)
                .droppyGlassControlChrome(shape: capsule)
                .mask {
                    GlassPocketMask(
                        shape: capsule,
                        centreY: pillHeight,
                        radius: Self.discRadius,
                        bottomFillet: Self.seamFillet
                    )
                }

            swapButton
                .offset(
                    x: (rowWidth - Self.buttonDiameter) / 2,
                    y: pillHeight - Self.buttonDiameter / 2
                )

            // On top so the labels stay crisp; they never overlap the disc.
            HStack(spacing: 0) {
                LanguageMenu(
                    model: model,
                    selection: $model.sourceID,
                    includesAuto: true,
                    label: sourceLabel(for: model),
                    inPillRow: true,
                    highlighted: chip.target == .source,
                    fontSize: headerFontSize,
                    alignment: .center,
                    edgeInset: headerEdgeInset,
                    chipTarget: .source,
                    availableIDs: model.installedSourceIDs
                )
                // The mark is the pill itself: the half's full height and out
                // to the capsule's end, so the effect cannot read as a smaller
                // capsule floating inside the row.
                .padding(.leading, PanelFooterMetrics.chipInset)
                .chipTarget(.source)
                .frame(width: halfWidth)

                // The pocket's width: both labels end on the red line.
                Color.clear
                    .frame(width: Self.discRadius * 2)

                LanguageMenu(
                    model: model,
                    selection: $model.targetID,
                    includesAuto: false,
                    label: model.name(for: model.targetID),
                    inPillRow: true,
                    highlighted: chip.target == .target,
                    fontSize: headerFontSize,
                    alignment: .center,
                    edgeInset: headerEdgeInset,
                    chipTarget: .target,
                    availableIDs: model.installedTargetIDs
                )
                .padding(.trailing, PanelFooterMetrics.chipInset)
                .chipTarget(.target)
                .frame(width: halfWidth)
            }
            .frame(width: rowWidth, height: pillHeight)
        }
        .frame(width: rowWidth, height: pillHeight + Self.discRadius, alignment: .topLeading)
    }

    /// The swap disc's glass, hit area and glyph. The glass stays put: the chip
    /// only lights the disc's own circle, so the arrows never blink.
    private var swapButton: some View {
        Button {
            model.swapLanguages()
        } label: {
            ZStack {
                Color.clear
                    .frame(width: Self.buttonDiameter, height: Self.buttonDiameter)
                SidePanelSwapGlyph(spins: model.swapSpins, enabled: model.canSwap)
            }
            .contentShape(Circle())
        }
        .buttonStyle(PanelPressStyle())
        .background {
            Color.clear
                .droppyGlassControlChrome(shape: AnyShape(Circle()))
        }
        .chipTarget(.swap)
        .arrowCursorRegion()
        .a11y("a11y.swap")
        .disabled(!model.canSwap)
    }
}

/// The swap disc's glyph, drawn apart from the disc's glass: the hover mark is
/// the disc alone, and the arrows never move with it.
private struct SidePanelSwapGlyph: View {
    var spins: Int
    var enabled: Bool

    var body: some View {
        Image(systemName: "repeat")
            .font(.system(size: SidePanelContentView.buttonDiameter * 0.4, weight: .bold))
            .foregroundStyle(AdaptiveColors.primaryTextAuto.opacity(0.92))
            // Sideways arrows: the languages sit side by side. Each swap turns
            // the pair half a circle, so the arrows point the other way.
            .rotationEffect(.degrees(Double(spins) * 180))
            .animation(DroppyAnimation.state, value: spins)
            .frame(width: SidePanelContentView.buttonDiameter, height: SidePanelContentView.buttonDiameter)
            .opacity(enabled ? 1 : 0.65)
    }
}

/// The translation under the input box: the result, the progress or the
/// status, with copy in its bottom-right corner.
private struct PanelResultTile: View {
    @ObservedObject var model: TranslateModel
    /// A held grip is direct manipulation: the status may turn into the result
    /// mid-drag, and crossfading it would read as the box's content sliding.
    var isDragging = false
    /// How much of the box is on screen. The status block is one unit: while
    /// the moving edge still crosses it, the whole block blurs together, so
    /// the download never reads sharper than the sentence under it.
    var reveal: CGFloat = 1
    /// The mount's box is already fitted to the status, so the block centres
    /// in it instead of the resting box.
    var fitsHeight = false
    @Environment(\.sidePanelChip) private var chip

    /// The block clears the edge's blur band at about three quarters open;
    /// below that it blurs in proportion to how closed the box is.
    private static let statusClearReveal: CGFloat = 0.75
    private static let statusBlurRamp: CGFloat = 0.15
    private var statusBlur: CGFloat {
        let closed = (Self.statusClearReveal - reveal) / Self.statusBlurRamp
        return SidePanelContentView.resultEdgeBlur * min(max(closed, 0), 1)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if !model.output.isEmpty {
                TranslationOutputScrollView(
                    text: model.output,
                    resetToken: model.outputScrollResetToken.uuidString,
                    scrollerTopInset: SidePanelContentView.resultTextTop,
                    scrollerBottomInset: 48,
                    textInset: SidePanelContentView.resultTextTop,
                    fontSize: SidePanelContentView.bodyFontSize
                )
            } else if model.status == .translating {
                HStack(spacing: DroppySpacing.sm) {
                    ProgressView().controlSize(.small)
                    Text(L10n.tr("panel.translating"))
                        .font(.system(size: SidePanelContentView.labelFontSize))
                        .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                        .cardTextShadow()
                }
                .padding(.leading, 7)
                .padding(.top, 23)
            } else if model.notice == nil, model.status == .idle {
                Text(L10n.outputPlaceholder(for: model.targetID))
                    .font(.system(size: SidePanelContentView.labelFontSize))
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                    .cardTextShadow()
                    .padding(.leading, 7)
                    .padding(.top, 23)
            } else if let message = model.notice ?? statusMessage(for: model) {
                // Top-aligned like the result text: a drag grows the box
                // downward, and a centred stack would drift up as it does.
                VStack(spacing: DroppySpacing.sm) {
                    // The download takes the user to settings, so it sits on
                    // top and the sentence under it says what it brings.
                    if model.status == .needsDownload {
                        Button {
                            model.requestDownload()
                        } label: {
                            PanelDownloadLabel()
                        }
                        .buttonStyle(DroppyAccentButtonStyle(size: .small))
                        .disabled(model.prepare != nil)
                        .chipTarget(SidePanelContentView.marksChip(reveal: reveal) ? .download : nil)
                        .a11y("status.downloadShort")
                    }
                    Text(message)
                        .font(.system(size: SidePanelContentView.labelFontSize))
                        .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                        .cardTextShadow()
                        .multilineTextAlignment(.center)
                    if model.canRetryTranslation {
                        Button {
                            model.retryTranslation()
                        } label: {
                            Text(L10n.tr("retry"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AdaptiveColors.primaryTextAuto.opacity(0.92))
                                .cardTextShadow()
                        }
                        .buttonStyle(DroppyQuietButtonStyle(size: .small))
                        .arrowCursorRegion()
                        .a11y("a11y.retry")
                    }
                }
                // Centred at rest, then pinned to the tile's top: a drag grows
                // the box downward, so the stack must not ride the new height.
                .frame(
                    width: nil,
                    height: fitsHeight ? nil : SidePanelContentView.resultBoxHeight,
                    alignment: .center
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: fitsHeight ? .center : .top
                )
                .blur(radius: statusBlur)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, PanelTileText.sideInset)
        // The same rim as every box: words fade as they reach the glass
        // instead of ending on a hard line.
        .panelTileEdgeFade()
        .animation(isDragging ? nil : DroppyAnimation.state, value: model.output.isEmpty)
    }
}

/// A named control in the footer: the glyph and the word, so it reads as an
/// action rather than as another disc. The chip lights the pill and leaves the
/// label on its own glass.
private struct SidePanelPillButton: View {
    var symbol: String
    var title: String
    var a11yKey: String
    var target: SidePanelChipTarget
    var action: () -> Void

    /// The pill takes the disc's height, so the row shares one centreline and
    /// the chip marks equal glass.
    static let height: CGFloat = PanelFooterMetrics.disc

    @Environment(\.sidePanelChip) private var chip

    var body: some View {
        Button(action: action) {
            SidePanelPillLabel(symbol: symbol, text: title)
                .padding(.horizontal, 9)
                .frame(height: Self.height)
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(PanelPressStyle())
        .background {
            Color.clear
                .droppyGlassControlChrome(shape: AnyShape(Capsule(style: .continuous)))
        }
        .chipTarget(target)
        .arrowCursorRegion()
        .a11y(a11yKey)
    }
}

/// The pill's ink, drawn once on the button's own glass.
private struct SidePanelPillLabel: View {
    var symbol: String
    var text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
            Text(text)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(AdaptiveColors.primaryTextAuto.opacity(0.92))
        .cardTextShadow()
    }
}

/// The footer trash's glyph, on its own glass.
private struct PanelClearGlyph: View {
    var body: some View {
        Image(systemName: "trash")
            .font(.system(size: 12))
            .foregroundStyle(AdaptiveColors.primaryTextAuto.opacity(0.92))
    }
}

/// The download pill's label. The size is the kit's small pill.
private struct PanelDownloadLabel: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.down.circle")
            Text(L10n.tr("status.downloadShort"))
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(AdaptiveColors.primaryTextAuto.opacity(0.92))
        .cardTextShadow()
    }
}

/// The footer's wordmark is also the engine picker: it says what translates
/// the text and changes it in place, without a trip to settings.
struct PanelEngineMenu: View {
    @ObservedObject var model: TranslateModel
    /// A grouped shelf slot keeps only the translate mark; the engine's name
    /// would push the paste and copy pills off the card.
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            if !compact {
                // The mark stays outside the glass, so the control matches the
                // footer's other buttons instead of reading as its own size.
                Image(systemName: "translate")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AdaptiveColors.primaryTextAuto.opacity(0.92))
                    .cardTextShadow()
                    .accessibilityHidden(true)
            }
            capsule
        }
        .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
    }

    /// The capsule holds only the engine's name; the translate mark sits
    /// outside it and the chip marks this part alone.
    private var capsule: some View {
        Menu {
            ForEach(TranslationEngine.allCases) { engine in
                Toggle(isOn: selected(engine)) {
                    Text(label(for: engine))
                }
            }
        } label: {
            PanelEngineLabel(model: model, compact: compact, showsIcon: compact)
                .padding(.horizontal, 8)
                .frame(height: PanelFooterMetrics.engineHeight)
                .contentShape(Capsule(style: .continuous))
        }
        .menuIndicator(.hidden)
        .buttonStyle(PanelPressStyle())
        .background {
            Color.clear
                .droppyGlassControlChrome(shape: AnyShape(Capsule(style: .continuous)))
        }
        .chipTarget(.engine)
        .arrowCursorRegion()
        .help(title)
        .accessibilityLabel(Text(verbatim: title))
    }

    /// One tick per engine; picking the ticked one again changes nothing.
    private func selected(_ engine: TranslationEngine) -> Binding<Bool> {
        Binding(
            get: { model.translationEngine == engine },
            set: { on in if on { model.setTranslationEngine(engine) } }
        )
    }

    private var title: String {
        "\(L10n.tr("panel.translateWith")) \(label(for: model.translationEngine))"
    }

    private func label(for engine: TranslationEngine) -> String {
        PanelEngineLabel.name(for: engine, provider: model.translationProvider)
    }
}

/// The engine capsule's ink. The chip washes the capsule and leaves this view
/// where the menu put it, so the text never shifts by the menu's inset.
struct PanelEngineLabel: View {
    @ObservedObject var model: TranslateModel
    /// The narrow footer keeps the translate mark alone.
    var compact = false
    /// The full footer draws the mark outside the glass; the narrow footer
    /// keeps it inside, where it is the whole control.
    var showsIcon = true

    var body: some View {
        HStack(spacing: 4) {
            if showsIcon {
                Image(systemName: "translate")
                    .font(.system(size: 11, weight: .medium))
            }
            if !compact {
                Text(Self.name(for: model))
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(AdaptiveColors.primaryTextAuto.opacity(0.92))
        .cardTextShadow()
    }

    /// The network engine speaks for its provider: "OpenAI" says more than
    /// "AI Translation".
    static func name(for model: TranslateModel) -> String {
        name(for: model.translationEngine, provider: model.translationProvider)
    }

    static func name(for engine: TranslationEngine, provider: TranslationProvider) -> String {
        L10n.tr(engine.nameKey(provider: provider))
    }
}

/// A box's swap pocket and corner.
struct SidePanelBoxCut: Equatable {
    var centreY: CGFloat
    var radius: CGFloat
    var fillet: CGFloat
    var corner: CGFloat
}

/// A box's silhouette: its rounded rect with the swap pocket removed, so the
/// chip that marks the box is the box.
struct SidePanelBoxChipShape: Shape {
    var cut: SidePanelBoxCut

    func path(in rect: CGRect) -> Path {
        let box = Path(
            roundedRect: rect,
            cornerRadius: min(cut.corner, rect.width / 2, rect.height / 2),
            style: .continuous
        )
        let pocket = DiscCutShape(
            centreY: cut.centreY,
            radius: cut.radius,
            topFillet: cut.fillet
        ).path(in: rect)
        return box.subtracting(pocket)
    }
}

/// A disc cut into a surface, its mouths filleted so straight edges ease into
/// the disc instead of meeting it at a point. `centreY` is measured from the
/// rect's top; a disc that clears an edge leaves a pocket there.
struct DiscCutShape: Shape {
    var centreY: CGFloat
    var radius: CGFloat
    /// Fillet at the top edge; 0 leaves the crossing sharp.
    var topFillet: CGFloat = 0
    /// Fillet at the bottom edge; 0 leaves the crossing sharp.
    var bottomFillet: CGFloat = 0

    /// Where the disc leaves one edge: the mouth on the edge, its fillet circle
    /// and the point where the two meet the disc.
    private struct Mouth {
        var edge: CGPoint
        var centre: CGPoint
        var fillet: CGFloat
        var tangent: CGPoint
    }

    func path(in rect: CGRect) -> Path {
        let disc = CGPoint(x: rect.midX, y: rect.minY + centreY)
        let crossesTop = disc.y - radius < rect.minY
        let crossesBottom = disc.y + radius > rect.maxY
        guard crossesTop || crossesBottom else { return Path() }

        // Fillets sit one radius inside the surface, tangent to its edge and to
        // the disc, so the joint has no kink.
        func mouth(on edgeY: CGFloat, inward: CGFloat, side: CGFloat, fillet: CGFloat) -> Mouth {
            let centreY = edgeY + inward * fillet
            let dy = centreY - disc.y
            let reach = radius + fillet
            let dx = sqrt(max(0, reach * reach - dy * dy))
            return Mouth(
                edge: CGPoint(x: disc.x + side * dx, y: edgeY),
                centre: CGPoint(x: disc.x + side * dx, y: centreY),
                fillet: fillet,
                tangent: CGPoint(
                    x: disc.x + side * dx * radius / reach,
                    y: disc.y + dy * radius / reach
                )
            )
        }

        func filletArc(_ path: inout Path, from start: CGPoint, to end: CGPoint, _ mouth: Mouth) {
            guard mouth.fillet > 0 else { return }
            addArc(&path, around: mouth.centre, radius: mouth.fillet, from: start, to: end)
        }

        var path = Path()
        if crossesTop && crossesBottom {
            let topLeft = mouth(on: rect.minY, inward: 1, side: -1, fillet: topFillet)
            let topRight = mouth(on: rect.minY, inward: 1, side: 1, fillet: topFillet)
            let bottomLeft = mouth(on: rect.maxY, inward: -1, side: -1, fillet: bottomFillet)
            let bottomRight = mouth(on: rect.maxY, inward: -1, side: 1, fillet: bottomFillet)

            path.move(to: topLeft.edge)
            filletArc(&path, from: topLeft.edge, to: topLeft.tangent, topLeft)
            addArc(&path, around: disc, radius: radius, from: topLeft.tangent, to: bottomLeft.tangent)
            filletArc(&path, from: bottomLeft.tangent, to: bottomLeft.edge, bottomLeft)
            path.addLine(to: bottomRight.edge)
            filletArc(&path, from: bottomRight.edge, to: bottomRight.tangent, bottomRight)
            addArc(&path, around: disc, radius: radius, from: bottomRight.tangent, to: topRight.tangent)
            filletArc(&path, from: topRight.tangent, to: topRight.edge, topRight)
        } else {
            let edgeY = crossesTop ? rect.minY : rect.maxY
            let inward: CGFloat = crossesTop ? 1 : -1
            let edgeFillet = crossesTop ? topFillet : bottomFillet
            let left = mouth(on: edgeY, inward: inward, side: -1, fillet: edgeFillet)
            let right = mouth(on: edgeY, inward: inward, side: 1, fillet: edgeFillet)

            path.move(to: left.edge)
            filletArc(&path, from: left.edge, to: left.tangent, left)
            addArc(&path, around: disc, radius: radius, from: left.tangent, to: right.tangent)
            filletArc(&path, from: right.tangent, to: right.edge, right)
        }
        path.closeSubpath()
        return path
    }

    /// Cubic arc taking the short way round, split under a quarter turn each.
    private func addArc(_ path: inout Path, around origin: CGPoint, radius: CGFloat, from start: CGPoint, to end: CGPoint) {
        var angle = atan2(start.y - origin.y, start.x - origin.x)
        var delta = atan2(end.y - origin.y, end.x - origin.x) - angle
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        let steps = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(steps)
        let handle = 4 / 3 * tan(step / 4) * radius
        for _ in 0..<steps {
            let next = angle + step
            let fromPoint = CGPoint(x: origin.x + radius * cos(angle), y: origin.y + radius * sin(angle))
            let toPoint = CGPoint(x: origin.x + radius * cos(next), y: origin.y + radius * sin(next))
            path.addCurve(
                to: toPoint,
                control1: CGPoint(x: fromPoint.x - handle * sin(angle), y: fromPoint.y + handle * cos(angle)),
                control2: CGPoint(x: toPoint.x + handle * sin(next), y: toPoint.y - handle * cos(next))
            )
            angle = next
        }
    }
}

/// Every panel button dips on press, with the kit's clock. Hover is the chip's
/// mark, or the glass's own wash.
struct PanelPressStyle: ButtonStyle {
    var pressScale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressScale : 1)
            .animation(DroppyAnimation.hoverQuick, value: configuration.isPressed)
    }
}
