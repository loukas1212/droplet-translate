import AppKit
import DroppyKit
import QuartzCore
import SwiftUI

/// The card's outline, published so the glass layer can be masked to it.
///
/// The surface is a material: it would fill the whole window if it were not
/// clipped, and the card's edge is the edge of the screen.
final class SidePanelSurfaceState: ObservableObject {
    @Published var silhouette = Path()
    /// Mirrors the rim's fade to the left edge when the panel docks left.
    @Published var mirrored = false
}

/// The handle's amount: how far its lobe hangs out of the card's edge.
///
/// The lobe is part of the card's own path, so the card's surface covers the
/// card and the lobe in one layer, and the colour never breaks between them.
/// The mark on the lobe rides the same amount, so it stays on the lobe.
final class SidePanelGripState: ObservableObject {
    @Published var amount: CGFloat = 0
}

/// Whether the card stays open when the user clicks elsewhere. The pin belongs
/// to this window; the model's pin holds the shelf open and is a different
/// surface.
final class SidePanelPinState: ObservableObject {
    @Published var isPinned = false
}

/// The card's face in the theme the user picked in Droppy.
///
/// Black is a solid card, Liquid Glass is the system's clear glass, and
/// Dynamic Glass is black melting into that glass. The glass is drawn on the
/// card's own outline, so its rim is the card's edge and nothing else sits
/// under it.
struct SidePanelCardSurface: View {
    let shape: AnyShape
    var mirrored = false
    @StateObject private var theme = HostThemeStore()

    var body: some View {
        switch theme.current {
        case .black:
            shape.fill(.black)
        case .liquidGlass:
            glass.overlay { rim }
        case .dynamicGlass:
            // The melt sits over the glass, so the top stays the shelf's
            // black and the glass only shows where the black has faded.
            glass
                .overlay { melt }
                .overlay { rim }
        }
    }

