import AppKit
import DroppyKit
import QuartzCore
import SwiftUI

/// The droplet's result window, floating beside a capture.
/// `SidePanelCardSurface` draws the app's themed card and
/// `DroppyPanelActivation` takes focus for it.
@MainActor
final class TranslationPanel: NSPanel {
    static let shared = TranslationPanel()

    private var hosting: NSHostingView<AnyView>?
    private var monitor: Any?
    private var activation: DroppyPanelActivation?
    private var fallbackReturn: NSRunningApplication?
    private var keyTask: Task<Void, Never>?
    private var interactive = false
    private var pinned = false
    private var requestCapture: () -> Void = {}
    private var requestSelection: () -> Void = {}
    private var cancelSelection: () -> Void = {}
    /// The panel's open and fold, stepped by a display link on the edge
    /// panel's bloom curve.
    private var bloomLink: CADisplayLink?
    private var bloomReveal: CGFloat = 1
    /// Where the bloom is on the shared curve; the fold runs it backwards.
    private var bloomPhase: CGFloat = 1
    /// The card at rest, and the point on the screen it blooms out of.
    private var bloomCard = NSRect.zero
    private var bloomPoint = CGPoint.zero
    private var bloomClosing = false
    private var lastBloomTick = CACurrentMediaTime()
    /// The dot the card grows out of; a panel with no capture grows from the
    /// pointer.
    static let bloomDot: CGFloat = 36

    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    // `DroppyPanelActivation` makes the panel key and main at once, and AppKit
    // throws when asked to make a borderless window main.
    override var canBecomeMain: Bool { true }

    // MARK: - Entry points

    /// The actions the more menu offers. The droplet owns capture and
    /// selection, so it hands them over once, as it does for the edge panel.
    func configure(
        requestCapture: @escaping () -> Void,
        requestSelection: @escaping () -> Void,
        cancelSelection: @escaping () -> Void
    ) {
        self.requestCapture = requestCapture
        self.requestSelection = requestSelection
        self.cancelSelection = cancelSelection
    }

    /// The result: the translation, with the original one tap away.
    func showResult(
        model: TranslateModel,
        translated: String,
        source: String,
        sourceName: String,
        showsOriginal: Bool,
        onCopy: @escaping (String) -> Void,
        near rect: CGRect?,
        on screen: NSScreen?
    ) {
        interactive = true
        // The floating panel is the edge panel's card, seen beside the capture:
        // same width and type scale, so a result reads the same on both.
        let width: CGFloat = SidePanel.expandedWidth
        display(
            content: AnyView(ResultWindowView(
                model: model,
                translated: translated,
                source: source,
                sourceName: sourceName,
                pinned: pinned,
                showsOriginal: showsOriginal,
                colorScheme: model.surfaceColorScheme,
                onCopy: { onCopy(translated) },
                onClose: { [weak self] in self?.closePanel() },
                onPin: { [weak self] in self?.togglePin() },
                requestCapture: requestCapture,
                requestSelection: requestSelection,
                cancelSelection: cancelSelection
            )),
            width: width,
            height: nil,
            near: rect,
            on: screen
        )
        if !pinned { installMonitor() }
    }

    /// A terminal status in the chosen destination.
    func showStatus(
        message: String,
        actionTitle: String? = nil,
        onAction: (() -> Void)? = nil,
        colorScheme: ColorScheme = .dark,
        near rect: CGRect?,
        on screen: NSScreen?
    ) {
        interactive = true
        pinned = false
        display(
            content: AnyView(ResultWindowStatusView(
                message: message,
                actionTitle: actionTitle,
                onAction: onAction,
                colorScheme: colorScheme,
                onClose: { [weak self] in self?.closePanel() }
            )),
            width: 320,
            height: nil,
            minimumHeight: 110,
            near: rect,
            on: screen
        )
        installMonitor()
    }

