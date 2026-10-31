import DroppyKit
import SwiftUI

/// The direction a drag on the shelf's handle asks the card to move.
enum ShelfGripDrag: Equatable {
    case up
    case down
}

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
    /// The pointer is on the handle, or a drag holds it. The panel answers by
    /// growing the card's own outline.
    var onGripOut: (Bool) -> Void = { _ in }
    /// The shelf's card cannot grow, so its handle keeps the bar inside the
    /// card and skips the tab that hangs below the panel's edge.
    var keepsGripInsideCard = false
    var glassTiles = true
    /// The tallest body this mount may draw; the shelf's fixed slot sets it.
    var maxBodyHeight = SidePanelContentView.maxPanelBodyHeight
    /// The shortest the input box may get. The shelf keeps the common floor;
    /// the edge panel passes its taller opening.
    var boxFloor = SidePanelContentView.minBoxHeight
    /// The shelf narrows the language row when it shares a grouped slot.
    var rowWidth = SidePanelContentView.defaultRowWidth
    /// The shelf's card step, 0 to 2. The host owns the height; this only
    /// decides how much of the input and the result the card shows.
    var shelfStep = 0
    /// How far the shelf's card has grown from its opening height to the
    /// result's height, 0…1. The host writes it through the card's frame, so a
    /// card resize needs no animation of its own here.
    var shelfGrowth: CGFloat = 1
    var onShelfGripTap: (() -> Void)?
    /// A drag on the shelf's handle: down asks for the next card height, up
    /// for the one below. The host keeps the height; the drag only picks it.
    var onShelfGripDrag: ((ShelfGripDrag) -> Void)?
    /// Starts a translation. The shelf raises its card so the result has room;
    /// the panel keeps its own submit.
    var onSubmit: (() -> Void)?

    /// Pins the edge panel's window. Nil on the shelf, whose menu pins the
    /// shelf through the model instead.
    var onPin: (() -> Void)?

    /// The card height the panel needs to show this content. The window sizes
    /// itself to it, so the box never leaves dead space under it. `animated`
    /// is false for the first layout and for a grip drag, which must track the
    /// pointer 1:1.
    var onBodyHeight: (CGFloat, Bool) -> Void = { _, _ in }

    /// One line of text plus the editor's insets, so the empty box still has
    /// air above and below the placeholder. This is the shelf's short step.
    static let minBoxHeight: CGFloat = 92
    /// The edge panel opens its empty box a little taller, so the card does
    /// not open pinched; its floor follows the panel, not the shelf's step.
    static let panelBoxFloor: CGFloat = 112
    /// Beyond this the editor scrolls instead of growing.
    static let maxBoxHeight: CGFloat = 150

    /// Air above and below the text, equal so a single line lands on the box's
    /// mid-height. The paste and clear discs sit inside the bottom inset, and
    /// the line stops just above them.
    private static let editorTopInset: CGFloat = 37.5
    private static let editorBottomInset: CGFloat = 37.5
    /// The translation box under the input at its resting height; the grip
    /// under the card stretches it taller. Below both sits the control strip.
    static let resultBoxHeight: CGFloat = 240
    /// The transparent band below the card's face. The window grows by it, and
    /// the drag tab hangs in it.
    static let gripStrip: CGFloat = 36
    /// How far the content view reaches below its boxes: the band above, plus
    /// the air the tab keeps under it. A control outside its hosting view takes
    /// no click, so the view must cover the tab.
    static let pillStrip: CGFloat = gripStrip + 8
    private static let resultGap: CGFloat = 6
    /// The footer holds the more disc plus the rim that separates it from the
    /// box above — the same 6pt as the header's.
    private static let footerHeight: CGFloat = PanelFooterMetrics.disc + 6
    /// The panel's body text, its labels and its secondary text.
    static let bodyFontSize: CGFloat = 14
    static let labelFontSize: CGFloat = 13
    fileprivate static let iconFontSize: CGFloat = 12
    /// The language row's width; both halves stay symmetric around the swap
    /// disc at the card's centre.
    static let defaultRowWidth: CGFloat = 254
    /// One label's box: the row minus the pocket, halved. Its inner edge is
    /// the pocket's tangent.
    static var rowHalf: CGFloat { (defaultRowWidth - discRadius * 2) / 2 }
    /// The air a language label keeps from its half's edges. Each half is
    /// centred on the swap disc, so both labels centre on their own side and
    /// the pair still frames the disc.
    private static let pillEdgeInset: CGFloat = 10
    /// The mark's air above and below a language label. The row's sides are
    /// cut by the padding each half already carries, so the mark ends on the
    /// pocket's tangent and 3pt inside the capsule's end.
    private static let rowMarkInset = PanelFooterMetrics.chipInset
    /// The pocket cut around the swap disc; its radius leaves a 6pt rim
    /// between the pocket and the 40pt disc.
    static let discRadius: CGFloat = 26
    static let buttonDiameter: CGFloat = 40
    /// Gap between the pill row and the text box.
    private static let rowGap: CGFloat = 6
    /// Rounds the mouths that meet the seam.
    private static let seamFillet: CGFloat = 10

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
    /// How far the pointer has pulled the shelf's bar from its rest position;
    /// the bar follows it, then asks the host for a step when it lets go.
    @State private var shelfGripPull: CGFloat = 0
    /// How far the input has folded into the result, 0…1. Step 3 hands the
    /// input's space to the result, so the card stays at its tallest while the
    /// result takes the whole face.
    @State private var inputFold: CGFloat = 0
    /// A drag on the handle: the result height it started from, the height at
    /// which its input starts folding, the height it has pulled to now, the
    /// dead band it started with, and whether the pointer has left the click's
    /// slop.
    private struct GripDrag {
        var startHeight: CGFloat
        /// The result height where the input begins to fold. Stored per drag so
        /// a box that is already folded unfolds from the same seam.
        var foldStart: CGFloat
        var pulled: CGFloat
        /// The 6pt removed from the first movement, signed by the direction the
        /// drag started in, so reversing does not jump by twice the slop.
        var deadband: CGFloat
        /// Step 3 (input folds into the result) needs something to read. A
        /// status is not a result: the box stops at its resting height instead
        /// of stretching for text that never came.
        var hasResult: Bool
        var started = false
        /// A pull that reached the end of step 2 already asked for the
        /// translation; one drag never asks twice.
        var translateStarted = false
    }
    /// The pointer is on the footer's more disc, or inside its open menu.
    @State private var pointerOnMore = false
    @State private var pointerInMenu = false
    /// The menu follows the pointer; this covers the gap between the disc and
    /// the panel, so crossing it never closes the menu.
    @State private var moreCloseTask: Task<Void, Never>?

    /// `boxHeight` seeds the first frame; the editor takes over after its first
    /// layout. Previewing a known state needs the seed, because the render test
    /// cannot wait for the hosting view's second pass.
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
        /// The held drag a render test cannot produce; seeds the grip so the
        /// armed clear state can be photographed.
        gripPull: CGFloat? = nil,
        /// The settled step 3 state: the result fills the card and the input is
        /// folded away. `fold` also seeds a half-fold for a render test.
        fold: CGFloat = 0,
        keepsGripInsideCard: Bool = false,
        glassTiles: Bool = true,
        maxBodyHeight: CGFloat = SidePanelContentView.maxPanelBodyHeight,
        rowWidth: CGFloat = SidePanelContentView.defaultRowWidth,
        shelfStep: Int = 0,
        shelfGrowth: CGFloat = 1,
        onShelfGripTap: (() -> Void)? = nil,
        onShelfGripDrag: ((ShelfGripDrag) -> Void)? = nil,
        onSubmit: (() -> Void)? = nil,
        onGripOut: @escaping (Bool) -> Void = { _ in },
        onPin: (() -> Void)? = nil,
        onBodyHeight: @escaping (CGFloat, Bool) -> Void = { _, _ in }
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
        self.glassTiles = glassTiles
        self.maxBodyHeight = maxBodyHeight
        self.boxFloor = boxFloor
        self.rowWidth = rowWidth
        self.shelfStep = shelfStep
        self.shelfGrowth = min(max(shelfGrowth, 0), 1)
        self.onShelfGripTap = onShelfGripTap
        self.onShelfGripDrag = onShelfGripDrag
        self.onSubmit = onSubmit
        self.onBodyHeight = onBodyHeight
        let box = boxHeight ?? boxFloor
        let fold = min(max(fold, 0), 1)
        _inputHeight = State(initialValue: box)
        _inputFold = State(initialValue: fold)
        _resultHeight = State(
            initialValue: Self.resultBoxHeight + box * fold
        )
        _resultReveal = State(
            initialValue: Self.showsResult(for: model) ? 1 : 0
        )
        _gripDrag = State(
            initialValue: gripPull.map {
                GripDrag(
                    startHeight: $0,
                    foldStart: max($0, Self.resultBoxHeight),
                    pulled: $0,
                    deadband: 0,
                    hasResult: false
                )
            }
        )
    }

    private var pillHeight: CGFloat { LanguageMenu.pillRowHeight }

    /// The island's 16pt shelf inset plus the 1.5pt widget slot: the gap the
    /// panel card keeps around its content on every edge.
    static var inset: CGFloat {
        DroppyShellMetrics.shelfContentInsets(usesNotchStyle: false).leading
            + DroppyShellMetrics.shelfWidgetSlotInset
    }

    /// The card body that holds the header, a box of `box` points and, when a
    /// translation is shown, the result box and the footer under it. The box
    /// tucks under the disc by `discRadius - rowGap`. `resultReveal` shrinks
    /// the result's height for a grip drag; its seam stays put, so the box
    /// grows downward instead of sliding.
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
        !model.output.isEmpty || model.status != .idle || model.notice != nil
    }

    /// The hosting view that draws a body of `body`: the card's content inset
    /// on every edge, plus the strip the drag tab hangs in.
    static func contentHeight(forBody body: CGFloat) -> CGFloat {
        body - inset * 2 + pillStrip
    }

    /// The shelf card's height for one step: the host's corner inset, the
    /// language row when the step keeps it, the boxes and the footer. The
    /// descriptor's height is the widget's whole rectangle, so the host's
    /// inset is part of it.
    static func shelfCardHeight(forRoom room: CGFloat, showsHeader: Bool) -> CGFloat {
        DroppySpacing.sm * 2 + shelfContentHeight(forRoom: room, showsHeader: showsHeader)
    }

    /// The card's content without the host's corner inset. A notch card
    /// spends the descriptor's extra 16pt on that inset; a solo island card
    /// spends none and gives it to the boxes, so the footer stays on the
    /// bottom edge in both.
    static func shelfContentHeight(forRoom room: CGFloat, showsHeader: Bool) -> CGFloat {
        (showsHeader ? LanguageMenu.pillRowHeight + rowGap : 0) + room + footerHeight
    }

    /// The room the shelf's second step gives the input and the full result.
    static var shelfResultRoom: CGFloat { minBoxHeight + resultGap + resultBoxHeight }
    /// The room the third step has once the language row is gone.
    static var shelfFullRoom: CGFloat {
        shelfResultRoom + LanguageMenu.pillRowHeight + rowGap
    }

    /// The shortest the card opens to with the input alone. The shelf's step
    /// keeps the common box floor; the edge panel opens taller.
    static var minBodyHeight: CGFloat { bodyHeight(forBox: minBoxHeight) }
    static var panelMinBodyHeight: CGFloat { bodyHeight(forBox: panelBoxFloor) }
    static var maxBodyHeight: CGFloat { bodyHeight(forBox: maxBoxHeight) }
    /// The tallest card, with the result box open. The window clamp uses this.
    static var maxPanelBodyHeight: CGFloat {
        bodyHeight(forBox: maxBoxHeight, result: true)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
            header
                .frame(height: pillHeight + Self.discRadius, alignment: .top)
                .zIndex(1)
                // Step 3 ends with the result on the whole face; the language
                // row clears out once the result is about to reach it.
                .opacity(headerOpacity)
                .allowsHitTesting(headerOpacity > 0)
            // The boxes ride the disc's pocket as one group: the tuck holds
            // even when step 3 has shrunk the input to nothing.
            VStack(spacing: 0) {
                SourceTile(
                    model: model,
                    notch: nil,
                    showsLanguageMenu: false,
                    glassTile: glassTiles,
                    tileCornerRadius: 28,
                    editorTopInset: Self.editorTopInset,
                    editorBottomInset: Self.editorBottomInset,
                    onSubmit: onSubmit ?? model.translate,
                    onEditorHeight: { height in
                        let clamped = min(max(height, boxFloor), Self.maxBoxHeight)
                        guard clamped != inputHeight else { return }
                        // The whole stack moves with the box: the header stays
                        // put, the footer travels, and the box's top never dips.
                        withAnimation(DroppyAnimation.state) {
                            inputHeight = clamped
                        }
                    },
                    showsInlineTools: false,
                    bodyFontSize: Self.bodyFontSize,
                    maxEditorHeight: keepsGripInsideCard && !showsResult
                        ? closedInputHeight
                        : Self.maxBoxHeight,
                    scrollerCap: keepsGripInsideCard && !showsResult
                        ? closedInputHeight
                        : Self.maxBoxHeight,
                    hoverChrome: true,
                    // Folded, the tile's frame is the input's old height while
                    // the result covers it; marking it would draw a wash over
                    // the result at a box that is no longer there.
                    chipTarget: inputFold == 0 && displayedBoxHeight > 0 ? .input : nil,
                    pocketCut: glassTiles ? Self.inputCut : nil
                )
                // The box follows new lines with the card; the state change carries
                // its own animation, so the footer travels with it. In step 3 it is
                // a shrinking top slice: the result climbs over it, so the text is
                // never squashed, only covered.
                .frame(height: inputTileHeight, alignment: .top)
                .frame(height: displayedBoxHeight, alignment: .top)
                .clipped()
                // Inside the box, not the footer: they belong to the text they act
                // on. The panel chip marks each one, so the disc keeps only its
                // resting glass. Folded, the tools go with the box: a 0pt overlay
                // would otherwise sit them on the language row.
                .overlay(alignment: .bottomTrailing) {
                    if inputFold == 0 && displayedBoxHeight > 0 {
                        HStack(spacing: 6) {
                            if !(model.input.isEmpty && model.output.isEmpty) {
                                SidePanelBoxButton(symbol: "trash", a11yKey: "a11y.clear", target: .clear) {
                                    model.clearInput()
                                }
                                .transition(.opacity)
                            }
                            // The paste control names itself: an icon alone reads as a tool,
                            // and the word is what the user came to press.
                            SidePanelPillButton(
                                symbol: "clipboard.fill",
                                title: L10n.tr("a11y.paste"),
                                a11yKey: "a11y.paste",
                                target: .paste
                            ) {
                                model.pasteInput()
                            }
                            .disabled(!model.canPaste)
                        }
                        .padding(.trailing, DroppySpacing.sm)
                        .padding(.bottom, DroppySpacing.sm)
                        .animation(DroppyAnimation.state, value: [model.input.isEmpty, model.output.isEmpty])
                    }
                }
                .allowsHitTesting(inputFold == 0 && displayedBoxHeight > 0)
                // A grip drag mounts the box before the result arrives, so the
                // drag pulls the empty sheet out of the input instead of waiting
                // for the status and then dropping the whole box in.
                if displaysResult || resultOnScreen {
                    resultBox
                        // A stowed box keeps its place in the stack but not its
                        // seam, so the footer sits where a bare input puts it.
                        // A held drag mounts the box at zero height; the gap
                        // mounts only once the pull shows it, matching the
                        // window body's math.
                        .padding(
                            .top,
                            resultOnScreen && visibleResultHeight > 0
                                ? (shelfHeaderRise > 0 ? 0 : Self.resultGap - fullCardRise)
                                : 0
                        )
                }
            }
            .padding(
                .top,
                -(Self.discRadius - Self.rowGap) - Self.resultGap * inputFold
                    - shelfHeaderRise
            )
            // The drop grows out of the input and pushes the footer down with
            // it; the extra height below is only visible while it stretches.
            footer
                .zIndex(2)
            Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(alignment: .bottom) {
                gripHandle
            }

            chipLayer
        }
        // The card is the sheet in front: nothing it holds may draw past its
        // own face, even on the frame where the window is still catching up
        // with a body that just changed size.
        .clipped()
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
                // Only a change of control republishes, so moving inside one
                // control does not redraw the panel. Step 3 fades the language
                // row out; its stale frames must not draw it back under the
                // chip.
                let target = Self.target(
                    at: point,
                    frames: chip.frames,
                    marksHeader: headerOpacity > 0
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
            // Folded away, the input's height has no say in the card.
            guard inputFold == 0 else { return }
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
        .onChange(of: displaysResult) { _, shown in
            if gripDrag != nil {
                // The drag owns the height until the pointer lifts; the box
                // stays where the fingers pulled it.
                reportGrip()
                return
            }
            if !shown, inputFold > 0 {
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
        }
        .onAppear {
            resultReveal = showsResult ? 1 : 0
            onBodyHeight(
                Self.bodyHeight(forBox: inputHeight, result: showsResult, resultHeight: resultHeight),
                false
            )
        }
    }

    private var showsResult: Bool {
        Self.showsResult(for: model)
    }

    /// The shelf's first step is the bare input, as the panel opens; the
    /// result joins it from the second step. A notice still shows at the
    /// first step, so an error is never hidden behind a tap. The panel shows
    /// the result whenever it has one. While the card collapses, the result
    /// stays mounted and shrinks with the height, so it leaves the stack only
    /// when the input has taken the whole room.
    private var displaysResult: Bool {
        guard keepsGripInsideCard else { return showsResult }
        if model.notice != nil { return true }
        if shelfStep > 0 { return showsResult }
        return showsResult && shelfGrowth > 0
    }

    /// The result box is on screen: a grip is holding it, or a pull has
    /// revealed it. A stowed status keeps its state but not its seam.
    private var resultOnScreen: Bool {
        if keepsGripInsideCard { return displaysResult && resultReveal > 0 }
        return gripDrag != nil || resultReveal > 0
    }

    /// The part of the result box on screen right now: the pull while the grip
    /// is held, the settled box when it is open, nothing when it is closed.
    private var visibleResultHeight: CGFloat {
        if let gripDrag { return gripDrag.pulled }
        guard displaysResult else { return 0 }
        return displayedResultHeight * resultReveal
    }

    /// The result height the current mount draws. The shelf derives it from
    /// its card step; the panel's grip writes it.
    private var displayedResultHeight: CGFloat {
        keepsGripInsideCard ? shelfResultHeight : resultHeight
    }

    /// The input's height on screen: step 3 folds it away a slice at a time
    /// while the result takes the space. The shelf's steps trade the input
    /// for the result and give it back as the card grows.
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
    /// actually hands over, minus the footer and, until step three, the
    /// language row.
    private var shelfRoom: CGFloat {
        let header = shelfStep == 2 ? 0 : pillHeight + Self.rowGap
        return max(0, maxBodyHeight - (header + Self.footerHeight))
    }

    /// The input at the current step: the whole room while the result is out
    /// of the picture, a short box beside the result, and nothing when the
    /// result has the card to itself. Between steps one and two the box
    /// follows the card's real growth, so the result grows out of it instead
    /// of switching layouts. A notice at the first step takes the input's
    /// place instead of hiding behind a taller card.
    private var shelfInputHeight: CGFloat {
        guard keepsGripInsideCard else { return inputHeight }
        guard displaysResult else { return max(inputHeight, shelfRoom) }
        if model.notice != nil, shelfStep == 0 { return 0 }
        if shelfStep == 2 { return 0 }
        let shortBox = min(inputHeight, Self.minBoxHeight)
        return shelfRoom - (shelfRoom - shortBox) * shelfGrowth
    }

    /// The result takes whatever the input leaves, so the two always fill the
    /// card at the step the host gave them.
    private var shelfResultHeight: CGFloat {
        guard keepsGripInsideCard, displaysResult else { return 0 }
        let input = shelfInputHeight
        return max(0, shelfRoom - input - (input > 0 ? Self.resultGap : 0))
    }

    /// The height the shelf's input fills when no result is on screen: what
    /// the fixed card leaves after the header and the footer.
    private var closedInputHeight: CGFloat {
        max(inputHeight, shelfRoom)
    }

    /// How far the result climbs past the language row at the end of step 3,
    /// measured from the seam it rests on: at full fold its top is the card's.
    private var fullCardRise: CGFloat {
        (pillHeight + Self.rowGap) * inputFold
    }

    /// The disc's centre from the result box's top while the box sits under it.
    private var resultPocketCentreY: CGFloat {
        -Self.resultGap - Self.rowGap - displayedBoxHeight
            + Self.resultGap * inputFold + fullCardRise
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

    /// The result box on screen. Its glass takes the height the pull has
    /// revealed, so the box stretches with the drag and its own rounded rim is
    /// the moving edge. The words keep their full layout inside and are clipped
    /// to that rim, so a pull never squeezes them; while the grip is held a
    /// blurred copy shows through near the rim, so a word comes into focus as
    /// it crosses the edge. Past the fold the result climbs to the card's top
    /// and the language row gives way.
    private var resultBox: some View {
        let tile = PanelResultTile(
            model: model,
            isDragging: gripDrag != nil,
            reveal: resultReveal
        )
            // The fold gives the result the gap it ate at the seam, so its
            // bottom keeps the footer's air instead of riding up with it.
            .frame(height: displayedResultHeight + fullCardRise + Self.resultGap * inputFold)
            .frame(
                height: displayedResultHeight * resultReveal + fullCardRise
                    + Self.resultGap * inputFold,
                alignment: .top
            )
            .clipped()
        return ZStack(alignment: .top) {
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
        .clipShape(RoundedRectangle(cornerRadius: 29, style: .continuous))
        .background {
            let shape = RoundedRectangle(cornerRadius: 29, style: .continuous)
            if glassTiles {
                if resultOnScreen {
                    Color.clear
                        .droppyGlassControlChrome(shape: AnyShape(shape))
                        .sidePanelTileBevel(shape: AnyShape(shape))
                        .mask {
                            GlassPocketMask(
                                shape: AnyShape(shape),
                                centreY: resultPocketCentreY,
                                radius: Self.discRadius,
                                topFillet: Self.seamFillet,
                                erase: headerOpacity
                            )
                        }
                } else {
                    Color.clear
                        .droppyGlassControlChrome(shape: AnyShape(shape))
                        .sidePanelTileBevel(shape: AnyShape(shape))
                }
            } else {
                shape.fill(AdaptiveColors.notchSurfaceCardFill)
            }
        }
        // The mark covers what is on screen, not the whole box: the rest is
        // under the card's edge, so a full-height frame would let the chip's
        // glass hang outside it. A stowed box marks nothing, or the mark draws
        // the box back on screen above its own clip.
        .chipTarget(resultReveal >= 1 ? .result : nil)
    }

    /// The language row stays usable until the result is about to reach it,
    /// then clears out of its way. The shelf's last step gives the row to the
    /// result outright.
    private var headerOpacity: Double {
        if keepsGripInsideCard, shelfStep == 2 { return 0 }
        let fade = min(max((inputFold - 0.7) / 0.3, 0), 1)
        return Double(1 - fade)
    }

    /// How far the shelf's last step pulls the boxes over the language row.
    private var shelfHeaderRise: CGFloat {
        keepsGripInsideCard && shelfStep == 2 ? pillHeight + Self.rowGap : 0
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
    /// The shelf's bar keeps a little air under it, so it has room to travel
    /// down while the pointer holds it, the way the card can only move in
    /// whole steps.
    static let shelfGripLift: CGFloat = 12
    /// How far the pointer may pull the shelf's bar from its rest position.
    static let shelfGripPullRange: ClosedRange<CGFloat> = -24...12
    static let gripHitSize = CGSize(width: gripWidth, height: gripStrip)

    /// The visible result height a drag of `translation` asks for, measured
    /// from `start`. `deadband` is the signed slop removed from the movement.
    /// A negative result is the pull past a fully folded box, where the clear
    /// action arms. `full` lets the result grow by the input's own height, so
    /// step 3 trades the two boxes and keeps the card the size it was; without
    /// a result to read, the pull stops at the resting box, so a status never
    /// stretches the card.
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
            : SidePanelContentView.resultBoxHeight
        let cap = max(start, ceiling)
        return min(start + translation - deadband, cap)
    }

    /// How much of the input the pointer has folded into the result: 0 until
    /// the pull passes the seam, 1 when the result has taken the input's
    /// height. The seam is fixed when the drag starts, so a box that is
    /// already folded unfolds from the same place.
    static func inputFold(
        pulled: CGFloat,
        box: CGFloat,
        full: Bool,
        foldStart: CGFloat = SidePanelContentView.resultBoxHeight
    ) -> CGFloat {
        guard full, box > 0 else { return 0 }
        return min(max(pulled - foldStart, 0) / box, 1)
    }

    /// The end of step 2 is the start button: a pull that reaches the resting
    /// box's height asks for the translation, the same as Return. A box that
    /// already reads is only being resized, and a run in flight is not
    /// restarted under the pointer.
    static func startsTranslation(
        pulled: CGFloat,
        hasInput: Bool,
        hasOutput: Bool,
        isTranslating: Bool
    ) -> Bool {
        pulled >= resultBoxHeight && hasInput && !hasOutput && !isTranslating
    }

    /// Pulls the result box `pulled` points out of the input; a negative pull
    /// folds it away. The box keeps at least its resting height, so its text
    /// never squeezes; only the slice on screen follows the pointer. Past the
    /// seam the input folds into the result with the pointer, so the result
    /// climbs to the card's top while the card keeps its height.
    private func applyGrip(_ pulled: CGFloat, full: Bool, foldStart: CGFloat) {
        let visible = max(pulled, 0)
        let height = max(visible, Self.resultBoxHeight)
        let reveal = height > 0 ? min(1, visible / height) : 0
        let fold = Self.inputFold(
            pulled: pulled,
            box: inputHeight,
            full: full,
            foldStart: foldStart
        )
        if abs(resultHeight - height) > 0.5 { resultHeight = height }
        if abs(resultReveal - reveal) > 0.001 { resultReveal = reveal }
        if abs(inputFold - fold) > 0.001 { inputFold = fold }
        reportGrip()
    }

    /// The window body carries only the part of the result the drag has pulled
    /// out, so the card edge stays under the pointer instead of dropping the
    /// whole box in when the translation starts. Once the input folds, the two
    /// heights trade places and the card stays at its tallest.
    private func reportGrip() {
        guard let drag = gripDrag else { return }
        let visible = max(drag.pulled, 0)
        let height = max(visible, Self.resultBoxHeight)
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

    /// Lets go: a result springs the box open, a status stows when the pull is
    /// closer to closed, and an empty box folds back into the input. Step 3
    /// settles on whichever side of the fold the pointer was closer to.
    private func settleGrip(_ drag: GripDrag) {
        let stows = !showsResult
            || (model.output.isEmpty && drag.pulled < Self.resultBoxHeight / 2)
        if stows {
            stowResultBox()
            return
        }
        let fullCard = drag.hasResult && drag.pulled > drag.foldStart + inputHeight / 2
        let height = fullCard
            ? drag.foldStart + inputHeight
            : max(Self.resultBoxHeight, min(drag.pulled, drag.foldStart))
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
            resultHeight = Self.resultBoxHeight
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

    /// The tallest the result box may get with `box` above it: whatever keeps
    /// the whole card inside the height the window already reserves.
    static func maxResultHeight(forBox box: CGFloat) -> CGFloat {
        maxPanelBodyHeight - bodyHeight(forBox: box) - resultGap
    }

    /// The control the pointer is on. The first pass takes the exact frames;
    /// the second lets a frame reach 4pt into the gap beside it, so the chip
    /// never blinks off while the pointer crosses the air between two
    /// controls. The gaps between controls are 8pt, so the reaches meet.
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

    /// The panel's sliding effect: one piece of glass that marks the control
    /// under the pointer, wherever it sits in the panel.
    private var chipLayer: some View {
        ZStack(alignment: .topLeading) {
            boxWash
            chipGlass
            chipInk
            moreGlyph
            engineLabel
        }
        .allowsHitTesting(false)
        // One clock for the whole mark: the glass travels, the ink it leaves
        // fades out above the control and the ink it reaches fades in, so no
        // label jumps to the destination before the glass lands there.
        .animation(DroppyAnimation.tabSelect, value: chip.target)
    }

    /// The pocket the swap disc cuts out of the input box. The chip's wash uses
    /// the same numbers, so the mark is the box and not a capsule over it.
    static var inputCut: SidePanelBoxCut {
        SidePanelBoxCut(centreY: -rowGap, radius: discRadius, fillet: seamFillet, corner: 28)
    }

    /// The mark under the pointer, lit in its own silhouette. Glass cannot take
    /// a shape with a hole, so a box takes the wash the kit's glass carries; a
    /// menu row takes it too, because it already sits on the menu's glass. The
    /// wash shares the glass's frame, so a move to or from one travels the same
    /// path as any other control; only the material changes.
    @ViewBuilder
    private var boxWash: some View {
        if let rect = markedRect {
            // The kit's hover wash is 0.06, which disappears on this black card.
            // 0.14 reads as the same lift the glass controls take.
            washShape
                .fill(AdaptiveColors.overlayAuto(0.14))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .opacity(marksWash ? 1 : 0)
                .animation(DroppyAnimation.tabSelect, value: rect)
                .animation(DroppyAnimation.state, value: marksWash)
        }
    }

    /// The silhouette the wash takes: a box keeps its disc pocket, a menu row
    /// follows the menu's own corners.
    private var washShape: AnyShape {
        switch chip.target ?? chip.lastTarget {
        case .input:
            return AnyShape(SidePanelBoxChipShape(cut: Self.inputCut))
        case .result:
            if headerOpacity > 0 {
                return AnyShape(
                    SidePanelBoxChipShape(
                        cut: SidePanelBoxCut(
                            centreY: resultPocketCentreY,
                            radius: Self.discRadius,
                            fillet: Self.seamFillet,
                            corner: 29
                        )
                    )
                )
            }
            return AnyShape(RoundedRectangle(cornerRadius: 29, style: .continuous))
        case .menuCapture, .menuSelect, .menuPin, .menuSettings:
            return AnyShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        default:
            return AnyShape(RoundedRectangle(cornerRadius: 29, style: .continuous))
        }
    }

    /// The engine capsule's ink is drawn here while the chip covers the
    /// capsule, above the chip's own glass. At rest the control draws it, so
    /// the word survives even when the chip has no frame to place it.
    @ViewBuilder
    private var engineLabel: some View {
        if let frame = chip.frames[.engine] {
            PanelEngineLabel(model: model)
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
                .opacity(chip.covers(.engine) ? 1 : 0)
                .animation(DroppyAnimation.state, value: chip.target)
        }
    }

    /// The more disc's dots live here while the chip covers it, above the
    /// chip's own glass.
    @ViewBuilder
    private var moreGlyph: some View {
        if let frame = chip.frames[.more] {
            PanelMoreGlyph(
                iconFont: 12,
                rotation: model.isToolbarExpanded ? 90 : 0
            )
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
                .opacity(chip.covers(.more) ? 1 : 0)
                .animation(DroppyAnimation.state, value: chip.target)
                .animation(DroppyAnimation.state, value: model.isToolbarExpanded)
        }
    }

    /// Where the mark sits: the control under the pointer, or the one it last
    /// covered. Both materials ride this frame, so every move is a slide.
    private var markedRect: CGRect? {
        chip.rect(resting: nil)
    }

    /// True when the mark rests on a control that takes the wash instead of
    /// glass: a box, or a row of the more menu.
    private var marksWash: Bool {
        chip.marksWithWash(chip.target)
    }

    /// The glass over the marked control. It takes that control's silhouette
    /// and keeps its frame; the ink carries the hover and press. A wash control
    /// hides it, but it still travels with the mark on its way there, so the
    /// hand-off reads as one piece of glass changing material, not two marks
    /// blinking.
    @ViewBuilder
    private var chipGlass: some View {
        if let rect = markedRect {
            let destination = chip.target.flatMap { chip.frames[$0] } ?? rect
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .droppyGlassControlChrome(
                    shape: AnyShape(
                        LiquidChipShape(
                            rect: rect,
                            destination: CGPoint(x: destination.midX, y: destination.midY)
                        )
                    ),
                    isHovering: true
                )
                .opacity(chip.target == nil || marksWash ? 0 : 1)
                .animation(DroppyAnimation.tabSelect, value: rect)
                .animation(DroppyAnimation.state, value: marksWash)
                .animation(DroppyAnimation.state, value: chip.target == nil)
        }
    }

    /// The marked control's ink, drawn above the glass so the glass never sits
    /// over the glyph.
    @ViewBuilder
    private var chipInk: some View {
        if let target = chip.target, let frame = chip.frames[target] {
            PanelChipInk(scale: chip.inkScale) {
                markedInk(for: target)
                    .frame(width: frame.width, height: frame.height)
            }
            .offset(x: frame.minX, y: frame.minY)
            // A new mark is a new copy: the old ink fades where it stood while
            // the new one grows at its control, so the glyphs never swap before
            // the glass has travelled.
            .id(target)
            .transition(.opacity)
        }
    }

    /// The ink each marked control draws for itself. The control hides its
    /// own copy while the chip covers it, so only one of them is ever seen.
    @ViewBuilder
    private func markedInk(for target: SidePanelChipTarget) -> some View {
        switch target {
        case .source:
            PillLanguageLabel(
                text: sourceLabel(for: model),
                highlighted: true,
                fontSize: Self.bodyFontSize,
                alignment: .center,
                edgeInset: Self.pillEdgeInset
            )
        case .target:
            PillLanguageLabel(
                text: model.name(for: model.targetID),
                highlighted: true,
                fontSize: Self.bodyFontSize,
                alignment: .center,
                edgeInset: Self.pillEdgeInset
            )
        case .swap:
            SidePanelSwapGlyph(spins: model.swapSpins, enabled: model.canSwap)
        case .download:
            PanelDownloadLabel()
        case .copy:
            SidePanelPillLabel(
                symbol: model.copied ? "checkmark" : "document.on.document",
                text: L10n.tr("copy")
            )
        case .paste:
            SidePanelPillLabel(symbol: "clipboard.fill", text: L10n.tr("a11y.paste"))
        case .clear:
            SidePanelDiscGlyph(symbol: "trash")
        case .more, .engine, .input, .result,
             .menuCapture, .menuSelect, .menuPin, .menuSettings:
            EmptyView()
        }
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
        // The more disc keeps the boxes' leading edge, bottom left; the engine
        // picker sits on the trailing edge, where the menu rows cannot reach it.
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
            Spacer(minLength: 0)
            PanelEngineMenu(
                model: model,
                showsCaption: rowWidth >= Self.defaultRowWidth
            )
        }
        .frame(height: Self.footerHeight, alignment: .bottom)
        .overlay(alignment: .bottomLeading) {
            if model.isToolbarExpanded {
                // The rows start on the footer's top edge, so the disc stays
                // in sight under them and turns its dots upright.
                PanelMoreMenu(
                    model: model,
                    requestCapture: requestCapture,
                    requestSelection: requestSelection,
                    cancelSelection: cancelSelection,
                    onHover: { moreHover($0, inMenu: true) },
                    pinned: onPin == nil ? nil : pin.isPinned,
                    onPin: onPin
                )
                .offset(y: -Self.footerHeight)
                .transition(.scale(scale: 0.96, anchor: .bottomLeading).combined(with: .opacity))
            }
        }
    }

    /// The drag handle. The panel's is the collapsed tab's silhouette laid on
    /// its side and filled with the card's own black, so it hangs off the
    /// card's bottom edge as one piece; the shelf's card cannot grow, so it
    /// keeps only the bar inside the card.
    @ViewBuilder
    private var gripHandle: some View {
        if keepsGripInsideCard {
            shelfGrip
        } else {
            interactiveGrip
        }
    }

    /// The shelf's handle: the same resting bar. A tap translates the text on
    /// the opening card; a drag up or down pulls the bar with the pointer and
    /// picks the card's height when it lets go: down grows, up shrinks.
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
                .offset(y: shelfGripPull)
        }
        .contentShape(Rectangle())
        .onHover { gripHover = $0 }
        .onTapGesture { onShelfGripTap?() }
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { value in
                    // The bar follows the pointer, so the handle answers the
                    // hand before the card can move; the card only has whole
                    // steps to give.
                    shelfGripPull = min(
                        max(value.translation.height, Self.shelfGripPullRange.lowerBound),
                        Self.shelfGripPullRange.upperBound
                    )
                }
                .onEnded { value in
                    let dy = value.translation.height
                    withAnimation(DroppyAnimation.notchOpen) { shelfGripPull = 0 }
                    guard abs(dy) > abs(value.translation.width), abs(dy) >= 10 else { return }
                    onShelfGripDrag?(dy < 0 ? .up : .down)
                }
        )
        .animation(DroppyAnimation.hover, value: out)
        .accessibilityElement()
        .accessibilityLabel(L10n.tr(shelfStep == 0 ? "a11y.translate" : "a11y.shelfGrip"))
        .accessibilityHint(
            L10n.tr(shelfStep == 0 ? "a11y.shelfGripTranslateHint" : "a11y.shelfGripHint")
        )
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onShelfGripDrag?(.down)
            case .decrement: onShelfGripDrag?(.up)
            @unknown default: break
            }
        }
        .help(L10n.tr(shelfStep == 0 ? "a11y.translate" : "a11y.shelfGrip"))
    }

    private var interactiveGrip: some View {
        let out = gripOut
        return ZStack(alignment: .bottom) {
            ZStack {
                // The handle itself is part of the card's own outline now: the
                // panel grows that shape, so the glass covers the card and the
                // lobe in one layer. Only the mark on it is drawn here, and it
                // rides the same amount, so it stays on the lobe.
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

    /// A downward drag pulls the result box out of the input, stretches it to
    /// the card's cap and then folds the input away, so the result takes the
    /// whole face. An upward drag reverses that, and 24pt past the fold clears
    /// the text. A click does nothing.
    private var gripGesture: some Gesture {
        // Global, not local: the tab moves down with the card it grows, so a
        // local translation would cancel the pointer's movement and stall.
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                let start = visibleResultHeight
                var drag = gripDrag ?? GripDrag(
                    startHeight: start,
                    foldStart: max(start - inputHeight * inputFold, Self.resultBoxHeight),
                    pulled: start,
                    deadband: 0,
                    hasResult: !model.output.isEmpty
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
                // The end of step 2 is also the start button: a pull that
                // fills the resting box translates, so one gesture opens the
                // box and asks for its text. A box that already reads is only
                // being resized.
                if !drag.translateStarted,
                   Self.startsTranslation(
                       pulled: drag.pulled,
                       hasInput: model.canTranslate,
                       hasOutput: !model.output.isEmpty,
                       isTranslating: model.status == .translating
                   ) {
                    drag.translateStarted = true
                    model.translate()
                }
                gripDrag = drag
                applyGrip(drag.pulled, full: drag.hasResult, foldStart: drag.foldStart)
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
        headerRow
            .frame(maxWidth: .infinity)
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

    /// The row capsule with the swap pocket cut through its glass, the disc,
    /// the disc's glyph and then both menus. The chip that marks them lives in
    /// the panel's own layer, above everything, so the glyph is drawn again
    /// there while the chip covers it.
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

            swapGlyph
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
                // The mark keeps 3pt of rim inside the capsule's end and runs
                // to the pocket's tangent, where the pocket's own curve leaves
                // the same 3. It is the label's box, so the chip's ink lands
                // on the label instead of 1.5pt off it.
                .chipTarget(
                    .source,
                    insets: EdgeInsets(top: Self.rowMarkInset, leading: 0, bottom: Self.rowMarkInset, trailing: 0)
                )
                .padding(.leading, PanelFooterMetrics.chipInset)
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
                .chipTarget(
                    .target,
                    insets: EdgeInsets(top: Self.rowMarkInset, leading: 0, bottom: Self.rowMarkInset, trailing: 0)
                )
                .padding(.trailing, PanelFooterMetrics.chipInset)
                .frame(width: halfWidth)
            }
            .frame(width: rowWidth, height: pillHeight)
        }
        .frame(width: rowWidth, height: pillHeight + Self.discRadius, alignment: .topLeading)
    }

    /// The disc's glass and hit area. The glyph is separate so the chip can
    /// draw it above its own glass. The glass stays put under the chip: hiding
    /// it while the chip slides in leaves the disc empty for a frame, which
    /// reads as a blink on the way to the seam.
    private var swapButton: some View {
        Button {
            model.swapLanguages()
        } label: {
            Color.clear
                .frame(width: Self.buttonDiameter, height: Self.buttonDiameter)
                .contentShape(Circle())
        }
        .buttonStyle(
            PanelPressStyle(
                hoverScale: SidePanelChipState.hoverScale,
                pressScale: SidePanelChipState.pressScale
            )
        )
        .background {
            Color.clear
                .droppyGlassControlChrome(shape: AnyShape(Circle()))
        }
        .chipTarget(.swap)
        .arrowCursorRegion()
        .a11y("a11y.swap")
        .disabled(!model.canSwap)
    }

    private var swapGlyph: some View {
        SidePanelSwapGlyph(spins: model.swapSpins, enabled: model.canSwap)
            .chipHidesInk(chip.covers(.swap))
            .allowsHitTesting(false)
    }
}

/// The swap disc's glyph. It is drawn apart from the disc's glass, so the
/// chip can put it above the chip's own glass.
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
    @Environment(\.sidePanelChip) private var chip

    /// The block clears the edge's blur band at about three quarters open;
    /// below that it blurs in proportion to how closed the box is.
    private static let statusClearReveal: CGFloat = 0.75
    private static let statusBlurRamp: CGFloat = 0.15
    /// The soft band at each rim, the input box's 10% at its resting height.
    private static let edgeFadeBand: CGFloat = 16

    private var statusBlur: CGFloat {
        let closed = (Self.statusClearReveal - reveal) / Self.statusBlurRamp
        return SidePanelContentView.resultEdgeBlur * min(max(closed, 0), 1)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                if !model.output.isEmpty {
                    TranslationOutputScrollView(
                        text: model.output,
                        resetToken: model.outputScrollResetToken.uuidString,
                        scrollerTopInset: 23,
                        scrollerBottomInset: 48,
                        textInset: 23,
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
                                    .chipHidesInk(chip?.covers(.download) == true)
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
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .contentShape(Capsule(style: .continuous))
                            }
                            .buttonStyle(
                                PanelPressStyle(
                                    hoverScale: SidePanelChipState.hoverScale,
                                    pressScale: SidePanelChipState.pressScale
                                )
                            )
                            .background {
                                Color.clear
                                    .droppyGlassControlChrome(
                                        shape: AnyShape(Capsule(style: .continuous))
                                    )
                            }
                            .arrowCursorRegion()
                            .a11y("a11y.retry")
                        }
                    }
                    // Centred in the resting box, then pinned to the tile's top:
                    // a drag grows the box downward, so the stack must not ride
                    // the new height and read as a slide.
                    .frame(
                        width: nil,
                        height: SidePanelContentView.resultBoxHeight,
                        alignment: .center
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .blur(radius: statusBlur)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, DroppySpacing.sm)
            .padding(.trailing, DroppySpacing.sm)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The rim the input box already keeps: words fade as they reach the
        // glass instead of ending on a hard line. The input's share of its own
        // height, capped: step 3's box is twice as tall, and a plain share
        // would dim the first line.
        .mask {
            GeometryReader { geometry in
                let band = min(Self.edgeFadeBand, geometry.size.height * 0.1)
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: band)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: band)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !model.output.isEmpty {
                SidePanelPillButton(
                    symbol: model.copied ? "checkmark" : "document.on.document",
                    title: L10n.tr("copy"),
                    a11yKey: "a11y.copy",
                    target: .copy
                ) {
                    model.copyOutput()
                }
                .padding(.trailing, DroppySpacing.sm)
                .padding(.bottom, DroppySpacing.sm)
            }
        }
        .animation(isDragging ? nil : DroppyAnimation.state, value: model.output.isEmpty)
    }
}