    @ViewBuilder
    private var glass: some View {
        if #available(macOS 26.0, *) {
            shape
                .fill(.clear)
                .glassEffect(.clear, in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }

    /// Dynamic Glass: black at the top, melting into the glass below.
    private var melt: some View {
        shape.fill(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.45),
                    .init(color: .clear, location: 0.78)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    /// The shelf's edge, drawn inside the card so the window's edge cannot cut
    /// it in half. The host's own shelf has a thin dark line and no bright rim,
    /// so the glass keeps the same hairline instead of a white outline. It
    /// fades out at the screen edge, where the card is not free-standing.
    private var rim: some View {
        GeometryReader { geo in
            // The fade belongs to the screen edge, so it scales with the
            // surface: a fixed 40pt fade would swallow the whole rim of the tab.
            let fade = min(40, geo.size.width * 0.2)
            shape
                .stroke(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.55), location: 0),
                            .init(color: .white.opacity(0.08), location: 0.45),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .mask { shape.fill(.white) }
                .mask {
                    HStack(spacing: 0) {
                        if mirrored {
                            LinearGradient(
                                colors: [.clear, .white],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: fade)
                            Color.white
                        } else {
                            Color.white
                            LinearGradient(
                                colors: [.white, .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: fade)
                        }
                    }
                }
        }
    }
}

/// The live card, on the outline the panel publishes as it moves.
struct SidePanelSurfaceLayer: View {
    @ObservedObject var state: SidePanelSurfaceState

    var body: some View {
        SidePanelCardSurface(shape: AnyShape(state.silhouette), mirrored: state.mirrored)
            .allowsHitTesting(false)
    }
}

/// The small tab the droplet keeps on the right edge of the screen.
///
/// DroppyKit has no side-panel surface: the host draws the notch and the
/// shelf, so an edge tab is the droplet's own window, like `TranslationPanel`.
@MainActor
final class SidePanel: NSPanel {
    static let shared = SidePanel()

    /// The edge tab at rest: depth into the screen and height. Both grow by
    /// about a fifth under the pointer, so the grown tab keeps the resting
    /// proportions instead of turning fat.
    static let width: CGFloat = 18
    static let height: CGFloat = 160

    /// The tab under the pointer. The shape scales to this and back.
    static let hoverWidth: CGFloat = 22
    static let hoverHeight: CGFloat = 192

    /// The window keeps a 32pt width so the pointer has a comfortable target;
    /// the shape sits flush with the screen edge inside it. Its size never
    /// changes under the cursor, so the hover cannot flicker.
    static let windowWidth: CGFloat = 32
    static let windowHeight = hoverHeight

    /// The pressed tab is the canvas the translation result will be laid out in,
    /// so it takes the result panel's width. Its height follows the text box;
    /// the extra on each side is the flare that melts each edge-side corner
    /// into the screen edge.
    static let expandedWidth: CGFloat = 460

    /// The largest the card gets: a full box plus its chrome and the grip's
    /// strip. Also the drag clamp, so the card never leaves the screen.
    static var expandedSize: NSSize {
        NSSize(
            width: expandedWidth,
            height: windowHeight(forBody: SidePanelContentView.maxPanelBodyHeight)
        )
    }

    /// The card body plus the two flare radii that melt its top and bottom
    /// corners into the screen edge.
    static func cardHeight(forBody body: CGFloat) -> CGFloat {
        body + SidePanelCardShape.filletRadius * 2
    }

    /// The window that holds a card body of `body`: the card plus the
    /// transparent strip the grip hangs in below it.
    static func windowHeight(forBody body: CGFloat) -> CGFloat {
        cardHeight(forBody: body) + SidePanelContentView.gripStrip
    }

    /// The window is as large as what it draws, so its transparent area never
    /// swallows clicks meant for the app below.
    private static var restingWindowSize: NSSize {
        NSSize(width: windowWidth, height: windowHeight)
    }

    private var dockedScreen: CGRect = .zero
    /// The screen minus the Dock and menu bar; the expanded card stays inside.
    private var dockedWorkArea: CGRect = .zero
    /// The edge the tab and card hang from.
    private(set) var side: SidePanelSide = .right
    private var placed = false
    /// The droplet is on screen: a hidden panel stays hidden.
    private var isActive = false
    private var outsideMonitor: Any?
    private var keyObserver: NSObjectProtocol?
    private var keyGainedObserver: NSObjectProtocol?
    /// The pressed canvas stays up until the user clicks another app.
    fileprivate var isExpanded = false
    /// The card body. The content reports what its text box needs; the window
    /// follows, clamped to the box's own limits.
    private var bodyHeight = SidePanelContentView.panelMinBodyHeight
    /// The body height the card is easing toward; nil once it rests.
    private var bodyHeightTarget: CGFloat?
    private var centreY: CGFloat = 0
    /// The card's top while it is open, fixed when the open begins. A body that
    /// grows while open holds this top, so the fold starts where the card rests
    /// instead of snapping to a new centre.
    private var cardTop: CGFloat?
    private var dragStart: (mouseY: CGFloat, centreY: CGFloat)?
    private let tabView = SidePanelTabView()
    private var model: TranslateModel?
    /// The sliding chip that marks the control under the pointer. The panel
    /// owns it, so it can bloom the chip over a held control.
    private let chip = SidePanelChipState()
    /// The handle's amount, shared with the content so its mark rides the lobe.
    private let grip = SidePanelGripState()
    /// The card's own pin; the menu reads it and the window answers it.
    private let pin = SidePanelPinState()
    /// The glass's active face while a pinned card is not the key window.
    private lazy var keyAppearance = PanelKeyAppearance(panel: self)
    private var content: NSHostingView<AnyView>?
    private var requestCapture: () -> Void = {}
    private var requestSelection: () -> Void = {}
    private var cancelSelection: () -> Void = {}
    private var activation: DroppyPanelActivation?
    /// Watches the pointer's button, so the chip knows a control is held.
    private var pressMonitor: Any?

    // MARK: - Opening and folding

    /// The bloom's length and shape, shared by both surfaces. It leaves the
    /// point at once, runs a twentieth past the card and settles.
    static let bloomDuration: CFTimeInterval = 0.5

    /// The fold's two beats: the card shrinks past the tab, then settles back to
    /// it. Both panels read the total.
    static let foldShrinkDuration: CFTimeInterval = 0.3
    static let foldSettleDuration: CFTimeInterval = 0.2
    static var foldDuration: CFTimeInterval { foldShrinkDuration + foldSettleDuration }

    static func bloomShape(_ phase: CGFloat) -> CGFloat {
        let t = min(max(phase, 0), 1)
        // Ease-out back: fast out of the point, a twentieth past the card, a
        // still end. The back amount is what sets that peak: 1.1655 → 1.05.
        let back: CGFloat = 1.1655
        let u = t - 1
        let value = 1 + (back + 1) * u * u * u + back * u * u
        // The ends are exact, without the back constant's rounding residue:
        // the folded card is 0 and the open one is 1.
        guard t > 0 else { return 0 }
        return t < 1 ? value : 1
    }

    /// The card's share of its size partway through a fold, from the card at 1
    /// to the tab at 0. It never runs above the card: a close that puffed back
    /// out first would read as a hesitation, not a dismissal.
    static func foldShape(_ phase: CGFloat) -> CGFloat {
        let t = min(max(phase, 0), 1)
        // Two beats: the card shrinks past the tab, smaller than it, then eases
        // back up to it. The card leaves at a finite speed and brakes into the
        // turn, so the close answers the click without a jolt at either end.
        if t >= foldTurn {
            let span = 1 - foldTurn
            let u = (t - foldTurn) / span
            return hermite(
                from: -foldSquash,
                to: 1,
                startSlope: 0,
                endSlope: foldStartSlope * span,
                at: u
            )
        }
        let v = t / foldTurn
        return hermite(from: 0, to: -foldSquash, startSlope: 0, endSlope: 0, at: v)
    }

    /// One cubic Hermite from `start` to `end`; the slopes are per unit of `t`.
    private static func hermite(
        from start: CGFloat,
        to end: CGFloat,
        startSlope: CGFloat,
        endSlope: CGFloat,
        at t: CGFloat
    ) -> CGFloat {
        let t2 = t * t
        let t3 = t2 * t
        return (2 * t3 - 3 * t2 + 1) * start
            + (t3 - 2 * t2 + t) * startSlope
            + (-2 * t3 + 3 * t2) * end
            + (t3 - t2) * endSlope
    }

    /// How far the fold takes the tab under its own size, how fast the card
    /// leaves, in reveal per phase, and the turn that joins the two beats. The
    /// fold plays the curve from the card down, so the settle owns the first
    /// slice of the phase and the shrink the rest.
    static let foldSquash: CGFloat = 0.12
    static let foldStartSlope: CGFloat = 2.2
    static var foldTurn: CGFloat { CGFloat(foldSettleDuration / foldDuration) }

    /// The phase whose reveal is `value` under `shape`, so a fold interrupted
    /// by an open (or an open by a fold) carries on from the size it reached
    /// instead of jumping to the other curve's idea of that moment.
    static func phase(for reveal: CGFloat, folding: Bool) -> CGFloat {
        let clamped = min(max(reveal, 0), 1)
        let size = min(max(reveal, -foldSquash), 1)
        if folding {
            // The fold runs past the tab and comes back, so the size picks its
            // own beat: the shrink above zero, the settle below it.
            var low: CGFloat = size < 0 ? 0 : foldTurn
            var high: CGFloat = size < 0 ? foldTurn : 1
            for _ in 0..<20 {
                let mid = (low + high) / 2
                let reaches = size < 0
                    ? foldShape(mid) > size
                    : foldShape(mid) < size
                if reaches { low = mid } else { high = mid }
            }
            return (low + high) / 2
        }
        // bloomShape climbs from 0 to 1 over the first half of the open.
        var low: CGFloat = 0
        var high: CGFloat = 0.5
        for _ in 0..<20 {
            let mid = (low + high) / 2
            if bloomShape(mid) < clamped { low = mid } else { high = mid }
        }
        return (low + high) / 2
    }
    /// The tab's own growth: a 150ms ease-out that answers the pointer, not a
    /// click. The grip leaves first, then the icon arrives.
    private static let hoverDuration: CFTimeInterval = 0.15
    /// The handle's lobe leaves the card's edge in the same beat as the tab's
    /// own growth, so the card and the lobe keep one shape while it moves.
    /// A critically damped spring, so the lobe eases out and settles without a
    /// bounce: the card is one piece, and a piece that snaps looks broken.
    private static let gripSpring = (response: 0.36, damping: 1.0)
    /// The body's own approach: a touch quicker than the content's scale, so
    /// the window's edge never trails the footer while a box grows.
    private static let bodyRate: CGFloat = 14

    /// 0 is the tab, 1 the open card.
    private var reveal: CGFloat = 0
    /// Where the bloom is on its curve, 0 folded and 1 open. The curve is
    /// shared by the open and the fold, so the two beats take the same time.
    private var bloomPhase: CGFloat = 0
    private var revealTarget: CGFloat = 0
    /// 0 is the resting tab, 1 the grown one.
    fileprivate var hoverAmount: CGFloat = 0
    private var hoverTarget: CGFloat = 0
    private var hoverFrom: CGFloat = 0
    private var hoverStart: CFTimeInterval?
    /// 0 is the lobe inside the card, 1 is the lobe hanging out of it.
    fileprivate var gripAmount: CGFloat = 0
    private var gripTarget: CGFloat = 0
    private var gripVelocity: CGFloat = 0
    private var displayLink: CADisplayLink?
    private var lastTick: CFTimeInterval = 0

    /// True while the tab draws the card's silhouette, so the fold back takes
    /// the same path the open took. The card edge and the exit both read this.
    var showsCard: Bool { reveal > 0 }
    var cardReveal: CGFloat { min(max(reveal, 0), 1) }
    var visibleStretch: CGFloat { max(reveal, 1) }
    /// 1 on the resting tab, below 1 while the fold settles out of the squash
    /// it runs past the tab.
    var tabSquash: CGFloat { min(1 + min(reveal, 0), 1) }
    /// The tab's size under the pointer, from the resting tab to the grown one.
    /// The fold lands on this size, so a close that started from a hovered tab
    /// still ends on the tab the user sees.
    var tabWidth: CGFloat {
        Self.width + (Self.hoverWidth - Self.width) * hoverAmount
    }
    var tabHeight: CGFloat {
        Self.height + (Self.hoverHeight - Self.height) * hoverAmount
    }
    /// The card's face, in the tab view's coordinates. Once the card is open
    /// it comes from the body the content is laid out in, not from the window:
    /// AppKit rounds a window frame to whole points, and half a point there
    /// leaves the grip's sides a pixel off the card's edge.
    var faceHeight: CGFloat {
        let windowHeight = reveal >= 1
            ? Self.windowHeight(forBody: bodyHeight)
            : tabView.bounds.height
        return max(windowHeight - visibleGripStrip, 1)
    }

    var visibleGripStrip: CGFloat {
        SidePanelContentView.gripStrip * cardReveal
    }

    private var isMoving: Bool { displayLink != nil }

    private var prefersReducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.restingWindowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        // A panel that waits for a view to need the keyboard swallows the
        // click that would have opened a menu. `canBecomeKey` already keeps the
        // resting tab out, so the expanded card can take the keyboard at once.
        becomesKeyOnlyIfNeeded = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        tabView.panel = self
        contentView = tabView

        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: NSApplication.willResignActiveNotification,
            object: nil
        )
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
    }

    /// Only the expanded canvas takes the keyboard, for its text box.
    override var canBecomeKey: Bool { isExpanded }
    /// `DroppyPanelActivation` makes the panel main; a borderless window that
    /// refuses throws from AppKit, so the flag follows the expanded state.
    override var canBecomeMain: Bool { isExpanded }

    /// A pinned card must keep its clicks while the host masks background
    /// windows: a click-through card cannot be unpinned.
    override var ignoresMouseEvents: Bool {
        get { super.ignoresMouseEvents }
        set {
            super.ignoresMouseEvents = newValue
            guard Self.keepsClicks(isPinned: pin.isPinned, isExpanded: isExpanded) else { return }
            // The host's mask is a window-server flag; a set to false alone
            // leaves the dead one. Push it through one change.
            super.ignoresMouseEvents = true
            super.ignoresMouseEvents = false
        }
    }

    static func keepsClicks(isPinned: Bool, isExpanded: Bool) -> Bool {
        isPinned && isExpanded
    }

    /// A pinned card's first press returns the foreground; the live glass is
    /// already there, but the click has to reach Droppy's window.
    override func sendEvent(_ event: NSEvent) {
        if Self.isPress(event.type),
           Self.takesFocusBack(
               isPinned: pin.isPinned,
               isExpanded: isExpanded,
               appIsActive: NSApp.isActive
           ) {
            takeFocusBack()
        }
        super.sendEvent(event)
    }

    static func isPress(_ type: NSEvent.EventType) -> Bool {
        type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown
    }