    /// Closes the panel and hands focus back to the app it covered.
    func closePanel(animated: Bool = true) {
        pinned = false
        removeMonitor()
        stopKeyRetry()
        // Fold back into the dot the card grew from. A fold that starts while
        // the card is still growing turns it round from where it is.
        if animated, isVisible {
            guard !bloomClosing else { return }
            bloomCard = frame
            bloomReveal = 1
            bloomPhase = 1
            startBloom(closing: true)
            return
        }
        stopBloom()
        finishClosing()
    }

    private func finishClosing() {
        stopBloom()
        if activation != nil {
            activation?.finish()
            activation = nil
        } else if let ret = fallbackReturn,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == NSRunningApplication.current.processIdentifier,
                  ret.processIdentifier != NSRunningApplication.current.processIdentifier {
            ret.activate()
        }
        fallbackReturn = nil
        orderOut(nil)
        // The content holds the model and the droplet's actions; a closed panel
        // must not keep them alive until the next result.
        contentView = nil
        hosting = nil
    }

    /// The pin keeps the panel up when the user clicks elsewhere.
    private func togglePin() {
        pinned.toggle()
        if pinned {
            removeMonitor()
        } else {
            installMonitor()
        }
    }

    // MARK: - Display

    /// - Parameters:
    ///   - width: the surface width.
    ///   - height: the surface's fixed height, or `nil` to measure it.
    private func display(
        content: AnyView,
        width: CGFloat,
        height: CGFloat?,
        minimumHeight: CGFloat = 140,
        near rect: CGRect?,
        on screen: NSScreen?
    ) {
        removeMonitor()
        stopKeyRetry()
        // A result arriving while the card is still blooming starts the bloom
        // again from the same point, rather than snapping the card to full size.
        let interruptedBloom = bloomLink != nil
        stopBloom()

        let hosting = NSHostingView(rootView: AnyView(content.panelGlassLift()))
        hosting.wantsLayer = true
        hosting.frame = NSRect(
            origin: .zero,
            size: CGSize(width: width, height: height ?? 200)
        )
        self.hosting = hosting
        // The window manages its content view's frame, so the card lives in a
        // plain container: only the container follows the window, and the
        // hosting view keeps its full size and is scaled inside it.
        let container = NSView(frame: NSRect(origin: .zero, size: hosting.frame.size))
        container.addSubview(hosting)
        contentView = container

        // One layout pass is enough to measure the SwiftUI content.
        hosting.layoutSubtreeIfNeeded()
        let measured = hosting.fittingSize.height
        let panelHeight: CGFloat
        if let height {
            panelHeight = height
        } else {
            panelHeight = min(600, max(minimumHeight, measured.isFinite ? measured : 200))
        }

        let target = screen
            ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let opening = !isVisible || interruptedBloom
        // The panel stays where the user put it after the first presentation.
        let windowFrame: NSRect
        if isVisible {
            let origin = frame.origin
            var kept = NSRect(origin: origin, size: CGSize(width: width, height: panelHeight))
            kept.origin.y = origin.y - (panelHeight - frame.height)
            windowFrame = kept
        } else {
            windowFrame = Self.frameForPanel(
                size: CGSize(width: width, height: panelHeight),
                near: rect,
                on: target
            )
        }
        bloomCard = windowFrame
        if opening {
            // The result blooms out of the point it came from: the card grows
            // on a radius from there, its contents with it, overshooting a
            // little before it settles on the edge panel's bloom curve. A result
            // that arrives mid-flight starts again from the same point.
            if !interruptedBloom {
                bloomPoint = Self.bloomPoint(near: rect, on: target)
            }
            bloomReveal = 0
            bloomPhase = 0
            place(bloom: Self.bloomRect(card: windowFrame, around: bloomPoint, at: 0))
        } else {
            place(bloom: windowFrame)
        }

        // The activation begins once per panel session; beginning it on every
        // status would hand the focus back and leave the panel inactive.
        if activation == nil && fallbackReturn == nil {
            let previousApp = NSWorkspace.shared.frontmostApplication
            makeKeyAndOrderFront(nil)
            activation = DroppyPanelActivation.begin(for: self, returningTo: previousApp)
            if activation == nil {
                // No host activation (harness, older host): take the key
                // ourselves and restore the previous app on close.
                fallbackReturn = previousApp
                NSApp.activate(ignoringOtherApps: true)
            }
        } else {
            makeKeyAndOrderFront(nil)
        }
        // App activation can hand the key back to the host's window; retake it
        // until it sticks.
        startKeyRetry()
        if opening { startBloom(closing: false) }
    }