/// A named control inside a box: the glyph and the word, so it reads as an
/// action rather than as another disc. The chip marks the pill and redraws
/// this label above its glass.
private struct SidePanelPillButton: View {
    var symbol: String
    var title: String
    var a11yKey: String
    var target: SidePanelChipTarget
    var action: () -> Void

    /// Matches the 28pt discs beside it: the kit's small pill pads its 12pt
    /// label by 8pt top and bottom, which stands taller than the clear disc.
    /// The glass is the same material; only the frame is this row's.
    static let height: CGFloat = 28

    @Environment(\.sidePanelChip) private var chip

    var body: some View {
        Button(action: action) {
            SidePanelPillLabel(symbol: symbol, text: title)
                .chipHidesInk(chip?.covers(target) == true)
                .padding(.horizontal, 9)
                .frame(height: Self.height)
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(
            PanelPressStyle(
                hoverScale: SidePanelChipState.hoverScale,
                pressScale: SidePanelChipState.pressScale
            )
        )
        .background {
            Color.clear
                .droppyGlassControlChrome(shape: AnyShape(Capsule(style: .continuous)))
        }
        .chipTarget(target)
        .arrowCursorRegion()
        .a11y(a11yKey)
    }
}

/// The pill's ink, shared by the button and the chip.
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

/// A disc inside a box. It keeps its own glass under the chip, which marks it
/// like any other control, and hides its glyph while the chip draws that glyph
/// above the mark.
private struct SidePanelBoxButton: View {
    var symbol: String
    var a11yKey: String
    var target: SidePanelChipTarget
    var action: () -> Void