    /// A press in the background takes the foreground, so the control under the
    /// pointer is the one the user sees and the keyboard follows the card.
    static func takesFocusBack(
        isPinned: Bool,
        isExpanded: Bool,
        appIsActive: Bool
    ) -> Bool {
        isPinned && isExpanded && !appIsActive
    }

    /// The screen edge, vertical position clamped to the screen. The full frame
    /// is used so the tab sits at the physical edge, not inside the Dock inset.
    static func frame(
        on screen: CGRect,
        originY: CGFloat,
        side: SidePanelSide = .right
    ) -> NSRect {
        let y = min(max(originY, screen.minY), screen.maxY - windowHeight)
        let x = side == .right ? screen.maxX - windowWidth : screen.minX
        return NSRect(
            x: x,
            y: y,
            width: windowWidth,
            height: windowHeight
        )
    }

    /// Moves the edge panel to the other screen edge, keeping its place on screen.
    func setSide(_ side: SidePanelSide) {
        guard side != self.side else { return }
        self.side = side
        guard isActive else { return }
        place()
        layoutContent()
        tabView.needsDisplay = true
    }

    func show(
        model: TranslateModel,
        requestCapture: @escaping () -> Void = {},
        requestSelection: @escaping () -> Void = {},
        cancelSelection: @escaping () -> Void = {},
        on screen: NSScreen? = nil
    ) {
        self.model = model
        self.requestCapture = requestCapture
        self.requestSelection = requestSelection
        self.cancelSelection = cancelSelection
        self.side = model.sidePanelSide
        isActive = true
        // The shelf views bind to whatever model the droplet hands over, so a
        // fresh mount per activation keeps a relaunch from showing a stale one.
        content?.removeFromSuperview()
        content = nil
        guard let screen = screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        dockedScreen = screen.frame
        dockedWorkArea = screen.visibleFrame
        if !placed {
            centreY = screen.frame.midY
            placed = true
        }
        place()
        orderFrontRegardless()
        makeClickable()
    }

    /// Gives the window back its clicks.
    ///
    /// Droppy leaves a droplet's window with its event mask off while the app
    /// runs in the background: the pointer enters the tab, but the click falls
    /// through to the app below and AppKit still reports `ignoresMouseEvents`
    /// as false. A set to false alone changes nothing, so the flag is pushed
    /// through one change; the second call then sends a live mask.
    fileprivate func makeClickable() {
        ignoresMouseEvents = true
        ignoresMouseEvents = false
    }