    // MARK: - Bloom

    /// The point the card blooms out of: the middle of the capture region, or
    /// the pointer when the panel was asked for without one. Host rects count
    /// from the top of the screen, windows from the bottom.
    static func bloomPoint(near rect: CGRect?, on screen: NSScreen?) -> CGPoint {
        let target = screen ?? NSScreen.main ?? NSScreen.screens.first
        let screenFrame = target?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        guard let rect else { return NSEvent.mouseLocation }
        return CGPoint(
            x: screenFrame.origin.x + rect.midX,
            y: screenFrame.origin.y + screenFrame.height - rect.midY
        )
    }

    /// One frame of the open or fold. The card and everything on it scales by
    /// one factor about that point, so it grows on a radius instead of a
    /// rectangle stretching corner to corner. A reveal past 1 overshoots the
    /// card on every side; below 0 it rests on the dot, never through it.
    static func bloomRect(card: NSRect, around point: CGPoint, at reveal: CGFloat) -> NSRect {
        let dot = bloomDot / card.height
        let scale = max(dot, dot + (1 - dot) * reveal)
        return NSRect(
            x: point.x + (card.minX - point.x) * scale,
            y: point.y + (card.minY - point.y) * scale,
            width: card.width * scale,
            height: card.height * scale
        )
    }

