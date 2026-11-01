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
                backdrop: .windowSurface,
                onCopy: { onCopy(translated) },
                onClose: { [weak self] in self?.closePanel() },
                onPin: { [weak self] in self?.togglePin() },
                requestCapture: requestCapture,
                requestSelection: requestSelection,
                cancelSelection: cancelSelection
            )),
            width: width,
            height: ResultWindowView.cardHeight(
                forWidth: width,
                translated: translated,
                source: source,
                showsOriginal: showsOriginal
            ),
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
                backdrop: .windowSurface,
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

        // The card's surface sits in its own layer, as it does under the edge
        // panel's content, so the bloom scales it with the boxes and the tiles
        // sit on the themed glass instead of on the window's black.
        let surface = NSHostingView(rootView: PanelSurfaceLayer())
        surface.appearance = NSAppearance(named: .darkAqua)
        surface.autoresizingMask = [.width, .height]
        surface.frame = hosting.bounds
        let glass = PanelSurfaceHost(frame: hosting.bounds)
        glass.addSubview(surface)

        let card = PanelCardView(frame: hosting.frame)
        card.wantsLayer = true
        card.addSubview(glass)
        card.addSubview(hosting)
        self.cardView = card
        // The window manages its content view's frame, so the card lives in a
        // plain container: only the container follows the window, and the card
        // keeps its full size and is scaled inside it.
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
                ResultWindowView.maximumHeight,
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
        updateKeyAppearance()
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
}

// MARK: - Content

private let panelRadius: CGFloat = 44

private let panelTileRadius: CGFloat = 29

private let panelInset = DroppySpacing.lg

/// What the panel's tiles sit on.
///
/// The live panel sits on the host's own surface for the theme in Droppy
/// (`SidePanelCardSurface`), the same card the shelf and the edge panel wear.
/// The settings picture puts that surface over the droplet's black, so a glass
/// theme melts from black the way it does on the desktop, instead of melting
/// into the settings page behind it.
enum PanelBackdrop {
    /// The surface is drawn in the view, as in the settings picture.
    case hostGlass
    /// The surface is drawn over the droplet's black.
    case hostGlassOnBlack
    /// The window draws the surface in its own layer behind the content, as
    /// the edge panel does, so the card's themed glass stays one layer under
    /// the boxes and the bloom scales it with the content.
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
        case .hostGlassOnBlack:
            shape
                .fill(.black)
                .overlay { SidePanelCardSurface(shape: shape) }
        case .windowSurface:
            Color.clear
        }
    }
}