    /// A pinned card is the one window the user still owns in the background.
    private func keepClickableWhenPinned() {
        guard pin.isPinned, isExpanded else { return }
        makeClickable()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.pin.isPinned, self.isExpanded else { return }
            self.makeClickable()
        }
    }

    /// Folds the card so a window it opens, such as Settings, is not covered.
    func fold() {
        collapse(respectingPin: false)
    }

    func hide() {
        collapse(animated: false, respectingPin: false)
        displayLink?.invalidate()
        displayLink = nil
        hoverTarget = 0
        hoverAmount = 0
        hoverStart = nil
        isActive = false
        tabView.needsDisplay = true
        orderOut(nil)
    }

    // MARK: - Expand

    fileprivate func expand(takingKey: Bool = true) {
        guard !isExpanded else { return }
        isExpanded = true
        setRevealTarget(1)
        showContent()
        if prefersReducedMotion {
            reveal = 1
            bloomPhase = 1
            content?.alphaValue = 1
            place()
        } else {
            startMotion()
        }
        installMonitor()
        installPressMonitor()
        if takingKey { takeKey() }
        // A card revealed by a selection never takes the keyboard, so it must
        // ask for the active glass face itself or macOS frosts it as inactive.
        updateKeyAppearance()
        tabView.needsDisplay = true
    }

    /// The pin belongs to this window, not the model: it keeps the card up
    /// when the user clicks elsewhere.
    private func togglePin() {
        pin.isPinned.toggle()
        if pin.isPinned { keepClickableWhenPinned() }
        updateKeyAppearance()
    }

    /// The press is handled after the foreground returns, so the control under
    /// the pointer is the one the user sees. `takeKey` keeps the return app current.
    private func takeFocusBack() {
        guard !NSApp.isActive else { return }
        takeKey()
    }

    /// Points the bloom at 1 (open) or 0 (folded). A target that flips while
    /// the card is still moving carries on from the size it reached: the open
    /// and the fold are different curves, so the phase is re-read under the
    /// one that takes over.
    private func setRevealTarget(_ target: CGFloat) {
        guard target != revealTarget else { return }
        if bloomPhase != revealTarget {
            bloomPhase = Self.phase(for: reveal, folding: target == 0)
        }
        revealTarget = target
    }

    /// Opens the card with the result in it. The panel is the droplet's own
    /// window, so a result that lands here leaves the keyboard with the app
    /// the user is working in.
    func revealResult() {
        guard isActive, model != nil else { return }
        orderFrontRegardless()
        expand(takingKey: false)
    }

    /// The panel is a launcher window: it needs the keyboard for its text box,
    /// and hands the foreground back when it folds away.
    private func takeKey() {
        let previous = NSWorkspace.shared.frontmostApplication
        makeKeyAndOrderFront(nil)
        activation = DroppyPanelActivation.begin(for: self, returningTo: previous)
        if activation == nil {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showContent() {
        guard let model else { return }
        let hosting: NSHostingView<AnyView>
        if let content {
            hosting = content
        } else {
            hosting = NSHostingView(
                rootView: AnyView(SidePanelContentView(
                    model: model,
                    chip: chip,
                    grip: grip,
                    pin: pin,
                    requestCapture: requestCapture,
                    requestSelection: requestSelection,
                    cancelSelection: cancelSelection,
                    boxFloor: SidePanelContentView.panelBoxFloor,
                    onGripOut: { [weak self] out in self?.setGripOut(out) },
                    onPin: { [weak self] in self?.togglePin() },
                    onBodyHeight: { [weak self] height, animated in
                        Task { @MainActor in
                            self?.applyBodyHeight(height, animated: animated)
                        }
                    }
                )
                .panelGlassLift())
            )
            hosting.appearance = NSAppearance(named: .darkAqua)
            hosting.wantsLayer = true
            // `layoutContent` owns the frame; a flexible mask would let AppKit
            // move the view on every window resize.
            hosting.autoresizingMask = []
            tabView.addSubview(hosting)
            content = hosting
        }
        hosting.isHidden = false
        layoutContent()
        // The first frame must not flash the words inside a still-tiny card.
        hosting.alphaValue = contentFade
    }

    /// Grows or shrinks the card around the text box, keeping the header — and
    /// the line being typed — where the eye left it. Eased on the display
    /// link, so a new line or an opening result box stretches the card instead
    /// of snapping it.
    private func applyBodyHeight(_ height: CGFloat, animated: Bool) {
        let clamped = min(
            max(height, SidePanelContentView.panelMinBodyHeight),
            SidePanelContentView.maxPanelBodyHeight
        )
        guard abs(clamped - (bodyHeightTarget ?? bodyHeight)) > 0.5 else { return }
        // The first layout, a grip drag and Reduce Motion all land at once:
        // the first must not animate in from a stale box, and the drag must
        // track the pointer.
        guard animated, isExpanded, reveal >= 1, !prefersReducedMotion else {
            bodyHeightTarget = nil
            guard abs(clamped - bodyHeight) > 0.5 else { return }
            bodyHeight = clamped
            if isExpanded && !isMoving { place(keepingTop: true) }
            layoutContent()
            return
        }
        bodyHeightTarget = clamped
        startMotion()
    }

    /// The island's own clearance: its 16pt shelf content inset plus the 1.5pt
    /// widget slot, so the card's corners stay concentric with the shell.
    ///
    /// The content hangs off the card's top-right corner, not its top-left: the
    /// window grows out of the screen edge, so the words stay where they will
    /// rest while the card opens around them. A left-anchored view would slide
    /// with the growing edge and read as the text moving, not the panel.
    private func layoutContent() {
        guard let content else { return }
        let inset = SidePanelContentView.inset
        let width = Self.expandedWidth - inset * 2
        // The content hangs from the screen edge, so it stays put while the
        // card grows over it; the free edge is the one that travels.
        content.frame = NSRect(
            x: side == .right ? tabView.bounds.width - inset - width : inset,
            y: SidePanelCardShape.filletRadius + inset,
            width: width,
            height: SidePanelContentView.contentHeight(forBody: bodyHeight)
        )

        let leadingInset = (Self.windowWidth - Self.hoverWidth) * (1 - cardReveal)
        let faceWidth = max(tabView.bounds.width - leadingInset, 1)
        let finalFaceHeight = Self.windowHeight(forBody: bodyHeight) - SidePanelContentView.gripStrip
        // The contents take the card's exact X/Y stretch, including its recoil.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        content.layer?.setAffineTransform(.identity)
        let faceAnchor = content.convert(
            NSPoint(
                x: side == .right ? leadingInset + faceWidth : tabView.bounds.minX,
                y: faceHeight / 2
            ),
            from: tabView
        )
        let transform = CGAffineTransform(translationX: faceAnchor.x, y: faceAnchor.y)
            .scaledBy(x: faceWidth / Self.expandedWidth, y: faceHeight / finalFaceHeight)
            .translatedBy(x: -faceAnchor.x, y: -faceAnchor.y)
        content.layer?.setAffineTransform(transform)
        CATransaction.commit()
    }

    /// The pin is the one thing an outside click or a lost key window cannot
    /// override; an explicit fold or hide passes `respectingPin: false`.
    static func foldsOnDismissal(isPinned: Bool, respectingPin: Bool = true) -> Bool {
        !respectingPin || !isPinned
    }

    private func collapse(animated: Bool = true, respectingPin: Bool = true) {
        guard isExpanded else { return }
        // The pin is a promise: an outside click or a lost key window must not
        // fold the card under it. Only an explicit fold, hide or unpin ends it.
        guard Self.foldsOnDismissal(isPinned: pin.isPinned, respectingPin: respectingPin) else {
            return
        }
        isExpanded = false
        // A closed card opens unpinned, like the floating panel's.
        pin.isPinned = false
        updateKeyAppearance()
        settleTabForFold()
        model?.isToolbarExpanded = false
        chip.pressed = false
        chip.target = nil
        // A fold must not freeze a body stretch half-finished; the next open
        // would size the card to that frame.
        if let target = bodyHeightTarget {
            bodyHeight = target
            bodyHeightTarget = nil
            layoutContent()
        }
        removeMonitor()
        removePressMonitor()
        activation?.finish()
        activation = nil
        setRevealTarget(0)
        tabView.needsDisplay = true
        guard animated, !prefersReducedMotion else {
            reveal = 0
            bloomPhase = 0
            finishFold()
            return
        }
        startMotion()
    }

    /// The tab is hidden under the open card, so a close can drop the hover at
    /// once: the card then morphs into the tab's resting size, not the grown
    /// one, and the two beats are measured against what the user sees after.
    private func settleTabForFold() {
        guard !tabView.pointerIsOnVisibleTab else { return }
        hoverAmount = 0
        hoverTarget = 0
        hoverStart = nil
    }

    /// Puts the window back on the tab once the card has folded away.
    private func finishFold() {
        cardTop = nil
        content?.isHidden = true
        content?.alphaValue = 1
        place()
        // The pointer may have left the tab while the card covered it, and the
        // tracking area cannot report that from under the card.
        hoverTarget = tabView.pointerIsOnVisibleTab ? 1 : 0
        // The lobe goes back into the card with it: the card is not there to
        // hang a handle from.
        if gripAmount > 0 {
            gripTarget = 0
            startMotion()
        }
        if prefersReducedMotion {
            hoverStart = nil
            hoverAmount = hoverTarget
            gripAmount = 0
            gripVelocity = 0
            grip.amount = 0
            tabView.needsDisplay = true
        } else if hoverAmount != hoverTarget {
            hoverFrom = hoverAmount
            hoverStart = CACurrentMediaTime()
            startMotion()
        }
    }

    // MARK: - Background

    @objc private func appWillResignActive() {
        keepClickableWhenPinned()
        updateKeyAppearance()
    }

    @objc private func appDidResignActive() {
        keepClickableWhenPinned()
        updateKeyAppearance()
    }

    @objc private func appDidBecomeActive() {
        updateKeyAppearance()
    }

    /// The card keeps one face while it is open: unpinning must not hand it
    /// back to the system's frosted inactive glass under the pointer.
    private func updateKeyAppearance() {
        keyAppearance.hold(
            PanelKeyAppearance.shouldHold(
                pinned: pin.isPinned,
                shown: isExpanded
            )
        )
    }

    /// A click in another app, or in another window of this one, folds the
    /// canvas back into the tab. The window observer catches the second case,
    /// where no global event reaches the panel.
    private func installMonitor() {
        removeMonitor()
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor in self?.collapse() }
        }
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.collapse()
                self?.updateKeyAppearance()
            }
        }
        keyGainedObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateKeyAppearance() }
        }
    }

    /// The chip dips over the control the pointer holds, so the panel
    /// watches the button itself.
    private func installPressMonitor() {
        removePressMonitor()
        pressMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp]
        ) { [weak self] event in
            let held = event.type == .leftMouseDown
            Task { @MainActor in self?.chip.pressed = held }
            return event
        }
    }

    private func removePressMonitor() {
        if let pressMonitor {
            NSEvent.removeMonitor(pressMonitor)
            self.pressMonitor = nil
        }
    }

    private func removeMonitor() {
        if let outsideMonitor {
            NSEvent.removeMonitor(outsideMonitor)
            self.outsideMonitor = nil
        }
        if let keyObserver {
            NotificationCenter.default.removeObserver(keyObserver)
            self.keyObserver = nil
        }
        if let keyGainedObserver {
            NotificationCenter.default.removeObserver(keyGainedObserver)
            self.keyGainedObserver = nil
        }
    }

    /// Keeps the window centred on the tab. While the content resizes the
    /// expanded card, its top edge stays put so the text does not slide.
    private func place(keepingTop: Bool = false) {
        setFrame(windowFrame(keepingTop: keepingTop), display: false)
        tabView.needsDisplay = true
    }

    /// The window rect for the current state. Between the two ends it travels
    /// from the tab's rect to the card's, so the fold out of the edge and the
    /// fold back are the same path.
    private func windowFrame(keepingTop: Bool = false) -> NSRect {
        let tab = collapsedFrame()
        guard reveal > 0 else { return tab }
        let card = cardFrame(keepingTop: keepingTop)
        guard reveal != 1 else { return card }
        return Self.revealRect(from: tab, to: card, at: reveal, side: side)
    }

    /// The resting tab's window, centred on where the user left the tab.
    private func collapsedFrame() -> NSRect {
        Self.frame(
            on: dockedScreen,
            originY: centreY - Self.windowHeight / 2,
            side: side
        )
    }

    /// The open card, kept inside the screen's work area.
    private func cardFrame(keepingTop: Bool = false) -> NSRect {
        let tabRect = collapsedFrame()
        let size = NSSize(
            width: Self.expandedWidth,
            height: Self.windowHeight(forBody: bodyHeight)
        )
        let top = keepingTop
            ? frame.maxY
            : openTop(tabMidY: tabRect.midY, cardHeight: size.height)
        let y = min(
            max(top - size.height, dockedWorkArea.minY),
            dockedWorkArea.maxY - size.height
        )
        return NSRect(
            x: side == .right ? tabRect.maxX - size.width : tabRect.minX,
            y: y,
            width: size.width,
            height: size.height
        )
    }

    /// The card's top for this open: its middle on the tab's, so the open grows
    /// out of the tab and the fold lands back in it. Computed once per open.
    private func openTop(tabMidY: CGFloat, cardHeight: CGFloat) -> CGFloat {
        if let cardTop { return cardTop }
        let top = Self.expandedTop(tabMidY: tabMidY, cardHeight: cardHeight, workArea: dockedWorkArea)
        cardTop = top
        return top
    }

    // MARK: - Motion

    /// The tab grew under the pointer, or shrank back off it.
    fileprivate func setHover(_ hovering: Bool) {
        guard !showsCard else { return }
        hoverFrom = hoverAmount
        hoverStart = CACurrentMediaTime()
        hoverTarget = hovering ? 1 : 0
        if prefersReducedMotion {
            hoverStart = nil
            hoverAmount = hoverTarget
            tabView.needsDisplay = true
        } else {
            startMotion()
        }
    }

    private func startMotion() {
        guard displayLink == nil else { return }
        lastTick = CACurrentMediaTime()
        let link = tabView.displayLink(target: self, selector: #selector(stepMotion))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// The pointer is on the handle, or a drag holds it: the lobe comes out
    /// of the card's edge. The lobe is part of the card's path, so the card
    /// grows the shape instead of moving a piece of its own.
    fileprivate func setGripOut(_ out: Bool) {
        let target: CGFloat = out ? 1 : 0
        guard target != gripTarget else { return }
        gripTarget = target
        startMotion()
    }

    /// The card's outline moves on the display link, so the lobe's own path
    /// follows the card's edge.
    @objc private func stepMotion(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let dt = max(now - lastTick, 0)
        lastTick = now

        let folding = revealTarget == 0
        let rate = CGFloat(dt) / CGFloat(folding ? Self.foldDuration : Self.bloomDuration)
        bloomPhase = bloomPhase < revealTarget
            ? min(revealTarget, bloomPhase + rate)
            : max(revealTarget, bloomPhase - rate)
        reveal = folding ? Self.foldShape(bloomPhase) : Self.bloomShape(bloomPhase)
        if let start = hoverStart {
            let t = min(max((now - start) / Self.hoverDuration, 0), 1)
            let eased = 1 - pow(1 - t, 3)
            hoverAmount = hoverFrom + (hoverTarget - hoverFrom) * eased
            if t >= 1 {
                hoverAmount = hoverTarget
                hoverStart = nil
            }
        } else {
            hoverAmount = hoverTarget
        }
        // The lobe's amount moves the card's own outline, so the glass keeps
        // one shape and one colour while the handle comes out.
        let gripStep = springStep(
            gripAmount,
            velocity: gripVelocity,
            to: gripTarget,
            spring: Self.gripSpring,
            dt: dt
        )
        gripVelocity = gripStep.velocity
        if gripStep.value != gripAmount {
            gripAmount = gripStep.value
            grip.amount = gripAmount
        }
        // Keep the top pinned on the tick that finishes a body stretch too,
        // or a centred card would re-centre on the tab and jump.
        let bodyWasMoving = bodyHeightTarget != nil
        if let target = bodyHeightTarget {
            bodyHeight = approach(bodyHeight, to: target, rate: Self.bodyRate, dt: dt)
            if bodyHeight == target { bodyHeightTarget = nil }
            layoutContent()
        }
        // While the body stretches, the card's top stays put and its edge
        // travels; the open and fold paths keep their own interpolated top.
        place(keepingTop: bodyHeightTarget != nil || bodyWasMoving)
        // The card grows out of the edge under a still frame of content, so the
        // hosting view must follow the edge it hangs from on every tick.
        layoutContent()
        // The words come in once the card is nearly out, and leave before it
        // starts to shrink: content shown inside a half-sized window is clipped
        // and reads as the panel tearing, not opening.
        content?.alphaValue = contentFade
        tabView.needsDisplay = true

        guard bloomPhase == revealTarget,
            hoverAmount == hoverTarget,
            gripAmount == gripTarget,
            bodyHeightTarget == nil else { return }
        displayLink?.invalidate()
        displayLink = nil
        if revealTarget == 0 { finishFold() }
    }

    /// One frame of a damped spring, solved analytically so its path does not
    /// depend on the display's refresh rate. Velocity survives a mid-flight retarget.
    func springStep(
        _ value: CGFloat,
        velocity: CGFloat,
        to target: CGFloat,
        spring: (response: Double, damping: Double),
        dt: CFTimeInterval
    ) -> (value: CGFloat, velocity: CGFloat) {
        let displacement = value - target
        let frequency = 2 * CGFloat.pi / CGFloat(spring.response)
        let damping = CGFloat(spring.damping)
        let time = CGFloat(dt)
        let next: CGFloat
        let nextVelocity: CGFloat

        if abs(damping - 1) < 0.0001 {
            let decay = exp(-frequency * time)
            let coefficient = velocity + frequency * displacement
            next = target + (displacement + coefficient * time) * decay
            nextVelocity = (velocity - frequency * coefficient * time) * decay
        } else if damping < 1 {
            let decay = exp(-damping * frequency * time)
            let dampedFrequency = frequency * sqrt(1 - damping * damping)
            let phase = dampedFrequency * time
            let coefficient = (velocity + damping * frequency * displacement) / dampedFrequency
            next = target + decay * (
                displacement * cos(phase) + coefficient * sin(phase)
            )
            nextVelocity = decay * (
                velocity * cos(phase)
                    - (damping * frequency * velocity + frequency * frequency * displacement)
                    / dampedFrequency * sin(phase)
            )
        } else {
            let root = sqrt(damping * damping - 1)
            let slowRate = -frequency * (damping - root)
            let fastRate = -frequency * (damping + root)
            let fastCoefficient = (velocity - slowRate * displacement) / (fastRate - slowRate)
            let slowCoefficient = displacement - fastCoefficient
            let slowDecay = exp(slowRate * time)
            let fastDecay = exp(fastRate * time)
            next = target + slowCoefficient * slowDecay + fastCoefficient * fastDecay
            nextVelocity = slowCoefficient * slowRate * slowDecay
                + fastCoefficient * fastRate * fastDecay
        }

        if abs(target - next) < 0.002, abs(nextVelocity) < 0.01 {
            return (target, 0)
        }
        return (next, nextVelocity)
    }

    /// The frames an open plays, sampled at even steps. The fold has its own
    /// curve and its own length, sampled by `foldSamples`.
    static func revealSamples(frames: Int = 40) -> [CGFloat] {
        let steps = max(frames, 2)
        return (0...steps).map { bloomShape(CGFloat($0) / CGFloat(steps)) }
    }

    /// The frames a fold plays, from the card at full size to the tab.
    static func foldSamples(frames: Int = 40) -> [CGFloat] {
        let steps = max(frames, 2)
        return (0...steps).map { foldShape(1 - CGFloat($0) / CGFloat(steps)) }
    }

    /// One frame of an exponential approach, snapped once it cannot be seen.
    private func approach(
        _ value: CGFloat,
        to target: CGFloat,
        rate: CGFloat,
        dt: CFTimeInterval
    ) -> CGFloat {
        let next = value + (target - value) * (1 - exp(-rate * CGFloat(dt)))
        return abs(target - next) < 0.002 ? target : next
    }

    /// One reveal-driven fade in both directions: reversing mid-flight cannot
    /// jump between separate opening and folding opacity curves.
    private var contentFade: CGFloat {
        smoothstep(from: 0.45, to: 0.9)
    }

    private func smoothstep(from: CGFloat, to: CGFloat) -> CGFloat {
        let t = min(max((reveal - from) / (to - from), 0), 1)
        return t * t * (3 - 2 * t)
    }

    private func lerp(_ from: CGFloat, _ to: CGFloat, _ t: CGFloat) -> CGFloat {
        from + (to - from) * t
    }

    /// The window rect partway through an open. The face it draws is what
    /// travels — the tab's box at 0, the card's at 1 — so both ends share a
    /// middle. The grip strip grows below the face and never takes part in the
    /// centring; lerping the window instead lifts the face by half the strip.
    static func revealRect(
        from tab: NSRect,
        to card: NSRect,
        at reveal: CGFloat,
        side: SidePanelSide = .right
    ) -> NSRect {
        let fullStrip = SidePanelContentView.gripStrip
        if reveal > 1 {
            let faceHeight = (card.height - fullStrip) * reveal
            let faceMidY = card.maxY - (card.height - fullStrip) / 2
            let width = card.width * reveal
            return NSRect(
                x: side == .right ? card.maxX - width : card.minX,
                y: faceMidY - faceHeight / 2 - fullStrip,
                width: width,
                height: faceHeight + fullStrip
            )
        }
        let strip = fullStrip * min(max(reveal, 0), 1)
        let faceHeight = tab.height + (card.height - fullStrip - tab.height) * reveal
        let faceMidY = tab.midY
            + (card.maxY - (card.height - fullStrip) / 2 - tab.midY) * reveal
        let width = tab.width + (card.width - tab.width) * reveal
        return NSRect(
            x: side == .right ? card.maxX - width : card.minX,
            y: faceMidY - faceHeight / 2 - strip,
            width: width,
            height: faceHeight + strip
        )
    }

    /// The top edge the expanded card opens at: the face's middle sits on the
    /// tab's, so the open grows out of the tab and the fold lands back in it.
    /// The clamp only bites when the tab is near the top or bottom edge.
    static func expandedTop(tabMidY: CGFloat, cardHeight: CGFloat, workArea: CGRect) -> CGFloat {
        let centred = tabMidY + (cardHeight - SidePanelContentView.gripStrip) / 2
        return min(max(centred, workArea.minY + cardHeight), workArea.maxY)
    }

    /// The card's top a drag asked for, kept inside the work area. The inverse
    /// of `expandedTop`.
    static func draggedTop(to top: CGFloat, cardHeight: CGFloat, workArea: CGRect) -> CGFloat {
        min(max(top, workArea.minY + cardHeight), workArea.maxY)
    }

    /// The tab's resting centre for a card whose top is `top`: the middle of the
    /// card's face, so folding lands the tab where the card was.
    static func tabCentre(forCardTop top: CGFloat, cardHeight: CGFloat) -> CGFloat {
        top - (cardHeight - SidePanelContentView.gripStrip) / 2
    }

    // MARK: - Vertical drag

    fileprivate func beginDrag() {
        dragStart = (NSEvent.mouseLocation.y, cardFaceCentre)
    }

    /// The middle of the card's face: the tab's own centre at rest, the open
    /// card's face centre while it is out, so the fold lands the tab there.
    private var cardFaceCentre: CGFloat {
        guard isExpanded, let cardTop else { return centreY }
        return Self.tabCentre(
            forCardTop: cardTop,
            cardHeight: Self.windowHeight(forBody: bodyHeight)
        )
    }

    fileprivate func drag() {
        guard let dragStart, dockedScreen != .zero else { return }
        let moved = dragStart.centreY + (NSEvent.mouseLocation.y - dragStart.mouseY)
        if isExpanded {
            // The open card is pinned to `cardTop`; the drag moves the pin, so
            // the whole face follows the pointer instead of sitting still.
            let height = Self.windowHeight(forBody: bodyHeight)
            let top = Self.draggedTop(
                to: moved + (height - SidePanelContentView.gripStrip) / 2,
                cardHeight: height,
                workArea: dockedWorkArea
            )
            cardTop = top
            centreY = Self.tabCentre(forCardTop: top, cardHeight: height)
        } else {
            // Keep the whole expanded canvas on the screen, not only the thin tab.
            let limit = max(Self.windowHeight, Self.expandedSize.height) / 2
            centreY = min(max(moved, dockedScreen.minY + limit), dockedScreen.maxY - limit)
        }
        place()
    }

    fileprivate func endDrag() {
        dragStart = nil
    }
}

/// The card's surface layer, under the card's marks and over its black.
///
/// The layer is a material that covers the whole window, so it must never
/// take a click: the grip and the card's own controls are above it, and the
/// rest of the panel has to keep receiving the mouse.
@MainActor
final class SidePanelGlassHost: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The visible tab. It owns the mouse so the panel can move only up and down:
/// the horizontal origin always comes from the docked screen.
@MainActor
final class SidePanelTabView: NSView {
    weak var panel: SidePanel?

    /// A render test cannot reach the panel's live hover, so it seeds the
    /// amount the tab has grown.
    var renderHover: CGFloat?

    private var tracking: NSTrackingArea?

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var hover: CGFloat {
        min(max(renderHover ?? panel?.hoverAmount ?? 0, 0), 1)
    }

    /// The amount the tab has grown, for the ink layer above the glass.
    fileprivate var inkHover: CGFloat { hover }

    /// The whole window is the hit area. It is the grown tab's size, so the
    /// pointer enters and leaves the same rect and the hover cannot flicker.
    private var restingRect: NSRect { bounds }

    /// The glass layer's shape. The surface is masked to it, so the material
    /// never spills past the card's edge.
    let surfaceState = SidePanelSurfaceState()
    /// The card's surface layer, under the card's marks and over its black.
    private var glassHost: SidePanelGlassHost?
    /// The tab's own marks, above the glass: a black surface would swallow
    /// them otherwise.
    private let inkView = SidePanelTabInkView()
    /// The shape the glass was last masked to, so it is published only when
    /// the card has actually moved.
    private var publishedShape: (reveal: CGFloat, stretch: CGFloat, hover: CGFloat, grip: CGFloat, height: CGFloat, squash: CGFloat, side: SidePanelSide)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let glass = SidePanelGlassHost()
        glass.autoresizingMask = [.width, .height]
        addSubview(glass)
        glassHost = glass
        let surface = NSHostingView(rootView: SidePanelSurfaceLayer(state: surfaceState))
        surface.appearance = NSAppearance(named: .darkAqua)
        surface.autoresizingMask = [.width, .height]
        glass.addSubview(surface)
        addSubview(inkView)
        inkView.tab = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        glassHost?.frame = bounds
        glassHost?.subviews.first?.frame = bounds
        inkView.frame = bounds
        publishSilhouette()
    }

    override var needsDisplay: Bool {
        get { super.needsDisplay }
        set {
            super.needsDisplay = newValue
            if newValue {
                inkView.needsDisplay = true
                publishSilhouette()
            }
        }
    }

    override func setNeedsDisplay(_ dirtyRect: NSRect) {
        super.setNeedsDisplay(dirtyRect)
        inkView.needsDisplay = true
        publishSilhouette()
    }

    /// Hands the glass layer the card's outline. The shape is the same one the
    /// card is filled with, so the material and the card always agree.
    private func publishSilhouette() {
        let inputs = (
            reveal: panel?.cardReveal ?? 0,
            stretch: panel?.visibleStretch ?? 1,
            hover: hover,
            grip: panel?.gripAmount ?? 0,
            height: panel?.faceHeight ?? 0,
            squash: panel?.tabSquash ?? 1,
            side: panel?.side ?? .right
        )
        if let published = publishedShape,
           published.reveal == inputs.reveal,
           published.stretch == inputs.stretch,
           published.hover == inputs.hover,
           published.grip == inputs.grip,
           published.height == inputs.height,
           published.squash == inputs.squash,
           published.side == inputs.side {
            return
        }
        publishedShape = inputs
        surfaceState.mirrored = inputs.side == .left
        surfaceState.silhouette = silhouettePath()
    }

    /// The card's outline with the handle's lobe under it, as one path.
    ///
    /// The card, the two fillets that run with the screen's edge and the lobe
    /// under the card are one outline, so the card's surface covers all of it
    /// in a single layer and no seam can show between the pieces.
    func silhouettePath() -> Path {
        let path: Path
        if let panel, panel.showsCard {
            path = SidePanelUnifiedShape(
                reveal: panel.cardReveal,
                stretch: panel.visibleStretch,
                gripAmount: panel.gripAmount,
                tabHeight: panel.tabHeight
            )
            .path(in: shapeCardRect)
        } else {
            path = SidePanelTabShape().path(in: shapeTabRect)
        }
        guard panel?.side == .left else { return path }
        // The card is drawn on the right edge; mirroring the path puts the
        // screen-edge fillets on the left without a second geometry.
        return path.applying(
            CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: bounds.minX + bounds.maxX, ty: 0)
        )
    }

    /// The card's face in the tab view's coordinates, before the mirror.
    private var shapeCardRect: NSRect {
        // The hit window starts wider than the tab; the face catches up with
        // the tab's current size as the same silhouette morphs into the card.
        let tabWidth = panel?.tabWidth ?? SidePanel.hoverWidth
        let leadingInset = (SidePanel.windowWidth - tabWidth) * (1 - (panel?.cardReveal ?? 0))
        return NSRect(
            x: bounds.minX + leadingInset,
            y: bounds.minY,
            width: bounds.width - leadingInset,
            height: panel?.faceHeight ?? 0
        )
    }

    /// The tab from its resting size to its grown one, flush with the screen
    /// edge and centred on the tab's own middle.
    fileprivate var tabRect: NSRect {
        let squash = panel?.tabSquash ?? 1
        let w = (SidePanel.width + (SidePanel.hoverWidth - SidePanel.width) * hover) * squash
        let h = (SidePanel.height + (SidePanel.hoverHeight - SidePanel.height) * hover) * squash
        let x = panel?.side == .left ? bounds.minX : bounds.maxX - w
        return NSRect(
            x: x,
            y: bounds.midY - h / 2,
            width: w,
            height: h
        )
    }

    /// The tab's rect before the mirror, always on the right edge.
    private var shapeTabRect: NSRect {
        let squash = panel?.tabSquash ?? 1
        let w = (SidePanel.width + (SidePanel.hoverWidth - SidePanel.width) * hover) * squash
        let h = (SidePanel.height + (SidePanel.hoverHeight - SidePanel.height) * hover) * squash
        return NSRect(
            x: bounds.maxX - w,
            y: bounds.midY - h / 2,
            width: w,
            height: h
        )
    }

    // The card has no fill of its own: the surface is the one layer over the
    // whole outline, so the colour is the app's theme and not ours.

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Expanded, the content lives here and must take its own clicks.
        if panel?.isExpanded == true {
            return super.hitTest(point)
        }
        let local = convert(point, from: superview)
        return restingRect.contains(local) ? self : nil
    }

    override func resetCursorRects() {
        addCursorRect(restingRect, cursor: .openHand)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }
        let area = NSTrackingArea(
            rect: restingRect,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        // The host can put the flag back while the pointer is away; the
        // tracking area still reports the enter, so the click lands.
        panel?.makeClickable()
        panel?.setHover(true)
    }

    /// Whether the pointer sits on the tab right now. The tracking area cannot
    /// answer this while the card covers the tab.
    var pointerIsOnTab: Bool {
        guard let window else { return false }
        let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        return restingRect.contains(point)
    }

    /// Whether the pointer sits on the visible tab, not on the hit window the
    /// open card fills.
    var pointerIsOnVisibleTab: Bool {
        guard let window else { return false }
        let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        return tabRect.contains(point)
    }

    override func mouseExited(with event: NSEvent) {
        panel?.setHover(false)
    }

    override func mouseDown(with event: NSEvent) {
        panel?.expand()
        NSCursor.closedHand.set()
        panel?.beginDrag()
    }

    override func mouseDragged(with event: NSEvent) {
        panel?.drag()
    }

    override func mouseUp(with event: NSEvent) {
        NSCursor.openHand.set()
        panel?.endDrag()
    }
}