    /// The words come in once the card is nearly out, and leave before it
    /// starts to shrink, as on the edge panel.
    static func bloomFade(_ reveal: CGFloat) -> CGFloat {
        let t = min(max((reveal - 0.45) / 0.45, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Puts one frame of the bloom on screen. The window takes the scaled
    /// card's rect and the content is laid out once at its full size and
    /// scaled as one picture, so the words never reflow or hit the window's
    /// edge while the card is small.
    private func place(bloom rect: NSRect) {
        setFrame(rect, display: true)
        guard let hosting else { return }
        let full = bloomCard.size
        let scale = full.height > 0 ? rect.height / full.height : 1
        hosting.frame = NSRect(
            x: (rect.width - full.width) / 2,
            y: (rect.height - full.height) / 2,
            width: full.width,
            height: full.height
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hosting.layer?.transform = CATransform3DMakeScale(scale, scale, 1)
        CATransaction.commit()
        hosting.alphaValue = Self.bloomFade(bloomReveal)
    }

    private func startBloom(closing: Bool) {
        bloomClosing = closing
        lastBloomTick = CACurrentMediaTime()
        guard bloomLink == nil, let hosting else { return }
        let link = hosting.displayLink(target: self, selector: #selector(stepBloom(_:)))
        link.add(to: .main, forMode: .common)
        bloomLink = link
    }

    private func stopBloom() {
        bloomLink?.invalidate()
        bloomLink = nil
    }

    @objc private func stepBloom(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let dt = max(now - lastBloomTick, 0)
        lastBloomTick = now
        // The open runs the shared curve forwards on its length, the fold runs
        // its own monotone curve on the shorter one.
        let target: CGFloat = bloomClosing ? 0 : 1
        let duration = bloomClosing ? SidePanel.foldDuration : SidePanel.bloomDuration
        let rate = CGFloat(dt) / CGFloat(duration)
        bloomPhase = bloomPhase < target
            ? min(target, bloomPhase + rate)
            : max(target, bloomPhase - rate)
        bloomReveal = bloomClosing
            ? SidePanel.foldShape(bloomPhase)
            : SidePanel.bloomShape(bloomPhase)
        place(bloom: Self.bloomRect(card: bloomCard, around: bloomPoint, at: bloomReveal))
        guard bloomPhase == target else { return }
        link.invalidate()
        bloomLink = nil
        if bloomClosing { finishClosing() }
    }

    /// 8pt below the region, above when it does not fit, clamped to the
    /// screen. A nil rect falls back to the pointer.
    private static func frameForPanel(
        size: CGSize,
        near rect: CGRect?,
        on screen: NSScreen?
    ) -> NSRect {
        let target = screen ?? NSScreen.main ?? NSScreen.screens.first
        let visible = target?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let screenFrame = target?.frame ?? visible

        let left: CGFloat
        let rectTop: CGFloat
        let rectBottom: CGFloat
        if let rect {
            left = screenFrame.origin.x + rect.origin.x
            rectTop = screenFrame.origin.y + screenFrame.height - rect.origin.y
            rectBottom = rectTop - rect.height
        } else {
            let mouse = NSEvent.mouseLocation
            left = mouse.x
            rectTop = mouse.y + 1
            rectBottom = mouse.y
        }

        var x = left
        var y = rectBottom - 8 - size.height
        if y < visible.minY + 8 {
            y = rectTop + 8
        }
        x = min(max(x, visible.minX + 8), max(visible.minX + 8, visible.maxX - size.width - 8))
        y = min(max(y, visible.minY + 8), max(visible.minY + 8, visible.maxY - size.height - 8))
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }

    // MARK: - Click outside

    private func installMonitor() {
        removeMonitor()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.isVisible, self.interactive else { return }
                if !self.frame.contains(NSEvent.mouseLocation) {
                    self.closePanel()
                }
            }
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func startKeyRetry() {
        stopKeyRetry()
        makeKey()
        keyTask = Task { @MainActor [weak self] in
            for _ in 0..<5 {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, !Task.isCancelled else { return }
                if self.isKeyWindow { break }
                self.makeKey()
            }
        }
    }

    private func stopKeyRetry() {
        keyTask?.cancel()
        keyTask = nil
    }
}

// MARK: - Content

private let panelRadius: CGFloat = 44

private let panelTileRadius: CGFloat = 29

private let panelInset = DroppySpacing.lg

/// The panel's surface is dark, so it takes the notch's ink tokens; the system's
/// adaptive ink would vanish in light appearance.
private let panelInk = AdaptiveColors.notchSurfacePrimaryText.opacity(0.92)
private let panelSecondaryInk = AdaptiveColors.notchSurfaceSecondaryText

/// What the panel's tiles sit on.
///
/// The live panel sits on the host's own surface for the theme in Droppy
/// (`SidePanelCardSurface`), the same card the shelf and the edge panel wear.
/// The settings picture puts that surface over the droplet's black, so a glass
/// theme melts from black the way it does on the desktop, instead of melting
/// into the settings page behind it.
enum PanelBackdrop {
    case hostGlass
    case hostGlassOnBlack
}

struct ResultWindowView: View {
    /// The live model, so the footer's more menu and engine picker act on the
    /// same state as the shelf and the edge panel.
    @ObservedObject var model: TranslateModel
    let translated: String
    let source: String
    let sourceName: String
    let pinned: Bool
    let showsOriginal: Bool
    /// The scheme the host draws its surfaces in; the panel's ink follows it.
    var colorScheme: ColorScheme = .dark
    /// The surface behind the tiles.
    var backdrop: PanelBackdrop = .hostGlass
    let onCopy: () -> Void
    let onClose: () -> Void
    let onPin: () -> Void
    var requestCapture: () -> Void = {}
    var requestSelection: () -> Void = {}
    var cancelSelection: () -> Void = {}

    /// The footer's height, the same as the shelf's and the edge panel's.
    static let footerHeight = PanelFooterMetrics.disc + 6
    /// The card's floor is the shelf's short card: the more menu opens upward
    /// in one column, and a shorter card would cut the menu's top row on its
    /// own rim.
    static let minimumHeight: CGFloat = 246

    @State private var copied = false
    @State private var isPinned: Bool
    @State private var pointerOnMore = false
    @State private var pointerInMenu = false
    @State private var moreCloseTask: Task<Void, Never>?
    /// One piece of glass that slides to the control under the pointer.
    @StateObject private var chip: SidePanelChipState

    init(
        model: TranslateModel,
        translated: String,
        source: String,
        sourceName: String,
        pinned: Bool,
        showsOriginal: Bool,
        colorScheme: ColorScheme = .dark,
        backdrop: PanelBackdrop = .hostGlass,
        onCopy: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onPin: @escaping () -> Void,
        requestCapture: @escaping () -> Void = {},
        requestSelection: @escaping () -> Void = {},
        cancelSelection: @escaping () -> Void = {},
        chipState: SidePanelChipState? = nil
    ) {
        self.model = model
        self.translated = translated
        self.source = source
        self.sourceName = sourceName
        self.pinned = pinned
        self.showsOriginal = showsOriginal
        self.colorScheme = colorScheme
        self.backdrop = backdrop
        self.onCopy = onCopy
        self.onClose = onClose
        self.onPin = onPin
        self.requestCapture = requestCapture
        self.requestSelection = requestSelection
        self.cancelSelection = cancelSelection
        _isPinned = State(initialValue: pinned)
        _chip = StateObject(wrappedValue: chipState ?? SidePanelChipState())
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: DroppySpacing.smd) {
                if showsOriginal, !source.isEmpty {
                    sourceTile
                }
                resultTile
                footer
                    .padding(.top, DroppySpacing.xs)
            }
            chipLayer
        }
        .coordinateSpace(name: SidePanelChipState.space)
        .environment(\.sidePanelChip, chip)
        .onPreferenceChange(SidePanelChipFrameKey.self) { chip.frames = $0 }
        // One tracking area over the card: the chip follows the pointer from
        // control to control, as it does on the edge panel.
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                let target = SidePanelContentView.target(at: point, frames: chip.frames)
                if target != chip.target { chip.target = target }
            case .ended:
                chip.target = nil
                chip.pressed = false
            }
        }
        .environment(\.colorScheme, colorScheme)
        .padding(panelInset)
        .frame(minHeight: Self.minimumHeight)
        .background { backdropView }
        .clipShape(RoundedRectangle(cornerRadius: panelRadius, style: .continuous))
        .shadow(radius: 12, y: 4)
        .background(
            Button("") { onClose() }
                .keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        )
        .onDisappear {
            moreCloseTask?.cancel()
            model.isToolbarExpanded = false
        }
    }

    /// The surface the tiles sit on.
    @ViewBuilder
    private var backdropView: some View {
        let shape = AnyShape(
            RoundedRectangle(cornerRadius: panelRadius, style: .continuous)
        )
        switch backdrop {
        case .hostGlass:
            SidePanelCardSurface(shape: shape)
        case .hostGlassOnBlack:
            shape
                .fill(.black)
                .overlay { SidePanelCardSurface(shape: shape) }
        }
    }

    private var sourceTile: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.xs) {
            LanguageMenu(
                model: model,
                selection: $model.sourceID,
                includesAuto: true,
                label: sourceMenuLabel,
                fontSize: SidePanelContentView.labelFontSize,
                chipTarget: .source,
                showsChevron: true
            )
            .chipTarget(.source)
            Text(source)
                .font(.system(size: SidePanelContentView.bodyFontSize))
                .foregroundStyle(panelInk)
                .cardTextShadow()
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DroppySpacing.md)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            // The same glass the shelf and the edge panel put their boxes on,
            // so the tiles take the theme's colour instead of a fixed wash.
            Color.clear
                .droppyGlassControlChrome(
                    shape: AnyShape(
                        RoundedRectangle(cornerRadius: panelTileRadius, style: .continuous)
                    )
                )
        }
    }

    private var sourceMenuLabel: String {
        model.sourceID == TranslateModel.auto ? sourceName : model.name(for: model.sourceID)
    }

    private var resultTile: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.xs) {
            // The target language is a picker here, as in the language row
            // on the shelf; changing it translates the source again.
            LanguageMenu(
                model: model,
                selection: $model.targetID,
                includesAuto: false,
                label: model.name(for: model.targetID),
                fontSize: SidePanelContentView.labelFontSize,
                chipTarget: .target,
                availableIDs: model.installedTargetIDs,
                showsChevron: true
            )
            .chipTarget(.target)
            Text(translated)
                .font(.system(size: SidePanelContentView.bodyFontSize))
                .foregroundStyle(panelInk)
                .cardTextShadow()
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            // The copy sits on the tile's bottom edge, as on the edge panel's
            // result box, so a taller card does not leave it floating.
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Button {
                    onCopy()
                    copied = true
                    Task {
                        try? await Task.sleep(for: .milliseconds(600))
                        copied = false
                    }
                } label: {
                    PanelCopyLabel(copied: copied)
                        .chipHidesInk(chip.covers(.copy))
                }
                .buttonStyle(DroppyQuietButtonStyle(size: .small))
                .chipTarget(.copy)
                .keyboardShortcut("c", modifiers: .command)
                .a11y(copied ? "a11y.copied" : "a11y.copy")
            }
        }
        .padding(DroppySpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            // The same glass the shelf and the edge panel put their boxes on,
            // so the tiles take the theme's colour instead of a fixed wash.
            Color.clear
                .droppyGlassControlChrome(
                    shape: AnyShape(
                        RoundedRectangle(cornerRadius: panelTileRadius, style: .continuous)
                    )
                )
        }
    }

    /// The footer both siblings wear: the more disc on the leading edge and
    /// the Translate wordmark with its engine on the trailing edge. The menu
    /// opens upward from the disc, as it does on the shelf and the edge panel.
    private var footer: some View {
        HStack(alignment: .center, spacing: DroppySpacing.sm) {
            ToolbarCapsule(
                model: model,
                requestCapture: requestCapture,
                requestSelection: requestSelection,
                cancelSelection: cancelSelection,
                fan: .up,
                onMoreHover: { moreHover($0, inMenu: false) },
                chipTarget: .more
            )
            Spacer(minLength: 0)
            PanelEngineMenu(model: model)
        }
        .frame(height: Self.footerHeight, alignment: .bottom)
        .overlay(alignment: .bottomLeading) {
            if model.isToolbarExpanded {
                PanelMoreMenu(
                    model: model,
                    requestCapture: requestCapture,
                    requestSelection: requestSelection,
                    cancelSelection: cancelSelection,
                    onHover: { moreHover($0, inMenu: true) },
                    pinned: isPinned,
                    onPin: togglePin
                )
                .offset(y: -Self.footerHeight)
                .transition(.scale(scale: 0.96, anchor: .bottomLeading).combined(with: .opacity))
            }
        }
    }

    private func togglePin() {
        isPinned.toggle()
        onPin()
    }

    /// Opens the menu while the pointer is on the disc or in it, and folds it
    /// a moment after the pointer leaves both, as the edge panel does.
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
            moreCloseTask?.cancel()
            guard model.isToolbarExpanded else { return }
            moreCloseTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(280))
                guard !Task.isCancelled else { return }
                model.isToolbarExpanded = false
            }
        }
    }

    // MARK: - The chip

    /// The panel's sliding effect: one piece of glass that marks the control
    /// under the pointer, wherever it sits on the card. It travels between
    /// controls, so a move reads as the glass sliding, not blinking.
    private var chipLayer: some View {
        ZStack(alignment: .topLeading) {
            chipWash
            chipGlass
            chipInk
        }
        .allowsHitTesting(false)
        .animation(DroppyAnimation.tabSelect, value: chip.target)
    }

    /// A menu row takes a wash in its own silhouette: it already sits on the
    /// menu's glass, and a second glass over it would hide its words.
    @ViewBuilder
    private var chipWash: some View {
        if let rect = chip.rect(resting: nil), chip.marksWithWash(chip.target) {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(AdaptiveColors.overlayAuto(0.14))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .animation(DroppyAnimation.tabSelect, value: rect)
        }
    }

    /// The glass over the marked control. It takes the control's frame and
    /// reaches toward the one it is travelling to.
    @ViewBuilder
    private var chipGlass: some View {
        if let rect = chip.rect(resting: nil) {
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
                .opacity(chip.target == nil || chip.marksWithWash(chip.target) ? 0 : 1)
                .animation(DroppyAnimation.tabSelect, value: rect)
                .animation(DroppyAnimation.state, value: chip.target == nil)
        }
    }

    /// The marked control's ink, drawn above the glass so the glass never sits
    /// over the glyph. The control hides its own copy while the chip covers it.
    @ViewBuilder
    private var chipInk: some View {
        if let target = chip.target, let frame = chip.frames[target] {
            PanelChipInk(scale: chip.inkScale) {
                chipInk(for: target)
                    .frame(width: frame.width, height: frame.height)
            }
            .offset(x: frame.minX, y: frame.minY)
            .id(target)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private func chipInk(for target: SidePanelChipTarget) -> some View {
        switch target {
        case .source:
            PanelMenuLabel(text: sourceMenuLabel, fontSize: SidePanelContentView.labelFontSize)
        case .target:
            PanelMenuLabel(text: model.name(for: model.targetID), fontSize: SidePanelContentView.labelFontSize)
        case .copy:
            PanelCopyLabel(copied: copied)
        case .more:
            PanelMoreGlyph(
                iconFont: 12,
                rotation: model.isToolbarExpanded ? 90 : 0
            )
            .animation(DroppyAnimation.state, value: model.isToolbarExpanded)
        case .engine:
            PanelEngineLabel(model: model)
        default:
            EmptyView()
        }
    }
}

/// The copy disc's label. The chip draws this same view above its own glass,
/// so the words never shift.
private struct PanelCopyLabel: View {
    var copied: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: copied ? "checkmark" : "document.on.document")
            Text(copied ? L10n.tr("panel.copied") : L10n.tr("panel.copy"))
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(AdaptiveColors.primaryTextAuto.opacity(0.92))
        .cardTextShadow()
    }
}

struct ResultWindowStatusView: View {
    let message: String
    var actionTitle: String? = nil
    var onAction: (() -> Void)? = nil
    var colorScheme: ColorScheme = .dark
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(message)
                    .font(.system(size: 13))
                    .cardTextShadow()
                    .lineLimit(4)
            }
            Spacer(minLength: 0)
            HStack(spacing: DroppySpacing.sm) {
                if let actionTitle, let onAction {
                    Button(action: onAction) {
                        Text(actionTitle).cardTextShadow()
                    }
                    .buttonStyle(DroppyAccentButtonStyle(size: .small))
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Text(L10n.tr("panel.dismiss")).cardTextShadow()
                }
                .buttonStyle(DroppyQuietButtonStyle(size: .small))
            }
        }
        .padding(16)
        .environment(\.colorScheme, colorScheme)
        .background {
            SidePanelCardSurface(
                shape: AnyShape(
                    RoundedRectangle(cornerRadius: panelRadius, style: .continuous)
                )
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: panelRadius, style: .continuous))
        .shadow(radius: 12, y: 4)
        .background(
            Button("") { onClose() }
                .keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        )
    }
}
