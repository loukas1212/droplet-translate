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
    /// The card: the surface layer under the content, scaled as one piece
    /// during the bloom.
    private var cardView: NSView?
    private var monitor: Any?
    private var activation: DroppyPanelActivation?
    private var fallbackReturn: NSRunningApplication?
    private var keyTask: Task<Void, Never>?
    private var interactive = false
    private var pinned = false
    /// Whether the model's own card is the face on screen. A live card follows
    /// the model, so a result must not build a second one.
    private var wearsCard = false
    /// The content's own controls: the sliding chip and the card's pin. They
    /// live here so the panel can resize without losing them, exactly as the
    /// edge panel keeps them on its window.
    private let chip = SidePanelChipState()
    private let pin = SidePanelPinState()
    /// The card body the content asked for.
    private var bodyHeight = SidePanelContentView.floatingMinBodyHeight
    /// Whether the panel opened from its shortcut for the user to type in. A
    /// card opened on a result leaves the keyboard where it is.
    private var focusesEditor = false
    /// The glass's active face while a pinned panel is not the key window.
    private lazy var keyAppearance = PanelKeyAppearance(panel: self)
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
    /// The tallest the card grows before its result scrolls.
    static let maximumHeight: CGFloat = 600

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
        // The card is the window: a drag on its face moves the panel, while
        // boxes and controls keep their presses. `sendEvent` does the moving
        // because AppKit's background drag left the frame in place.
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(appDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(windowDidChangeKey),
            name: NSWindow.didResignKeyNotification,
            object: self
        )
        center.addObserver(
            self,
            selector: #selector(windowDidChangeKey),
            name: NSWindow.didBecomeKeyNotification,
            object: self
        )
    }

    /// A press on the card's face makes the panel follow the pointer while the
    /// button is held. A timer reads the pointer instead of drag events:
    /// SwiftUI takes some presses, but the button state is always available.
    private var dragAnchor: NSPoint?
    /// The panel's origin at the press. Movement is added to it, so other frame
    /// changes cannot make the drag drift.
    private var dragOrigin = NSPoint.zero
    private var dragMoved = false
    private var dragTimer: Timer?

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            let hit = contentView?.hitTest(event.locationInWindow)
            if Self.canDragFrom(hit) { beginDrag() } else { endDrag() }
        case .leftMouseDragged:
            followPointer()
        case .leftMouseUp:
            endDrag()
        default:
            break
        }
        super.sendEvent(event)
    }

    private func beginDrag() {
        endDrag()
        let mouse = NSEvent.mouseLocation
        dragAnchor = mouse
        dragOrigin = frame.origin
        dragMoved = false
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.dragTick() }
        }
        // Common modes, so it keeps running while AppKit or SwiftUI is
        // tracking the press.
        RunLoop.main.add(timer, forMode: .common)
        dragTimer = timer
    }

    private func endDrag() {
        dragTimer?.invalidate()
        dragTimer = nil
        dragAnchor = nil
        dragMoved = false
    }

    private func dragTick() {
        guard dragAnchor != nil else { endDrag(); return }
        // A release the window never saw still ends the drag.
        guard NSEvent.pressedMouseButtons & 1 != 0 else { endDrag(); return }
        followPointer()
    }

    private func followPointer() {
        guard let anchor = dragAnchor, bloomLink == nil else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - anchor.x
        let dy = now.y - anchor.y
        if !dragMoved {
            guard abs(dx) + abs(dy) > 3 else { return }
            dragMoved = true
        }
        setFrameOrigin(NSPoint(x: dragOrigin.x + dx, y: dragOrigin.y + dy))
    }

    /// Text boxes and AppKit controls keep their own presses; everything else
    /// on the card drags the panel.
    private static func canDragFrom(_ view: NSView?) -> Bool {
        var current = view
        while let v = current {
            if v is NSTextView || v is NSScrollView || v is NSControl { return false }
            current = v.superview
        }
        return true
    }

    override var canBecomeKey: Bool { true }
    // `DroppyPanelActivation` makes the panel key and main at once, and AppKit
    // throws when asked to make a borderless window main.
    override var canBecomeMain: Bool { true }

    /// The card is up and not folding. Rebuilding it would move its top even
    /// when the content has not changed.
    private var keepsLiveCard: Bool {
        isVisible && wearsCard && !bloomClosing
    }

    // MARK: - Entry points

    /// The actions the more menu offers. The droplet handles capture and
    /// selection, so it passes them in once, as it does for the edge panel.
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
        focusesEditor = false
        // The card watches the model it was opened with, so a result that
        // lands while it is up needs no new face.
        if keepsLiveCard {
            if !pinned { installMonitor() }
            return
        }
        // The card ends where the content does: both boxes, or the translation
        // alone, with the result fitted to its words.
        let alone = !showsOriginal
        let box = showsOriginal ? SidePanelContentView.floatingBoxFloor : 0
        bodyHeight = SidePanelContentView.bodyHeight(
            forBox: box,
            result: true,
            resultHeight: SidePanelContentView.floatingFittedResultHeight(
                text: translated,
                alone: alone,
                matching: box
            )
        )
        display(
            content: floatingContent(model: model),
            width: SidePanel.expandedWidth,
            height: bodyHeight,
            near: rect,
            on: screen
        )
        wearsCard = true
        if !pinned { installMonitor() }
    }

    /// The panel with an empty box, opened from its shortcut: the same card
    /// the edge panel opens, with the keyboard in the field.
    func showEmpty(
        model: TranslateModel,
        near rect: CGRect? = nil,
        on screen: NSScreen? = nil
    ) {
        interactive = true
        focusesEditor = true
        pinned = false
        pin.isPinned = false
        if keepsLiveCard {
            takeEditorFocus()
            installMonitor()
            return
        }
        bodyHeight = SidePanelContentView.floatingMinBodyHeight
        display(
            content: floatingContent(model: model),
            width: SidePanel.expandedWidth,
            height: bodyHeight,
            near: rect,
            on: screen
        )
        wearsCard = true
        installMonitor()
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
        focusesEditor = false
        // The card draws the same status, with the same download and retry
        // controls as the edge panel. A live card keeps its face.
        if keepsLiveCard { return }
        pinned = false
        display(
            content: AnyView(ResultWindowStatusView(
                message: message,
                actionTitle: actionTitle,
                onAction: onAction,
                colorScheme: colorScheme,
                backdrop: .windowSurface,
                onClose: { [weak self] in self?.closePanel() }
            )),
            width: 320,
            height: nil,
            minimumHeight: 0,
            near: rect,
            on: screen
        )
        wearsCard = false
        installMonitor()
    }

    /// Closes the panel and hands focus back to the app it covered.
    func closePanel(animated: Bool = true) {
        focusesEditor = false
        pinned = false
        pin.isPinned = false
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
        endDrag()
        stopBloom()
        wearsCard = false
        if activation != nil {
            activation?.finish()
            activation = nil
        } else if let ret = fallbackReturn,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == NSRunningApplication.current.processIdentifier,
                  ret.processIdentifier != NSRunningApplication.current.processIdentifier {
            ret.activate()
        }
        fallbackReturn = nil
        keyAppearance.hold(false)
        orderOut(nil)
        // The content holds the model and the droplet's actions; a closed panel
        // must not keep them alive until the next result.
        contentView = nil
        hosting = nil
        cardView = nil
    }

    /// The pin keeps the panel up when the user clicks elsewhere.
    private func togglePin() {
        pinned.toggle()
        pin.isPinned = pinned
        if pinned {
            removeMonitor()
        } else {
            installMonitor()
        }
        updateKeyAppearance()
    }

    @objc private func appDidResignActive() {
        updateKeyAppearance()
    }

    @objc private func appDidBecomeActive() {
        updateKeyAppearance()
    }

    @objc private func windowDidChangeKey() {
        updateKeyAppearance()
    }

    /// The panel keeps one face while it is open: unpinning must not hand it
    /// back to the system's frosted inactive glass under the pointer.
    private func updateKeyAppearance() {
        keyAppearance.hold(
            PanelKeyAppearance.shouldHold(
                pinned: pinned,
                shown: isVisible
            )
        )
    }

    /// The panel's body: the edge panel's card in the floating panel's rounded
    /// outline. All controls come from this one view, so the two cannot drift.
    private func floatingContent(model: TranslateModel) -> AnyView {
        let translationOnly = !model.resultPage.showsOriginal
        return AnyView(
            FloatingPanelBody(
                model: model,
                chip: chip,
                pin: pin,
                requestCapture: requestCapture,
                requestSelection: requestSelection,
                cancelSelection: cancelSelection,
                onClose: { [weak self] in self?.closePanel() },
                onPin: { [weak self] in self?.togglePin() },
                onBodyHeight: { [weak self] height, animated in
                    Task { @MainActor in
                        self?.applyBodyHeight(height, animated: animated)
                    }
                },
                translationOnly: translationOnly
            )
            .background(
                Button("") { [weak self] in self?.closePanel() }
                    .keyboardShortcut(.cancelAction)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            )
        )
    }

    /// The body height the window takes, between the empty card's floor and the
    /// tallest card. A folded card ends higher, at its fitted result.
    static func clampedBodyHeight(_ height: CGFloat) -> CGFloat {
        min(
            max(height, SidePanelContentView.floatingMinBodyHeight),
            SidePanelContentView.floatingMaxBodyHeight
        )
    }

    /// The content reports the height it needs and the window follows, keeping
    /// its top edge so the line being typed does not move.
    private func applyBodyHeight(_ height: CGFloat, animated: Bool) {
        let clamped = Self.clampedBodyHeight(height)
        guard abs(clamped - bodyHeight) > 0.5 else { return }
        bodyHeight = clamped
        guard isVisible else { return }
        // A box that grows during the bloom must take the card with it, or the
        // footer hangs under the card's edge.
        let resting = bloomLink == nil ? frame : bloomCard
        let target = Self.frameKeepingTop(
            resting,
            size: CGSize(width: resting.width, height: clamped)
        )
        bloomCard = target
        guard bloomLink == nil else { return }
        place(bloom: target)
    }

    /// The window of `size` with the same top edge as `frame`. The card grows
    /// and folds from its top, so the line being read never moves.
    static func frameKeepingTop(_ frame: NSRect, size: CGSize) -> NSRect {
        NSRect(
            x: frame.minX,
            y: frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
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
        // The card is the app's dark glass whatever the system is set to, so
        // its ink follows the card, as it does on the edge panel.
        hosting.appearance = NSAppearance(named: .darkAqua)
        hosting.wantsLayer = true
        hosting.frame = NSRect(
            origin: .zero,
            size: CGSize(width: width, height: height ?? 200)
        )
        self.hosting = hosting

        // The card's surface is its own layer, under the content, so the bloom
        // scales it with the boxes and the tiles sit on themed glass.
        let surface = NSHostingView(
            rootView: PanelSurfaceLayer()
        )
        surface.appearance = NSAppearance(named: .darkAqua)
        surface.autoresizingMask = [.width, .height]
        surface.frame = hosting.bounds
        let glass = PanelSurfaceHost(frame: hosting.bounds)
        glass.addSubview(surface)

        let card = PanelCardView(frame: hosting.frame)
        card.wantsLayer = true
        // A clear window lets clicks fall through transparent pixels, so the
        // glass alone does not hold a press. An almost invisible fill in the
        // card's outline keeps every point hit-able and scales with the bloom.
        card.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.01).cgColor
        card.layer?.cornerRadius = panelRadius
        card.layer?.cornerCurve = .continuous
        card.addSubview(glass)
        card.addSubview(hosting)
        self.cardView = card
        // The window manages its content view's frame, so the card lives in a
        // plain container that keeps its size and is scaled inside it.
        let container = NSView(frame: hosting.frame)
        container.addSubview(card)
        contentView = container

        // One layout pass is enough to measure the SwiftUI content.
        hosting.layoutSubtreeIfNeeded()
        let panelHeight: CGFloat
        if let height {
            panelHeight = height
        } else {
            let measured = hosting.fittingSize.height
            panelHeight = min(
                Self.maximumHeight,
                max(minimumHeight, measured.isFinite ? measured : 200)
            )
        }

        let target = screen
            ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let opening = !isVisible || interruptedBloom
        // The panel stays where the user put it after the first presentation.
        let windowFrame: NSRect
        if isVisible {
            windowFrame = Self.frameKeepingTop(
                frame,
                size: CGSize(width: width, height: panelHeight)
            )
        } else {
            windowFrame = Self.frameForPanel(
                size: CGSize(width: width, height: panelHeight),
                near: rect,
                on: target
            )
        }
        bloomCard = windowFrame
        if opening {
            // The card blooms from the point it came from, growing on a radius
            // with its contents and overshooting slightly. A result that arrives
            // mid-flight starts again from the same point.
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
        if focusesEditor { takeEditorFocus() }
        if opening { startBloom(closing: false) }
        updateKeyAppearance()
    }

    // MARK: - Bloom

    /// Where the card blooms from: the capture region's middle, or the pointer
    /// without one. Host rects count from the top, windows from the bottom.
    static func bloomPoint(near rect: CGRect?, on screen: NSScreen?) -> CGPoint {
        let target = screen ?? NSScreen.main ?? NSScreen.screens.first
        let screenFrame = target?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        guard let rect else { return NSEvent.mouseLocation }
        return CGPoint(
            x: screenFrame.origin.x + rect.midX,
            y: screenFrame.origin.y + screenFrame.height - rect.midY
        )
    }

    /// One frame of the open or fold. The card scales by one factor around the
    /// bloom point, so it grows on a radius instead of stretching corner to
    /// corner; past 1 it overshoots, below 0 it rests on the dot.
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

    /// Puts one bloom frame on screen. The window takes the scaled card's rect,
    /// and the content is laid out once at full size and scaled as a picture, so
    /// words never reflow or clip while the card is small.
    private func place(bloom rect: NSRect) {
        setFrame(rect, display: true)
        guard let card = cardView else { return }
        let full = bloomCard.size
        let scale = full.height > 0 ? rect.height / full.height : 1
        card.frame = NSRect(
            x: (rect.width - full.width) / 2,
            y: (rect.height - full.height) / 2,
            width: full.width,
            height: full.height
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        card.layer?.transform = CATransform3DMakeScale(scale, scale, 1)
        CATransaction.commit()
        card.alphaValue = Self.bloomFade(bloomReveal)
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

    /// The shortcut opens the card for typing, so the field takes the keyboard.
    /// Activation can move focus, so the ask repeats for a few turns.
    private func takeEditorFocus() {
        Task { @MainActor [weak self] in
            for _ in 0..<5 {
                guard let self, self.focusesEditor, self.isVisible else { return }
                if let content = self.contentView,
                   let editor = firstEditor(in: content) {
                    if self.firstResponder === editor { return }
                    self.makeFirstResponder(editor)
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }
}

// MARK: - Content

let panelRadius: CGFloat = 44

/// The floating panel's content: the edge panel's card, drawn in the panel's
/// own rounded outline, and the shortcut opens the same card drawn in it.
struct FloatingPanelBody: View {
    @ObservedObject var model: TranslateModel
    @ObservedObject var chip: SidePanelChipState
    @ObservedObject var pin: SidePanelPinState
    var requestCapture: () -> Void = {}
    var requestSelection: () -> Void = {}
    var cancelSelection: () -> Void = {}
    var onClose: () -> Void = {}
    var onPin: () -> Void = {}
    var onBodyHeight: (CGFloat, Bool) -> Void = { _, _ in }
    /// The content setting asks for the translation alone: the card starts
    /// with the original folded away and the result in its place.
    var translationOnly = false

    var body: some View {
        SidePanelContentView(
            model: model,
            chip: chip,
            pin: pin,
            requestCapture: requestCapture,
            requestSelection: requestSelection,
            cancelSelection: cancelSelection,
            boxFloor: SidePanelContentView.floatingBoxFloor,
            boxCap: SidePanelContentView.floatingBoxCap,
            translationOnly: translationOnly,
            fitsResult: true,
            showsGrip: false,
            maxBodyHeight: SidePanelContentView.floatingMaxBodyHeight,
            onClose: onClose,
            onPin: onPin,
            onBodyHeight: onBodyHeight
        )
        .padding(.horizontal, SidePanelContentView.sideInset)
        .padding(.vertical, SidePanelContentView.inset)
    }
}

/// The host's surface for Droppy's theme, the same card the shelf and edge
/// panel use. It lives in its own layer, so the bloom scales it with the content.
enum PanelBackdrop {
    /// The surface is drawn in the view.
    case hostGlass
    /// The window draws the surface in its own layer behind the content, as
    /// the edge panel does.
    case windowSurface

    /// True when the view draws the card's surface itself.
    var drawsCard: Bool {
        self != .windowSurface
    }
}

/// The card's face behind a panel's content.
private struct PanelSurfaceBackdrop: View {
    let backdrop: PanelBackdrop
    let shape: AnyShape

    var body: some View {
        switch backdrop {
        case .hostGlass:
            SidePanelCardSurface(shape: shape)
        case .windowSurface:
            Color.clear
        }
    }
}

/// The card's glass, in its own AppKit layer under the content.
/// `NSHostingView` keeps it out of the SwiftUI tree, as the edge panel does,
/// so the card stays one layer under the boxes.
private struct PanelSurfaceLayer: View {
    var body: some View {
        SidePanelCardSurface(
            shape: AnyShape(
                RoundedRectangle(cornerRadius: panelRadius, style: .continuous)
            )
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Holds the card's surface layer; the content above owns every click.
private final class PanelSurfaceHost: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The card as one piece: the surface layer and the content fill it together,
/// so the bloom scales both on the same transform.
private final class PanelCardView: NSView {
    override func layout() {
        super.layout()
        for subview in subviews {
            subview.frame = bounds
        }
    }
}

struct ResultWindowStatusView: View {
    let message: String
    var actionTitle: String? = nil
    var onAction: (() -> Void)? = nil
    var colorScheme: ColorScheme = .dark
    var backdrop: PanelBackdrop = .hostGlass
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
            PanelSurfaceBackdrop(
                backdrop: backdrop,
                shape: AnyShape(
                    RoundedRectangle(cornerRadius: panelRadius, style: .continuous)
                )
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: panelRadius, style: .continuous))
        .shadow(
            color: backdrop.drawsCard ? .black.opacity(0.33) : .clear,
            radius: 12,
            y: 4
        )
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