/// The tab's own marks: the grip that moves the panel and the chevron that
/// says where the click opens.
///
/// They live above the glass, because the surface is opaque under a black
/// theme and would swallow anything drawn under it.
@MainActor
final class SidePanelTabInkView: NSView {
    weak var tab: SidePanelTabView?

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let tab, tab.panel?.showsCard != true else { return }
        let rect = tab.tabRect
        let hover = tab.inkHover

        // The grip leaves before the chevron arrives, so the hover never shows
        // both marks at once: the pointer gets one in a 150ms answer.
        let gripAlpha = (1 - Self.smoothstep(from: 0, to: 0.45, hover)) * 0.85
        if gripAlpha > 0.001 {
            Self.gripColor.withAlphaComponent(gripAlpha).setFill()
            let bar = NSRect(
                x: rect.midX - 1.5,
                y: rect.midY - 13,
                width: 3,
                height: 26
            )
            NSBezierPath(
                roundedRect: bar,
                xRadius: 1.5,
                yRadius: 1.5
            ).fill()
        }

        let markAlpha = Self.smoothstep(from: 0.45, to: 1, hover) * 0.85
        if markAlpha > 0.001 {
            self.drawChevron(in: rect, alpha: markAlpha)
        }
    }

    private func drawChevron(in rect: NSRect, alpha: CGFloat) {
        // Into the screen: the chevron points at the page the click uncovers.
        let left = tab?.panel?.side == .left
        let tipX = rect.midX + (left ? 1.75 : -1.75)
        let baseX = rect.midX + (left ? -1.75 : 1.75)
        let y = rect.midY
        let chevron = NSBezierPath()
        chevron.move(to: NSPoint(x: baseX, y: y - 4.5))
        chevron.line(to: NSPoint(x: tipX, y: y))
        chevron.line(to: NSPoint(x: baseX, y: y + 4.5))
        chevron.lineWidth = 1.5
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        NSColor(AdaptiveColors.notchSurfacePrimaryText).withAlphaComponent(0.65 * alpha).setStroke()
        chevron.stroke()
    }

    /// The mark's ink, from the host's own ladder: white on a dark surface.
    private static let gripColor = NSColor(AdaptiveColors.notchSurfaceTertiaryText)
    private static func smoothstep(from: CGFloat, to: CGFloat, _ value: CGFloat) -> CGFloat {
        let t = min(max((value - from) / (to - from), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

/// The expanded canvas. Left corners round inward; the two corners on the
/// screen edge are concave fillets that run smooth with the edge, so the panel
/// reads as one piece with the side of the screen.
struct SidePanelCardShape: Shape {
    static let radius = DroppyShellMetrics.expandedIslandCornerRadius
    static let filletRadius: CGFloat = 32

    var cornerRadius = radius
    var fillet = filletRadius

    func path(in rect: CGRect) -> Path {
        // Clamp the fillet before finding the body, or a narrow morph leaves
        // its lower screen-edge corner short of the rect.
        let f = min(fillet, rect.width / 2, rect.height / 2)
        let body = max(0, rect.height - f * 2)
        let r = min(cornerRadius, rect.width / 2, body / 2)
        let k = r * 0.5523
        let fk = f * 0.5523
        let top = rect.minY + f
        let bottom = top + body
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + r, y: top))
        path.addLine(to: CGPoint(x: rect.maxX - f, y: top))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: top - f),
            control1: CGPoint(x: rect.maxX - f + fk, y: top),
            control2: CGPoint(x: rect.maxX, y: top - f + fk)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: bottom + f))
        path.addCurve(
            to: CGPoint(x: rect.maxX - f, y: bottom),
            control1: CGPoint(x: rect.maxX, y: bottom + f - fk),
            control2: CGPoint(x: rect.maxX - f + fk, y: bottom)
        )
        path.addLine(to: CGPoint(x: rect.minX + r, y: bottom))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: bottom - r),
            control1: CGPoint(x: rect.minX + r - k, y: bottom),
            control2: CGPoint(x: rect.minX, y: bottom - r + k)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: top + r))
        path.addCurve(
            to: CGPoint(x: rect.minX + r, y: top),
            control1: CGPoint(x: rect.minX, y: top + r - k),
            control2: CGPoint(x: rect.minX + r - k, y: top)
        )
        path.closeSubpath()
        return path
    }
}