/// The card's glass, drawn in its own AppKit layer under the panel's content.
///
/// `NSHostingView` keeps the surface out of the content's SwiftUI tree, the
/// same way the edge panel's `SidePanelGlassHost` does, so the card is one
/// layer under the boxes.
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
    static let footerHeight = PanelFooterMetrics.footerHeight
    /// The card's floor is the shelf's opening card: the more menu opens
    /// upward in one column, and a shorter card would cut the menu's top row
    /// on its own rim.
    static let minimumHeight: CGFloat = 250
    /// The card with the original above the result: the siblings' second step,
    /// the shelf's short box over its full one, under the language row.
    static var minimumHeightWithOriginal: CGFloat {
        panelInset * 2 + languageRowHeight + sourceBoxHeight + boxGap
            + resultBoxHeight + footerHeight
    }
    /// The shelf's short input box, which the panel's original takes.
    static let sourceBoxHeight: CGFloat = SidePanelContentView.minBoxHeight
    /// The shelf's full result box, which the panel's answer takes.
    static let resultBoxHeight: CGFloat = SidePanelContentView.resultBoxHeight
    /// The air between the two boxes, as the shelf's steps space them.
    static let boxGap: CGFloat = DroppySpacing.xsm
    /// The seam the language row cuts for the swap disc: the air under the
    /// labels' pill, the fillet that runs from the cut, and the air each label
    /// keeps from its half's edge.
    static let rowGap: CGFloat = DroppySpacing.xsm
    static let seamFillet: CGFloat = 10
    static let rowEdgeInset: CGFloat = 10
    /// What the row adds above the original's box: the pill, with the box
    /// tucked under the disc's lower half.
    static var languageRowHeight: CGFloat {
        LanguageMenu.pillRowHeight + rowGap
    }
    /// The tallest the card grows before its result scrolls.
    static let maximumHeight: CGFloat = 600
    /// The source is context, not the answer: four lines, then it scrolls.
    static let sourceTextCap: CGFloat = 68
    /// The text's room inside the card, once the root and tile insets are
    /// taken out. The panel has a fixed width, so the height follows from it.
    static var textWidth: CGFloat {
        SidePanel.expandedWidth - panelInset * 2 - PanelTileText.sideInset * 2 - 20
    }

    /// The height the card needs for this pair, between its floor and its cap.
    /// With an original the two boxes keep the siblings' step-2 heights instead
    /// of shrinking to their words; the result takes the room the source
    /// leaves, and past the cap it scrolls.
    static func cardHeight(
        forWidth width: CGFloat,
        translated: String,
        source: String,
        showsOriginal: Bool
    ) -> CGFloat {
        let showsSource = showsOriginal && !source.isEmpty
        let textWidth = max(120, width - panelInset * 2 - PanelTileText.sideInset * 2 - 20)
        let resultText = textHeight(translated, width: textWidth)
        guard showsSource else {
            // Root inset, the tile's language row and padding, the copy row
            // and the footer. The floor already leaves a few lines of air.
            let chrome: CGFloat = 160
            let resultCap = max(0, maximumHeight - chrome)
            let resultHeight = min(resultText, resultCap)
            return min(maximumHeight, max(minimumHeight, chrome + resultHeight))
        }
        let sourceText = min(textHeight(source, width: textWidth), sourceTextCap)
        let sourceTile = max(sourceBoxHeight, sourceText + PanelTileText.verticalAir * 2)
        let room = maximumHeight - panelInset * 2 - languageRowHeight - sourceTile
            - boxGap - footerHeight
        let resultTile = max(
            resultBoxHeight,
            min(resultText + PanelTileText.verticalAir * 2, room)
        )
        let natural = panelInset * 2 + languageRowHeight + sourceTile + boxGap
            + resultTile + footerHeight
        return min(maximumHeight, max(minimumHeightWithOriginal, natural))
    }

    static func minimumHeight(showsOriginal: Bool) -> CGFloat {
        showsOriginal ? minimumHeightWithOriginal : minimumHeight
    }

    /// The text's wrapped height at the panel's type size, measured the way
    /// the scroll view lays it out: character wrapping and a 5pt indent.
    static func textHeight(_ text: String, width: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let paragraph = NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = 5
        paragraph.headIndent = 5
        paragraph.lineBreakMode = .byCharWrapping
        let bounds = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: NSFont.systemFont(ofSize: SidePanelContentView.bodyFontSize),
                .paragraphStyle: paragraph
            ]
        )
        return ceil(bounds.height) + 2
    }

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
            // The footer follows the box with only its own 6pt rim above the
            // disc, as on the shelf and the edge panel; the box takes the rest.
            VStack(spacing: 0) {
                if showsLanguageRow {
                    languageRow
                    sourceTile
                        .padding(.top, -(SidePanelContentView.discRadius - Self.rowGap))
                        .padding(.bottom, Self.boxGap)
                }
                resultTile
                footer
            }
            chipLayer
        }
        .coordinateSpace(name: SidePanelChipState.space)
        .environment(\.sidePanelChip, chip)
        .onPreferenceChange(SidePanelChipFrameKey.self) { chip.frames = $0 }
        .onChange(of: model.isToolbarExpanded) { _, open in
            // A menu that folds under the pointer never reports `ended`, and a
            // stale true would hold it open on the next hover.
            pointerInMenu = false
            if open { return }
            moreCloseTask?.cancel()
            moreCloseTask = nil
        }
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
        .frame(minHeight: Self.minimumHeight(
            showsOriginal: showsOriginal && !source.isEmpty
        ))
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
        .onDisappear {
            moreCloseTask?.cancel()
            model.isToolbarExpanded = false
        }
    }

    /// The glass every box sits on, bevel included: without the top rim the
    /// pane disappears into the card.
    private var tileGlass: some View {
        FrostedTileSurface(shape: AnyShape(tileShape))
    }

    private var tileShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: panelTileRadius, style: .continuous)
    }

    /// The card with an original shows the shelf's language row: the two
    /// labels in one capsule, the swap disc in the seam it cuts, and the
    /// original's box tucked under it.
    private var showsLanguageRow: Bool {
        showsOriginal && !source.isEmpty
    }

    /// The shelf's language row, at the panel's own width.
    private var languageRow: some View {
        let rowWidth = SidePanel.expandedWidth - panelInset * 2
        let halfWidth = (rowWidth - SidePanelContentView.discRadius * 2) / 2
        let button = SidePanelContentView.buttonDiameter
        let capsule = AnyShape(Capsule(style: .continuous))
        return ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: rowWidth, height: LanguageMenu.pillRowHeight)
                .droppyGlassControlChrome(shape: capsule)
                .mask {
                    GlassPocketMask(
                        shape: capsule,
                        centreY: LanguageMenu.pillRowHeight,
                        radius: SidePanelContentView.discRadius,
                        bottomFillet: Self.seamFillet
                    )
                }
            swapButton
                .offset(x: (rowWidth - button) / 2, y: LanguageMenu.pillRowHeight - button / 2)
            swapGlyph
                .offset(x: (rowWidth - button) / 2, y: LanguageMenu.pillRowHeight - button / 2)
            HStack(spacing: 0) {
                LanguageMenu(
                    model: model,
                    selection: $model.sourceID,
                    includesAuto: true,
                    label: sourceMenuLabel,
                    inPillRow: true,
                    highlighted: chip.target == .source,
                    fontSize: SidePanelContentView.bodyFontSize,
                    alignment: .center,
                    edgeInset: Self.rowEdgeInset,
                    chipTarget: .source,
                    availableIDs: model.installedSourceIDs
                )
                .chipTarget(
                    .source,
                    insets: EdgeInsets(
                        top: PanelFooterMetrics.chipInset,
                        leading: 0,
                        bottom: PanelFooterMetrics.chipInset,
                        trailing: 0
                    )
                )
                .padding(.leading, PanelFooterMetrics.chipInset)
                .frame(width: halfWidth)
                // The pocket's width: both labels end on the disc's edge.
                Color.clear
                    .frame(width: SidePanelContentView.discRadius * 2)
                LanguageMenu(
                    model: model,
                    selection: $model.targetID,
                    includesAuto: false,
                    label: model.name(for: model.targetID),
                    inPillRow: true,
                    highlighted: chip.target == .target,
                    fontSize: SidePanelContentView.bodyFontSize,
                    alignment: .center,
                    edgeInset: Self.rowEdgeInset,
                    chipTarget: .target,
                    availableIDs: model.installedTargetIDs
                )
                .chipTarget(
                    .target,
                    insets: EdgeInsets(
                        top: PanelFooterMetrics.chipInset,
                        leading: 0,
                        bottom: PanelFooterMetrics.chipInset,
                        trailing: 0
                    )
                )
                .padding(.trailing, PanelFooterMetrics.chipInset)
                .frame(width: halfWidth)
            }
            .frame(width: rowWidth, height: LanguageMenu.pillRowHeight)
        }
        .frame(
            width: rowWidth,
            height: LanguageMenu.pillRowHeight + SidePanelContentView.discRadius,
            alignment: .topLeading
        )
    }

    private var swapButton: some View {
        Button {
            model.swapLanguages()
        } label: {
            Color.clear
                .frame(
                    width: SidePanelContentView.buttonDiameter,
                    height: SidePanelContentView.buttonDiameter
                )
                .contentShape(Circle())
        }
        .buttonStyle(
            PanelPressStyle(
                hoverScale: SidePanelChipState.hoverScale,
                pressScale: SidePanelChipState.pressScale
            )
        )
        .background {
            Color.clear.droppyGlassControlChrome(shape: AnyShape(Circle()))
        }
        .chipTarget(.swap)
        .arrowCursorRegion()
        .a11y("a11y.swap")
        .disabled(!model.canSwap)
    }

    private var swapGlyph: some View {
        PanelSwapGlyph(spins: model.swapSpins, enabled: model.canSwap)
            .chipHidesInk(chip.covers(.swap))
            .allowsHitTesting(false)
    }

    /// The original's box: the shelf's short input, with the swap disc's pocket
    /// cut into its top edge when the row is above it.
    private var sourceTile: some View {
        sourceWords
            .frame(minHeight: Self.sourceBoxHeight, alignment: .top)
            .background {
                if showsLanguageRow {
                    FrostedTileSurface(shape: AnyShape(tileShape))
                        .mask {
                            GlassPocketMask(
                                shape: AnyShape(tileShape),
                                centreY: -Self.rowGap,
                                radius: SidePanelContentView.discRadius,
                                topFillet: Self.seamFillet
                            )
                        }
                } else {
                    tileGlass
                }
            }
    }

    private var sourceWords: some View {
        TranslationOutputScrollView(
            text: source,
            resetToken: "",
            scrollerTopInset: PanelTileText.verticalAir,
            scrollerBottomInset: PanelTileText.verticalAir,
            textInset: PanelTileText.verticalAir,
            fontSize: SidePanelContentView.bodyFontSize
        )
        // The words keep the same air; the pane they scroll behind reaches the
        // box's rim, so a cut line fades there instead of stopping above it.
        .frame(height: Self.sourceHeight(for: source) + PanelTileText.verticalAir * 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PanelTileText.sideInset)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .panelTileEdgeFade()
    }

    /// The source keeps a short box; a capture longer than the cap scrolls
    /// instead of pushing the answer off the card.
    static func sourceHeight(for source: String) -> CGFloat {
        min(textHeight(source, width: textWidth), sourceTextCap)
    }

    private var sourceMenuLabel: String {
        model.sourceID == TranslateModel.auto ? sourceName : model.name(for: model.sourceID)
    }

    /// The result's box. Alone, it carries the target picker at its top edge;
    /// beside an original, the picker sits in the language row above instead.
    private var resultTile: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.xs) {
            if !showsLanguageRow {
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
                .padding(.leading, PanelTileText.sideInset)
                .chipTarget(.target)
            }
            resultWords
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The copy sits on the tile's bottom edge, as on the edge panel's
        // result box, and outside the fade so its word stays sharp.
        .overlay(alignment: .bottomTrailing) {
            copyButton
                .padding(.trailing, DroppySpacing.sm)
                .padding(.bottom, DroppySpacing.sm)
        }
        .background { tileGlass }
    }

    private var resultWords: some View {
        TranslationOutputScrollView(
            text: translated,
            resetToken: "",
            scrollerTopInset: PanelTileText.verticalAir,
            scrollerBottomInset: PanelTileText.verticalAir,
            textInset: PanelTileText.verticalAir,
            fontSize: SidePanelContentView.bodyFontSize
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, PanelTileText.sideInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .panelTileEdgeFade()
    }

    private var copyButton: some View {
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
            // The menu stays mounted so its glass can fold back into the disc;
            // `open` drives the slide and the hit area.
            PanelMoreMenu(
                model: model,
                open: model.isToolbarExpanded,
                requestCapture: requestCapture,
                requestSelection: requestSelection,
                cancelSelection: cancelSelection,
                onHover: { moreHover($0, inMenu: true) },
                pinned: isPinned,
                onPin: togglePin
            )
            .offset(y: -Self.footerHeight)
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
            languageInk(for: sourceMenuLabel)
        case .target:
            languageInk(for: model.name(for: model.targetID))
        case .swap:
            PanelSwapGlyph(spins: model.swapSpins, enabled: model.canSwap)
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

    /// The language ink the chip draws while it covers a control. The row's
    /// labels are the shelf's pill labels and keep their size; the lone
    /// picker inside the result box is the smaller menu label.
    @ViewBuilder
    private func languageInk(for text: String) -> some View {
        if showsLanguageRow {
            PillLanguageLabel(
                text: text,
                highlighted: true,
                fontSize: SidePanelContentView.bodyFontSize,
                alignment: .center,
                edgeInset: Self.rowEdgeInset
            )
        } else {
            PanelMenuLabel(text: text, fontSize: SidePanelContentView.labelFontSize)
        }
    }
}

/// The swap disc's glyph, drawn apart from its glass so the chip can put the
/// glyph above the chip's own glass.
private struct PanelSwapGlyph: View {
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
            .frame(
                width: SidePanelContentView.buttonDiameter,
                height: SidePanelContentView.buttonDiameter
            )
            .opacity(enabled ? 1 : 0.65)
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