    /// The disc's diameter; the chip's glyph copies its font from it.
    static let diameter: CGFloat = 28

    @Environment(\.sidePanelChip) private var chip

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .chipHidesInk(chip?.covers(target) == true)
        }
        .buttonStyle(DroppyCircleButtonStyle(size: Self.diameter))
        .chipTarget(target)
        .arrowCursorRegion()
        .a11y(a11yKey)
    }
}

/// A disc's glyph, drawn again above the chip's glass. The kit's disc style
/// sizes its glyph at 0.4 of the diameter in bold, so the copy matches.
private struct SidePanelDiscGlyph: View {
    var symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: SidePanelBoxButton.diameter * 0.4, weight: .bold))
            .foregroundStyle(AdaptiveColors.primaryTextAuto.opacity(0.92))
    }
}

/// The download pill's label. The chip draws this same view above its own
/// glass, so the words never shift. The size is the kit's small pill.
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
    /// A grouped shelf slot keeps only the engine capsule; the caption would
    /// crowd the footer.
    var showsCaption = true
    @Environment(\.sidePanelChip) private var chip

    var body: some View {
        HStack(spacing: DroppySpacing.xs) {
            if showsCaption {
                Image(systemName: "translate")
                    .font(.system(size: 12, weight: .medium))
                Text(L10n.tr("panel.translateWith"))
                    .font(.system(size: 12))
                    .cardTextShadow()
            }
            capsule
        }
        .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
    }

    /// The capsule holds only the engine in use, so it stays small next to
    /// the caption; the chip marks this part alone.
    private var capsule: some View {
        Menu {
            ForEach(TranslationEngine.allCases) { engine in
                Toggle(isOn: selected(engine)) {
                    Text(label(for: engine))
                }
            }
        } label: {
            PanelEngineLabel(model: model)
                // The chip redraws this label above its own glass, so the two
                // copies cross-fade instead of swapping.
                .chipHidesInk(chip?.covers(.engine) ?? false)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .contentShape(Capsule(style: .continuous))
        }
        .menuIndicator(.hidden)
        .buttonStyle(
            PanelPressStyle(
                hoverScale: SidePanelChipState.hoverScale,
                pressScale: SidePanelChipState.pressScale
            )
        )
        // The glass sits outside the button's style, so the chip can draw the
        // same ink above a glass that never moves with the pointer.
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

/// The engine capsule's ink. The chip draws this same view above its own
/// glass, so the text never shifts by the menu's inset.
struct PanelEngineLabel: View {
    @ObservedObject var model: TranslateModel

    var body: some View {
        Text(Self.name(for: model))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(AdaptiveColors.primaryTextAuto.opacity(0.92))
            .cardTextShadow()
            .lineLimit(1)
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

/// A disc cut into a surface, its mouths filleted so the surface's straight
/// edges ease into the disc instead of meeting it at a point.
///
/// `centreY` is the disc's centre from the rect's top edge. A disc that crosses
/// both edges cuts a band; one that clears an edge leaves a pocket there.
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

/// Every panel button lifts a little under the pointer, dips on press, and
/// returns to the lift while the pointer stays.
struct PanelPressStyle: ButtonStyle {
    var hoverScale: CGFloat = 1.1
    /// The scale while the button is held. The chip's ink dips with it; the
    /// mark keeps its frame.
    var pressScale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        PanelPressBody(
            configuration: configuration,
            hoverScale: hoverScale,
            pressScale: pressScale
        )
    }
}

private struct PanelPressBody: View {
    let configuration: ButtonStyleConfiguration
    let hoverScale: CGFloat
    let pressScale: CGFloat
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .scaleEffect(
                configuration.isPressed ? pressScale : (hovering && isEnabled ? hoverScale : 1)
            )
            .animation(DroppyAnimation.hoverQuick, value: configuration.isPressed)
            .animation(DroppyAnimation.hoverQuick, value: hovering)
            .onHover { hovering = $0 }
    }
}

/// The chip's copy of a marked control's ink. It grows from rest when the mark
/// arrives, so a marked button expands like a menu row instead of appearing
/// already lifted.
/// The ink above the chip's glass, lifted under the pointer and dipped while
/// the control is held.
struct PanelChipInk<Content: View>: View {
    var scale: CGFloat
    let content: Content
    @State private var appeared = false

    init(scale: CGFloat, @ViewBuilder content: () -> Content) {
        self.scale = scale
        self.content = content()
    }

    var body: some View {
        content
            .scaleEffect(appeared ? scale : 1)
            .animation(DroppyAnimation.hoverQuick, value: scale)
            .onAppear {
                withAnimation(DroppyAnimation.hoverQuick) { appeared = true }
            }
    }
}