/// The card's outline with the handle's lobe under it, as one path.
///
/// The card, the two fillets that run with the screen's edge and the lobe
/// under the card are one outline. The card's surface covers all of it in a
/// single layer, so no seam can show between the pieces and the colour is the
/// app's theme rather than ours.
struct SidePanelUnifiedShape: Shape {
    var reveal: CGFloat
    var stretch: CGFloat = 1
    /// 0 is the lobe inside the card, 1 is the lobe hanging out of it.
    var gripAmount: CGFloat = 0
    /// The tab's height inside the rect; the card fills the rect.
    var tabHeight: CGFloat?

    func path(in rect: CGRect) -> Path {
        let card = SidePanelMorphShape(
            reveal: reveal,
            stretch: stretch,
            tabHeight: tabHeight
        )
        .path(in: rect)
        guard let lobe = Self.lobe(in: rect, amount: gripAmount) else { return card }
        // A second subpath would stroke its own top edge inside the card and
        // read as a piece stacked on it; the union keeps one outline.
        return Path(card.cgPath.union(lobe.cgPath, using: .winding))
    }

    /// The lobe's outline, hanging under the card's bottom edge.
    ///
    /// It is the collapsed tab's silhouette laid on its side. At rest it sits
    /// inside the card, so the card's own outline is all that shows; the
    /// pointer brings it out.
    static func lobe(in card: CGRect, amount: CGFloat) -> Path? {
        guard amount > 0.001 else { return nil }
        let flatBottom = card.maxY - SidePanelCardShape.filletRadius
        let out = SidePanelContentView.gripCurveDepth - SidePanelContentView.gripOverlap
        let bottom = flatBottom + out - SidePanelContentView.gripRise * (1 - amount)
        return SidePanelGripShape(stem: SidePanelContentView.gripTuck).path(
            in: CGRect(
                x: card.midX - SidePanelContentView.gripWidth / 2,
                y: bottom - SidePanelContentView.gripDepth,
                width: SidePanelContentView.gripWidth,
                height: SidePanelContentView.gripDepth
            )
        )
    }
}

/// One continuous outline from the tab to the card; both ends keep their exact paths.
struct SidePanelMorphShape: Shape {
    var reveal: CGFloat
    var stretch: CGFloat = 1
    /// The tab's height inside the rect; the card fills the rect. Nil keeps
    /// the tab on the whole rect, which is the open's starting frame.
    var tabHeight: CGFloat?

    func path(in rect: CGRect) -> Path {
        let amount = min(max(reveal, 0), 1)
        let stretch = max(stretch, 1)
        let baseRect = stretch > 1
            ? CGRect(
                x: rect.maxX - rect.width / stretch,
                y: rect.midY - rect.height / stretch / 2,
                width: rect.width / stretch,
                height: rect.height / stretch
            )
            : rect
        let tabRect = tabHeight.map { height in
            let h = min(max(height / stretch, 0), baseRect.height)
            return CGRect(
                x: baseRect.minX,
                y: baseRect.midY - h / 2,
                width: baseRect.width,
                height: h
            )
        } ?? baseRect
        let curves = zip(tabSegments(in: tabRect), cardSegments(in: baseRect)).map {
            $0.mixed(to: $1, amount: amount)
        }
        var path = Path()
        guard let first = curves.first else { return path }
        path.move(to: first.p0)
        for curve in curves {
            path.addCurve(to: curve.p3, control1: curve.p1, control2: curve.p2)
        }
        path.closeSubpath()
        guard stretch > 1 else { return path }
        let transform = CGAffineTransform(translationX: rect.maxX, y: rect.midY)
            .scaledBy(x: stretch, y: stretch)
            .translatedBy(x: -rect.maxX, y: -rect.midY)
        return path.applying(transform)
    }

    private func tabSegments(in rect: CGRect) -> [Cubic] {
        let corners = SidePanelTabShape.corners(in: rect)
        let topParts = corners.top.split()
        let bottomParts = corners.bottom.split()
        let bottomTail = bottomParts.second.split()
        let face = Cubic.line(from: corners.top.p3, to: corners.bottom.p0).split()
        return [
            topParts.first, topParts.second,
            face.first, face.second,
            bottomParts.first, bottomTail.first, bottomTail.second,
            .line(from: corners.bottom.p3, to: corners.top.p0)
        ]
    }

    private func cardSegments(in rect: CGRect) -> [Cubic] {
        let fillet = SidePanelCardShape.filletRadius
        let edgeFillet = min(fillet, rect.width / 2, rect.height / 2)
        let body = max(0, rect.height - edgeFillet * 2)
        let radius = min(SidePanelCardShape.radius, rect.width / 2, body / 2)
        let radiusControl = radius * 0.5523
        let filletControl = edgeFillet * 0.5523
        let top = rect.minY + edgeFillet
        let bottom = top + body

        let start = CGPoint(x: rect.maxX, y: rect.minY)
        let topRight = CGPoint(x: rect.maxX - edgeFillet, y: top)
        let topLeft = CGPoint(x: rect.minX + radius, y: top)
        let upperLeft = CGPoint(x: rect.minX, y: top + radius)
        let lowerLeft = CGPoint(x: rect.minX, y: bottom - radius)
        let bottomLeft = CGPoint(x: rect.minX + radius, y: bottom)
        let bottomRight = CGPoint(x: rect.maxX - edgeFillet, y: bottom)
        let lowerRight = CGPoint(x: rect.maxX, y: bottom + edgeFillet)

        return [
            Cubic(
                p0: start,
                p1: CGPoint(x: rect.maxX, y: top - edgeFillet + filletControl),
                p2: CGPoint(x: rect.maxX - edgeFillet + filletControl, y: top),
                p3: topRight
            ),
            .line(from: topRight, to: topLeft),
            Cubic(
                p0: topLeft,
                p1: CGPoint(x: rect.minX + radius - radiusControl, y: top),
                p2: CGPoint(x: rect.minX, y: top + radius - radiusControl),
                p3: upperLeft
            ),
            .line(from: upperLeft, to: lowerLeft),
            Cubic(
                p0: lowerLeft,
                p1: CGPoint(x: rect.minX, y: bottom - radius + radiusControl),
                p2: CGPoint(x: rect.minX + radius - radiusControl, y: bottom),
                p3: bottomLeft
            ),
            .line(from: bottomLeft, to: bottomRight),
            Cubic(
                p0: bottomRight,
                p1: CGPoint(x: rect.maxX - edgeFillet + filletControl, y: bottom),
                p2: CGPoint(x: rect.maxX, y: bottom + edgeFillet - filletControl),
                p3: lowerRight
            ),
            .line(from: lowerRight, to: start)
        ]
    }

}

/// One cubic segment of an outline, shared by the tab and the morph that grows
/// out of it.
struct Cubic {
    var p0, p1, p2, p3: CGPoint

    static func line(from start: CGPoint, to end: CGPoint) -> Cubic {
        Cubic(
            p0: start,
            p1: CGPoint(x: start.x + (end.x - start.x) / 3, y: start.y + (end.y - start.y) / 3),
            p2: CGPoint(x: start.x + (end.x - start.x) * 2 / 3, y: start.y + (end.y - start.y) * 2 / 3),
            p3: end
        )
    }

    func split() -> (first: Cubic, second: Cubic) {
        let p01 = Self.midpoint(p0, p1)
        let p12 = Self.midpoint(p1, p2)
        let p23 = Self.midpoint(p2, p3)
        let p012 = Self.midpoint(p01, p12)
        let p123 = Self.midpoint(p12, p23)
        let middle = Self.midpoint(p012, p123)
        return (
            Cubic(p0: p0, p1: p01, p2: p012, p3: middle),
            Cubic(p0: middle, p1: p123, p2: p23, p3: p3)
        )
    }

    func mixed(to other: Cubic, amount: CGFloat) -> Cubic {
        Cubic(
            p0: Self.mix(p0, other.p0, amount),
            p1: Self.mix(p1, other.p1, amount),
            p2: Self.mix(p2, other.p2, amount),
            p3: Self.mix(p3, other.p3, amount)
        )
    }

    private static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    private static func mix(_ a: CGPoint, _ b: CGPoint, _ amount: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * amount, y: a.y + (b.y - a.y) * amount)
    }
}

/// The collapsed tab, from the reference vector: it runs almost straight down
/// the screen edge, turns in one tight corner, holds a straight face, then the
/// same mirrored. The path is authored at 30 x 160 and scales to whatever rect
/// it gets.
struct SidePanelTabShape: Shape {
    static let referenceWidth: CGFloat = 30
    static let referenceHeight: CGFloat = 160
    /// How far down the face each corner runs, and where its two control
    /// points sit along the sweep and across the depth.
    static let sweep: CGFloat = 48
    static let downControl: CGFloat = 0.65
    static let upControl: CGFloat = 0.35
    static let outControl: CGFloat = 1

    /// The tab's edge in its own 30 x 160 face, from where the top corner
    /// leaves the screen edge to where the bottom one reaches it. The morph and
    /// the handle read these, so the card grows out of the tab it draws.
    static func corners(in rect: CGRect) -> (top: Cubic, bottom: Cubic) {
        (
            Cubic(
                p0: point(referenceWidth, 0, in: rect),
                p1: point(referenceWidth, sweep * downControl, in: rect),
                p2: point(referenceWidth * (1 - outControl), sweep * upControl, in: rect),
                p3: point(0, sweep, in: rect)
            ),
            Cubic(
                p0: point(0, referenceHeight - sweep, in: rect),
                p1: point(referenceWidth * (1 - outControl), referenceHeight - sweep * upControl, in: rect),
                p2: point(referenceWidth, referenceHeight - sweep * downControl, in: rect),
                p3: point(referenceWidth, referenceHeight, in: rect)
            )
        )
    }

    func path(in rect: CGRect) -> Path {
        let corners = Self.corners(in: rect)
        var path = Path()
        path.move(to: corners.top.p0)
        path.addCurve(to: corners.top.p3, control1: corners.top.p1, control2: corners.top.p2)
        path.addLine(to: corners.bottom.p0)
        path.addCurve(to: corners.bottom.p3, control1: corners.bottom.p1, control2: corners.bottom.p2)
        path.closeSubpath()
        return path
    }

    static func point(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + x / referenceWidth * rect.width,
            y: rect.minY + y / referenceHeight * rect.height
        )
    }
}

/// The drag handle under the card: the collapsed tab's silhouette laid on its
/// side, so the flat edge faces the card and the curve hangs below. The ends
/// taper the way the tab's tips do, at the handle's own slim scale.
///
/// `stem` is a straight extension above the curve. The card buries it, so the
/// curve starts exactly on the card's edge and reads as one piece with it.
struct SidePanelGripShape: Shape {
    var stem: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let curveHeight = max(rect.height - stem, 1)
        let width = SidePanelTabShape.referenceWidth
        let height = SidePanelTabShape.referenceHeight
        let sweep = SidePanelTabShape.sweep
        let down = sweep * SidePanelTabShape.downControl
        var path = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: rect.minX + y / height * rect.width,
                y: rect.minY + stem + (width - x) / width * curveHeight
            )
        }
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: point(width, 0))
        path.addCurve(
            to: point(0, sweep),
            control1: point(width, down),
            control2: point(width * (1 - SidePanelTabShape.outControl), sweep * SidePanelTabShape.upControl)
        )
        path.addLine(to: point(0, height - sweep))
        path.addCurve(
            to: point(width, height),
            control1: point(width * (1 - SidePanelTabShape.outControl), height - sweep * SidePanelTabShape.upControl),
            control2: point(width, height - down)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
