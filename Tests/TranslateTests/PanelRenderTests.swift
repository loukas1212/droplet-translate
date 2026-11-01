import AppKit
import SwiftUI
import Testing
@testable import Translate

/// The floating panel, the edge tab and the terminal HUD card can be drawn.
///
/// The panel is the droplet's own window over another app: the host has no
/// surface for it, so nothing else in the project renders it. This test draws
/// the panel's visible states into a window and writes them out as pictures, so
/// the design can be looked at without a translation running.
@Suite("External result surfaces")
@MainActor
struct PanelRenderTests {
    /// Where the pictures are written.
    private static var folder: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("translate-panel-shots", isDirectory: true)
    }

    @Test("The more menu's glass starts on the disc and slides into its rectangle")
    func moreMenuGlassSlidesOutOfTheDisc() {
        let lift = PanelFooterMetrics.footerHeight
        let menuWidth = PanelMoreMenu(model: TranslateModel(), open: false).width
        // Four rows, the air between them, and the menu's edge inset.
        let menuHeight: CGFloat = 146
        let background = CGRect(x: 0, y: 0, width: menuWidth, height: menuHeight + lift)

        let closed = PanelMenuMorphShape(progress: 0, lift: lift)
            .path(in: background)
            .boundingRect
        let disc = CGRect(
            x: background.minX,
            y: menuHeight + PanelFooterMetrics.rim,
            width: PanelFooterMetrics.disc,
            height: PanelFooterMetrics.disc
        )
        #expect(closed == disc, "the menu's glass does not start on the disc")

        let open = PanelMenuMorphShape(progress: 1, lift: lift)
            .path(in: background)
            .boundingRect
        #expect(open == CGRect(x: 0, y: 0, width: menuWidth, height: menuHeight))
        // The glass travels the whole footer: the circle rises into the card.
        #expect(closed.maxY - open.maxY == lift)

        let half = PanelMenuMorphShape(progress: 0.5, lift: lift)
            .path(in: background)
            .boundingRect
        #expect(half.maxY > open.maxY && half.maxY < closed.maxY)
        #expect(half.width > closed.width && half.width < open.width)
    }

    @Test("The panel's result and terminal statuses draw")
    func thePanelDraws() throws {
        let folder = Self.folder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let result = try Self.draw(
            ResultWindowView(
                model: TranslateModel(),
                translated: "The rain in Spain falls mainly on the plain.",
                source: "ฝนในสเปนตกหลักบนที่ราบ",
                sourceName: "Thai",
                pinned: false,
                showsOriginal: true,
                onCopy: {},
                onClose: {},
                onPin: {}
            ),
            size: CGSize(width: 460, height: ResultWindowView.minimumHeightWithOriginal),
            named: "panel-result"
        )
        // The result alone, measured at the panel's fixed width: the target
        // language stays a picker, and the pin lives only in the more menu.
        let resultOnly = try Self.draw(
            ResultWindowView(
                model: TranslateModel(),
                translated: "The rain in Spain falls mainly on the plain.",
                source: "",
                sourceName: "Thai",
                pinned: false,
                showsOriginal: false,
                onCopy: {},
                onClose: {},
                onPin: {}
            ),
            size: CGSize(width: 460, height: ResultWindowView.minimumHeight),
            named: "panel-result-only"
        )
        // The footer's menu on the themed card, as the settings picture draws
        // it: black under the glass keeps the ink legible and shows the one
        // column clearing the card's top edge, at both card heights.
        let menuModel = TranslateModel()
        menuModel.isToolbarExpanded = true
        let menu = try Self.draw(
            ResultWindowView(
                model: menuModel,
                translated: "The rain in Spain falls mainly on the plain.",
                source: "ฝนในสเปนตกหลักบนที่ราบ",
                sourceName: "Thai",
                pinned: false,
                showsOriginal: true,
                backdrop: .hostGlassOnBlack,
                onCopy: {},
                onClose: {},
                onPin: {}
            ),
            size: CGSize(width: 460, height: ResultWindowView.minimumHeightWithOriginal),
            named: "panel-more-menu"
        )
        let menuShortModel = TranslateModel()
        menuShortModel.isToolbarExpanded = true
        let menuShort = try Self.draw(
            ResultWindowView(
                model: menuShortModel,
                translated: "The rain in Spain falls mainly on the plain.",
                source: "",
                sourceName: "Thai",
                pinned: false,
                showsOriginal: false,
                backdrop: .hostGlassOnBlack,
                onCopy: {},
                onClose: {},
                onPin: {}
            ),
            size: CGSize(width: 460, height: ResultWindowView.minimumHeight),
            named: "panel-more-menu-short"
        )
        let failed = try Self.draw(
            ResultWindowStatusView(
                message: "The translation failed. Try again.",
                actionTitle: "Try again",
                onAction: {},
                onClose: {}
            ),
            size: CGSize(width: 320, height: 140),
            named: "panel-failed"
        )
        let needsDownload = try Self.draw(
            ResultWindowStatusView(
                message: "Download English → Thai to translate.",
                actionTitle: "Download",
                onAction: {},
                onClose: {}
            ),
            size: CGSize(width: 320, height: 140),
            named: "panel-needs-download"
        )

        #expect(result > 0, "the result panel drew nothing")
        #expect(resultOnly > 0, "the result-only panel drew nothing")
        #expect(menu > 0, "the panel's more menu drew nothing")
        #expect(menuShort > 0, "the short panel's more menu drew nothing")
        #expect(failed > 0, "the failure status panel drew nothing")
        #expect(needsDownload > 0, "the download status panel drew nothing")
    }

    @Test("The side panel draws its tab and docks to the right edge")
    func sidePanelDrawsDocked() throws {
        let tab = try Self.draw(
            SidePanelTabView(),
            size: CGSize(width: SidePanel.windowWidth, height: SidePanel.windowHeight),
            named: "side-panel"
        )
        let grown = SidePanelTabView()
        grown.renderHover = 1
        let hover = try Self.draw(
            grown,
            size: CGSize(width: SidePanel.windowWidth, height: SidePanel.windowHeight),
            named: "side-panel-hover"
        )

        let screen = CGRect(x: 100, y: 50, width: 1440, height: 900)
        let centred = SidePanel.frame(on: screen, originY: screen.midY - SidePanel.windowHeight / 2)
        let left = SidePanel.frame(
            on: screen,
            originY: screen.midY - SidePanel.windowHeight / 2,
            side: .left
        )
        let top = SidePanel.frame(on: screen, originY: -10_000)
        let bottom = SidePanel.frame(on: screen, originY: 10_000)
        #expect(tab > 0, "the side panel drew nothing")
        #expect(hover > 0, "the grown side panel drew nothing")
        #expect(centred.maxX == screen.maxX, "the tab is not flush with the right edge")
        #expect(left.minX == screen.minX, "the tab is not flush with the left edge")
        #expect(centred.midY == screen.midY, "the tab is not centred vertically")
        #expect(centred.width == SidePanel.windowWidth)
        #expect(centred.height == SidePanel.windowHeight)
        #expect(top.minY == screen.minY, "the tab can be dragged off the top")
        #expect(bottom.maxY == screen.maxY, "the tab can be dragged off the bottom")
    }

    @Test("The pin stops an outside click from folding the edge card")
    func pinStopsOutsideFold() {
        #expect(!SidePanel.foldsOnDismissal(isPinned: true))
        #expect(SidePanel.foldsOnDismissal(isPinned: false))
        #expect(SidePanel.foldsOnDismissal(isPinned: true, respectingPin: false))
    }

    @Test("A press on a pinned card takes the foreground back")
    func pinnedCardPressTakesFocusBack() {
        let panel = SidePanel.shared
        panel.ignoresMouseEvents = true
        #expect(panel.ignoresMouseEvents, "an unpinned card follows the host's mask")
        // The card stays live while another app is in front; the press only has
        // to bring Droppy forward so the control under the pointer takes it.
        #expect(SidePanel.takesFocusBack(
            isPinned: true, isExpanded: true, appIsActive: false
        ))
        #expect(!SidePanel.takesFocusBack(
            isPinned: true, isExpanded: true, appIsActive: true
        ))
        #expect(!SidePanel.takesFocusBack(
            isPinned: true, isExpanded: false, appIsActive: false
        ))
        #expect(!SidePanel.takesFocusBack(
            isPinned: false, isExpanded: true, appIsActive: false
        ))
        #expect(SidePanel.isPress(.leftMouseDown))
        #expect(SidePanel.isPress(.rightMouseDown))
        #expect(!SidePanel.isPress(.mouseMoved))
        // The host may mask a background droplet's window; a pinned card keeps
        // its clicks so the unpin row is reachable.
        #expect(SidePanel.keepsClicks(isPinned: true, isExpanded: true))
        #expect(!SidePanel.keepsClicks(isPinned: false, isExpanded: true))
        #expect(!SidePanel.keepsClicks(isPinned: true, isExpanded: false))
    }

    @Test("An open card keeps the glass's clear face after unpinning")
    func openCardHoldsKeyAppearance() {
        #expect(PanelKeyAppearance.shouldHold(pinned: true, shown: true))
        // The pin keeps the card open; it does not own the face. Unpinning an
        // open card must not flip it to the system's frosted glass.
        #expect(PanelKeyAppearance.shouldHold(pinned: false, shown: true))
        #expect(!PanelKeyAppearance.shouldHold(pinned: false, shown: false))
    }

    @Test("The card opens and folds back onto the tab")
    func cardFoldsBackToTheTab() throws {
        let opening = SidePanel.revealSamples(frames: 60)
        #expect(opening.first == 0)
        #expect(opening.last == 1, "the card never settles open")
        #expect(opening.max() ?? 0 > 1.02, "the card lost its visible rubber-band overshoot")
        #expect(abs((opening.max() ?? 0) - 1.05) < 0.001, "the open does not run 5% past the card")

        // The fold has its own curve: never above the card, so a close cannot
        // puff back out before it shrinks. It runs past the tab and settles back
        // up to it, one beat each way.
        let folding = SidePanel.foldSamples(frames: 60)
        #expect(folding.first == 1)
        #expect(folding.last == 0, "the fold never returns to the tab")
        #expect(folding.allSatisfy { $0 <= 1 }, "the fold puffs out before it shrinks")
        let floor = folding.min() ?? 0
        #expect(abs(floor + SidePanel.foldSquash) < 0.002, "the fold does not run past the tab")
        let turn = folding.firstIndex(of: floor) ?? 0
        let descending = folding[..<turn]
        #expect(
            zip(descending, descending.dropFirst()).allSatisfy { $0 >= $1 },
            "the fold grows on its way down to the tab"
        )
        let ascending = folding[turn...]
        #expect(
            zip(ascending, ascending.dropFirst()).allSatisfy { $0 <= $1 },
            "the fold does not settle back up to the tab"
        )
        // The close leaves at a finite speed and lands still, so neither end
        // snaps: a hesitation before it moves, or a jolt as it arrives.
        let firstStep = folding[0] - folding[1]
        let lastStep = folding[folding.count - 2] - folding[folding.count - 1]
        #expect(firstStep > 0, "the fold hesitates before it moves")
        #expect(firstStep < 0.1, "the fold jumps off the card")
        #expect(abs(lastStep) < 0.01, "the fold lands with a jolt")
        // The shrink owns its own seconds and the settle its own. The fold plays
        // the curve backwards from the card, so the turn is reached after the
        // shrink's time and the settle takes what is left.
        let shrinkTime = CGFloat(turn) / CGFloat(folding.count - 1) * CGFloat(SidePanel.foldDuration)
        #expect(
            abs(shrinkTime - CGFloat(SidePanel.foldShrinkDuration)) < 0.02,
            "the shrink and the settle do not take the time they were given"
        )

        // The frames the fold plays, so the eye can check the two beats: the
        // card shrinks past the resting tab, then the tab settles back to it.
        let size = CGSize(width: 11 * 480 + 20, height: 680)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(white: 0.85, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor.black.setFill()
        let tab = NSRect(x: 0, y: 0, width: SidePanel.width, height: SidePanel.height)
        let card = NSRect(x: 0, y: 0, width: SidePanel.expandedWidth, height: 520)
        for (column, progress) in stride(from: CGFloat(0), through: 1, by: 0.1).enumerated() {
            let reveal = SidePanel.foldShape(1 - progress)
            let squash = min(1 + min(reveal, 0), 1)
            let width: CGFloat
            let height: CGFloat
            if reveal > 0 {
                let frame = SidePanel.revealRect(from: tab, to: card, at: reveal)
                let strip = SidePanelContentView.gripStrip * reveal
                let leadingInset = (SidePanel.windowWidth - SidePanel.width) * (1 - reveal)
                width = frame.width - leadingInset
                height = frame.height - strip
            } else {
                width = SidePanel.width * squash
                height = SidePanel.height * squash
            }
            let rect = NSRect(
                x: 10 + CGFloat(column + 1) * 480 - width,
                y: 340 - height / 2,
                width: width,
                height: height
            )
            let shape = reveal > 0
                ? SidePanelMorphShape(
                    reveal: reveal,
                    stretch: max(reveal, 1),
                    tabHeight: SidePanel.height
                ).path(in: rect)
                : SidePanelTabShape().path(in: rect)
            NSBezierPath(cgPath: shape.cgPath).fill()
        }
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        try png.write(to: Self.folder.appendingPathComponent("side-panel-fold.png"))
    }

    @Test("The fold lands on the tab's visible size, not the hit window")
    func foldLandsOnVisibleTab() {
        let rect = CGRect(
            x: 0,
            y: 0,
            width: SidePanel.width,
            height: SidePanel.windowHeight
        )
        let tabHeight = SidePanel.height
        let landed = SidePanelMorphShape(reveal: 0, tabHeight: tabHeight).path(in: rect)
        let tabRect = CGRect(
            x: rect.minX,
            y: rect.midY - tabHeight / 2,
            width: rect.width,
            height: tabHeight
        )
        let tab = SidePanelTabShape().path(in: tabRect)
        #expect(abs(landed.boundingRect.minY - tab.boundingRect.minY) < 0.01)
        #expect(abs(landed.boundingRect.maxY - tab.boundingRect.maxY) < 0.01)
        #expect(abs(landed.boundingRect.height - tabHeight) < 0.01)

        // The open still fills the whole window: the tab height only shortens
        // the folded end.
        let open = SidePanelMorphShape(reveal: 1, tabHeight: tabHeight).path(in: rect)
        #expect(abs(open.boundingRect.height - rect.height) < 0.01)
    }

    @Test("A bloom that turns round carries on from the size it reached")
    func reversedBloomKeepsItsSize() {
        // The open and the fold are different curves, so a target that flips
        // mid-flight has to re-read the phase or the card jumps size.
        for reveal in stride(from: CGFloat(0.1), through: 1, by: 0.05) {
            let openPhase = SidePanel.phase(for: reveal, folding: false)
            #expect(abs(SidePanel.bloomShape(openPhase) - reveal) < 0.002)

            let foldPhase = SidePanel.phase(for: reveal, folding: true)
            #expect(abs(SidePanel.foldShape(foldPhase) - reveal) < 0.001)
        }
        // A fold caught after it has run past the tab re-reads its own beat.
        for reveal in stride(from: CGFloat(-0.08), through: -0.02, by: 0.02) {
            let foldPhase = SidePanel.phase(for: reveal, folding: true)
            #expect(abs(SidePanel.foldShape(foldPhase) - reveal) < 0.001)
        }
    }

    @Test("The panel spring follows the same path at every refresh rate")
    func panelSpringIsRefreshRateIndependent() {
        let panel = SidePanel.shared
        let spring = (response: 0.42, damping: 0.65)
        let whole = panel.springStep(0, velocity: 0, to: 1, spring: spring, dt: 1.0 / 30)
        let half = panel.springStep(0, velocity: 0, to: 1, spring: spring, dt: 1.0 / 60)
        let twoHalves = panel.springStep(
            half.value,
            velocity: half.velocity,
            to: 1,
            spring: spring,
            dt: 1.0 / 60
        )
        #expect(abs(whole.value - twoHalves.value) < 0.0001)
        #expect(abs(whole.velocity - twoHalves.velocity) < 0.0001)
    }

    @Test("The collapsed tab keeps the reference silhouette at every scale")
    func tabShapeFollowsReference() {
        let idle = CGRect(x: 10, y: 0, width: 30, height: 160)
        let path = SidePanelTabShape().path(in: idle)
        #expect(abs(path.boundingRect.minX - idle.minX) < 0.01)
        #expect(abs(path.boundingRect.maxX - idle.maxX) < 0.01)
        #expect(abs(path.boundingRect.minY - idle.minY) < 0.01)
        #expect(abs(path.boundingRect.maxY - idle.maxY) < 0.01)
        // Full depth through the middle, flush with the edge at both tips.
        #expect(path.contains(CGPoint(x: 39, y: 80)), "the middle lost its depth")
        #expect(path.contains(CGPoint(x: 11, y: 80)), "the middle lost its inner reach")
        #expect(!path.contains(CGPoint(x: 11, y: 10)), "the taper no longer reaches the edge")

        let grown = SidePanelTabShape().path(in: CGRect(x: 0, y: 0, width: 40, height: 192))
        #expect(abs(grown.boundingRect.width - 40) < 0.01)
        #expect(abs(grown.boundingRect.height - 192) < 0.01)
        #expect(grown.contains(CGPoint(x: 1, y: 96)), "the grown tab lost its depth")
    }

    @Test("The morph keeps both screen-edge corners attached at every width")
    func morphKeepsScreenEdgeCornersAttached() {
        let narrow = CGRect(x: 0, y: 0, width: 22, height: 192)
        let card = SidePanelCardShape().path(in: narrow).boundingRect
        #expect(abs(card.minY - narrow.minY) < 0.01)
        #expect(abs(card.maxY - narrow.maxY) < 0.01, "the narrow card loses its lower-right corner")

        for reveal in stride(from: 0.0, through: 1.0, by: 0.05) {
            let rect = CGRect(x: 0, y: 0, width: 22 + 438 * reveal, height: 192 + 208 * reveal)
            let morph = SidePanelMorphShape(reveal: reveal).path(in: rect).boundingRect
            #expect(abs(morph.minY - rect.minY) < 0.01, "the morph loses its top edge at \(reveal)")
            #expect(abs(morph.maxY - rect.maxY) < 0.01, "the morph loses its bottom edge at \(reveal)")
        }
    }

    @Test("The drag handle is the tab's silhouette on its side")
    func gripHandleIsTheTabOnItsSide() {
        let rect = CGRect(
            x: 0,
            y: 0,
            width: SidePanelContentView.gripWidth,
            height: SidePanelContentView.gripDepth
        )
        let path = SidePanelGripShape().path(in: rect)
        #expect(abs(path.boundingRect.width - rect.width) < 0.01)
        #expect(abs(path.boundingRect.height - rect.height) < 0.01)
        // Flat against the card, full depth in the middle, tapered to the ends.
        #expect(path.contains(CGPoint(x: rect.midX, y: rect.minY + 0.5)), "the flat edge left the card")
        #expect(path.contains(CGPoint(x: rect.midX, y: rect.maxY - 0.5)), "the handle lost its middle")
        #expect(!path.contains(CGPoint(x: rect.minX + 1, y: rect.minY + 0.5)), "the end is not tapered")
        // Deeper than the old pill, so the silhouette reads as the tab.
        #expect(rect.height > 7)
    }

    @Test("The handle grows out of the card's outline, not on top of it")
    func gripLobeSharesTheCardOutline() {
        let rect = CGRect(x: 0, y: 0, width: 460, height: 300)
        let path = SidePanelUnifiedShape(reveal: 1, gripAmount: 1).path(in: rect)
        var subpaths = 0
        path.cgPath.applyWithBlock { element in
            if element.pointee.type == .moveToPoint { subpaths += 1 }
        }
        #expect(subpaths == 1, "the lobe is a second subpath, so its edge draws across the card")
    }

    @Test("The card blooms out of the tab's middle and folds back into it")
    func expandedSidePanelBloomsFromTabMiddle() throws {
        let workArea = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let tab = NSRect(x: 1408, y: 400, width: SidePanel.windowWidth, height: SidePanel.windowHeight)
        let height = SidePanel.expandedSize.height
        let top = SidePanel.expandedTop(tabMidY: tab.midY, cardHeight: height, workArea: workArea)
        let card = NSRect(
            x: tab.maxX - SidePanel.expandedWidth,
            y: top - height,
            width: SidePanel.expandedWidth,
            height: height
        )

        let closed = SidePanel.revealRect(from: tab, to: card, at: 0)
        let opened = SidePanel.revealRect(from: tab, to: card, at: 1)
        let firstFrame = SidePanel.revealRect(from: tab, to: card, at: 0.001)
        #expect(closed == tab, "the morph does not start on the tab's window")
        #expect(abs(opened.minY - card.minY) < 0.001 && opened.size == card.size)
        #expect(abs(firstFrame.height - tab.height) < 1, "the first frame jumps in height")

        let stretch: CGFloat = 1.06
        let overshot = SidePanel.revealRect(from: tab, to: card, at: stretch)
        let cardFaceHeight = card.height - SidePanelContentView.gripStrip
        let overshotFaceHeight = overshot.height - SidePanelContentView.gripStrip
        #expect(abs(overshot.width - card.width * stretch) < 0.001)
        #expect(abs(overshotFaceHeight - cardFaceHeight * stretch) < 0.001)
        #expect(overshot.maxX == card.maxX, "the radial stretch leaves the screen edge")
        #expect(
            abs(overshot.minY + SidePanelContentView.gripStrip + overshotFaceHeight / 2 - (card.maxY - cardFaceHeight / 2)) < 0.001,
            "the radial stretch does not expand from the screen-edge centre"
        )

        // Every frame's face must sit on the tab's own middle: not on the
        // screen's, and not half a grip strip above it.
        for reveal in stride(from: 0.01, through: 0.99, by: 0.02) {
            let frame = SidePanel.revealRect(from: tab, to: card, at: reveal)
            let strip = SidePanelContentView.gripStrip * reveal
            let face = NSRect(
                x: frame.minX,
                y: frame.minY + strip,
                width: frame.width,
                height: frame.height - strip
            )
            #expect(abs(face.midY - tab.midY) < 0.01, "the face left the tab's middle at \(reveal)")
        }

        // A tab near either edge still keeps the card on screen.
        let low = SidePanel.expandedTop(tabMidY: 60, cardHeight: 400, workArea: workArea)
        #expect(low - 400 >= workArea.minY, "a low tab pushes the card off the bottom")
        let high = SidePanel.expandedTop(tabMidY: 890, cardHeight: 400, workArea: workArea)
        #expect(high <= workArea.maxY, "a high tab pushes the card off the top")

        // Dragging the open card moves its top, and the tab folds back to the
        // middle of the face it left.
        let dragged = SidePanel.draggedTop(to: top - 120, cardHeight: height, workArea: workArea)
        #expect(abs(dragged - (top - 120)) < 0.001, "the open card ignores the drag")
        let centre = SidePanel.tabCentre(forCardTop: dragged, cardHeight: height)
        #expect(
            abs(SidePanel.expandedTop(tabMidY: centre, cardHeight: height, workArea: workArea) - dragged) < 0.001,
            "the fold does not land on the face's middle"
        )
        #expect(
            SidePanel.draggedTop(to: top + 10_000, cardHeight: height, workArea: workArea) == workArea.maxY,
            "a drag past the top leaves the work area"
        )
        #expect(
            SidePanel.draggedTop(to: top - 10_000, cardHeight: height, workArea: workArea)
                == workArea.minY + height,
            "a drag past the bottom leaves the work area"
        )

        // The frames the spring actually plays, so the eye can check the line.
        // True size, one column each, all sharing a middle.
        let size = CGSize(width: 8 * 480 + 20, height: 680)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(white: 0.85, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor.black.setFill()
        let samples = Self.sampled(SidePanel.revealSamples(frames: 40), count: 8)
        for (column, reveal) in samples.enumerated() {
            let frame = SidePanel.revealRect(from: tab, to: card, at: reveal)
            let strip = SidePanelContentView.gripStrip * min(max(reveal, 0), 1)
            let width = reveal == 0 ? SidePanel.width : frame.width
            let height = reveal == 0 ? SidePanel.height : frame.height - strip
            let rect = NSRect(
                x: 10 + CGFloat(column + 1) * 480 - width,
                y: 340 - height / 2,
                width: width,
                height: height
            )
            let shape = reveal == 0
                ? SidePanelTabShape().path(in: rect)
                : SidePanelMorphShape(reveal: reveal, stretch: max(reveal, 1)).path(in: rect)
            NSBezierPath(cgPath: shape.cgPath).fill()
        }
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        try png.write(to: Self.folder.appendingPathComponent("side-panel-bloom.png"))
    }

    @Test("The left card opens and folds flush with the left edge")
    func leftCardStaysOnTheLeftEdge() {
        let workArea = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let tab = NSRect(x: 0, y: 400, width: SidePanel.windowWidth, height: SidePanel.windowHeight)
        let height = SidePanel.expandedSize.height
        let top = SidePanel.expandedTop(tabMidY: tab.midY, cardHeight: height, workArea: workArea)
        let card = NSRect(
            x: tab.minX,
            y: top - height,
            width: SidePanel.expandedWidth,
            height: height
        )

        for reveal in [0, 0.001, 0.25, 0.5, 0.75, 1] as [CGFloat] {
            let frame = SidePanel.revealRect(from: tab, to: card, at: reveal, side: .left)
            #expect(
                frame.minX == card.minX,
                "the left card leaves the screen edge at reveal \(reveal)"
            )
        }

        let stretch: CGFloat = 1.06
        let overshot = SidePanel.revealRect(from: tab, to: card, at: stretch, side: .left)
        #expect(overshot.minX == card.minX, "the left card's stretch leaves the screen edge")
        #expect(abs(overshot.width - card.width * stretch) < 0.001)

        // The right edge keeps its own anchor.
        let rightCard = NSRect(
            x: 1440 - SidePanel.expandedWidth,
            y: top - height,
            width: SidePanel.expandedWidth,
            height: height
        )
        let rightTab = NSRect(
            x: 1440 - SidePanel.windowWidth,
            y: 400,
            width: SidePanel.windowWidth,
            height: SidePanel.windowHeight
        )
        let rightFrame = SidePanel.revealRect(from: rightTab, to: rightCard, at: 0.5)
        #expect(rightFrame.maxX == rightCard.maxX, "the right card leaves the screen edge")
    }

    /// The spring's samples, thinned to `count` even steps.
    private static func sampled(_ values: [CGFloat], count: Int) -> [CGFloat] {
        guard values.count > count, count > 1 else { return values }
        return (0..<count).map { values[$0 * (values.count - 1) / (count - 1)] }
    }

    @Test("The expanded side panel draws its header over the text box")
    func sidePanelExpandedDraws() throws {
        let model = TranslateModel()
        // Long enough to reach the box cap, so the shot shows the full card.
        model.input = Array(repeating: "The rain in Spain falls mainly on the plain.", count: 10)
            .joined(separator: "\n")
        let expanded = try Self.draw(
            SidePanelExpandedPreview(model: model),
            size: SidePanel.expandedSize,
            named: "side-panel-expanded"
        )
        #expect(expanded > 0, "the expanded side panel drew nothing")

        let compact = try Self.draw(
            SidePanelExpandedPreview(
                model: TranslateModel(),
                boxHeight: SidePanelContentView.panelBoxFloor,
                boxFloor: SidePanelContentView.panelBoxFloor
            ),
            size: CGSize(
                width: SidePanel.expandedWidth,
                height: SidePanel.windowHeight(forBody: SidePanelContentView.panelMinBodyHeight)
            ),
            named: "side-panel-compact"
        )
        #expect(compact > 0, "the empty side panel drew nothing")

        let menuModel = TranslateModel()
        menuModel.input = "The rain in Spain falls mainly on the plain."
        menuModel.isToolbarExpanded = true
        let menu = try Self.draw(
            SidePanelExpandedPreview(
                model: menuModel,
                boxHeight: SidePanelContentView.panelBoxFloor,
                boxFloor: SidePanelContentView.panelBoxFloor
            ),
            size: CGSize(
                width: SidePanel.expandedWidth,
                height: SidePanel.windowHeight(forBody: SidePanelContentView.panelMinBodyHeight)
            ),
            named: "side-panel-more-menu"
        )
        #expect(menu > 0, "the open more menu drew nothing")
    }

    @Test("The side panel opens the translation box under the input")
    func sidePanelResultDraws() throws {
        let model = TranslateModel()
        model.beginPreview(
            source: "en",
            target: "th",
            text: "The rain in Spain falls mainly on the plain.",
            translated: "ฝนตกในสเปนส่วนใหญ่บนที่ราบ"
        )
        let shot = try Self.draw(
            SidePanelExpandedPreview(model: model, boxHeight: SidePanelContentView.minBoxHeight),
            size: CGSize(
                width: SidePanel.expandedWidth,
                height: SidePanel.windowHeight(
                    forBody: SidePanelContentView.bodyHeight(
                        forBox: SidePanelContentView.minBoxHeight,
                        result: true
                    )
                )
            ),
            named: "side-panel-result"
        )
        #expect(shot > 0, "the side panel's result box drew nothing")
    }

    @Test("Step 3 hands the whole card to the result")
    func sidePanelFullCardDraws() throws {
        let model = TranslateModel()
        model.beginPreview(
            source: "en",
            target: "th",
            text: "The rain in Spain falls mainly on the plain.",
            translated: "ฝนตกในสเปนส่วนใหญ่บนที่ราบ"
        )
        let shot = try Self.draw(
            SidePanelExpandedPreview(
                model: model,
                boxHeight: SidePanelContentView.minBoxHeight,
                fold: 1
            ),
            size: CGSize(
                width: SidePanel.expandedWidth,
                height: SidePanel.windowHeight(
                    forBody: SidePanelContentView.bodyHeight(
                        forBox: SidePanelContentView.minBoxHeight,
                        result: true
                    )
                )
            ),
            named: "side-panel-full-card"
        )
        #expect(shot > 0, "the full-card result drew nothing")
    }

    @Test("The step-3 fold moves the result, not the buttons")
    func sidePanelMidFoldDraws() throws {
        let model = TranslateModel()
        model.beginPreview(
            source: "en",
            target: "th",
            text: "The rain in Spain falls mainly on the plain.",
            translated: "ฝนตกในสเปนส่วนใหญ่บนที่ราบ"
        )
        let shot = try Self.draw(
            SidePanelExpandedPreview(
                model: model,
                boxHeight: SidePanelContentView.minBoxHeight,
                fold: 0.5
            ),
            size: CGSize(
                width: SidePanel.expandedWidth,
                height: SidePanel.windowHeight(
                    forBody: SidePanelContentView.bodyHeight(
                        forBox: SidePanelContentView.minBoxHeight,
                        result: true
                    )
                )
            ),
            named: "side-panel-mid-fold"
        )
        #expect(shot > 0, "the mid-fold result drew nothing")
    }

    @Test("The side panel offers the language download above its message")
    func sidePanelDownloadDraws() throws {
        let model = TranslateModel()
        model.beginPreview(
            source: "en",
            target: "th",
            text: "The rain in Spain falls mainly on the plain.",
            translated: "",
            status: .needsDownload
        )
        let shot = try Self.draw(
            SidePanelExpandedPreview(model: model, boxHeight: SidePanelContentView.minBoxHeight),
            size: CGSize(
                width: SidePanel.expandedWidth,
                height: SidePanel.windowHeight(
                    forBody: SidePanelContentView.bodyHeight(
                        forBox: SidePanelContentView.minBoxHeight,
                        result: true
                    )
                )
            ),
            named: "side-panel-needs-download"
        )
        #expect(shot > 0, "the side panel's download state drew nothing")
    }

    @Test("The shelf draws the panel's card at solo and grouped widths")
    func shelfDrawsPanelCard() throws {
        let model = TranslateModel()
        model.beginPreview(
            source: "en",
            target: "th",
            text: "The rain in Spain falls mainly on the plain.",
            translated: "ฝนตกในสเปนส่วนใหญ่บนที่ราบ"
        )
        for (width, row, name) in [
            (CGFloat(440), SidePanelContentView.defaultRowWidth, "shelf-solo"),
            (CGFloat(230), CGFloat(214), "shelf-paired")
        ] {
            let shot = try Self.draw(
                TranslateWidget(
                    model: model,
                    rowWidth: row,
                    shelfStep: .full
                )
                    .padding(8)
                    .frame(width: width, height: ShelfHeightStep.full.height)
                    .background(Color.black),
                size: CGSize(width: width, height: ShelfHeightStep.full.height),
                named: name
            )
            #expect(shot > 0, "the shelf's \(name) card drew nothing")
        }
    }

    @Test("The shelf opens with the input and no result box")
    func shelfStartsClosed() throws {
        let shot = try Self.draw(
            TranslateWidget(model: TranslateModel())
                .padding(8)
                .frame(width: 440, height: ShelfHeightStep.compact.height)
                .background(Color.black),
            size: CGSize(width: 440, height: ShelfHeightStep.compact.height),
            named: "shelf-step-1"
        )
        #expect(shot > 0, "the closed shelf card drew nothing")
    }

    @Test("The shelf's capsule cycles the three card heights")
    func shelfStepsCycle() {
        #expect(ShelfHeightStep.compact.height == 250)
        #expect(ShelfHeightStep.medium.height == 440)
        #expect(ShelfHeightStep.full.height == 480)
        #expect(ShelfHeightStep.compact.contentHeight == 234)
        #expect(ShelfHeightStep.medium.contentHeight == 424)
        #expect(ShelfHeightStep.full.contentHeight == 464)
        // The boxes fill the round cards: the tall input alone, the short
        // input beside the result, then the result on the whole face.
        #expect(ShelfHeightStep.compact.room == 154)
        #expect(ShelfHeightStep.medium.room == 344)
        #expect(ShelfHeightStep.full.room == 424)
        #expect(ShelfHeightStep.compact.next == .medium)
        #expect(ShelfHeightStep.medium.next == .full)
        #expect(ShelfHeightStep.full.next == .compact)
        // The boxes read their growth from the card's real height, so the
        // window between the two heights must normalize on both shapes.
        #expect(ShelfHeightStep.growth(forHeight: 234, hostInset: 16) == 0)
        #expect(ShelfHeightStep.growth(forHeight: 424, hostInset: 16) == 1)
        #expect(ShelfHeightStep.growth(forHeight: 329, hostInset: 16) == 0.5)
        #expect(ShelfHeightStep.growth(forHeight: 250, hostInset: 0) == 0)
        #expect(ShelfHeightStep.growth(forHeight: 440, hostInset: 0) == 1)
        #expect(ShelfHeightStep.growth(forHeight: 100, hostInset: 16) == 0)
        #expect(ShelfHeightStep.growth(forHeight: 900, hostInset: 16) == 1)
    }

    @Test("Every box's words share one margin and edge fade")
    func tileTextRecipeIsShared() {
        #expect(PanelTileText.sideInset == 8)
        #expect(PanelTileText.verticalAir == 16)
        // The input's 10% at its resting height, capped so a tall result keeps
        // the same rim.
        #expect(abs(PanelTileText.fadeBand(for: 94) - 9.4) < 0.0001)
        #expect(PanelTileText.fadeBand(for: 160) == 16)
        #expect(PanelTileText.fadeBand(for: 420) == 16)
        // The top air is the band's full height, so the first line never sits
        // under the fade.
        #expect(PanelTileText.verticalAir == PanelTileText.fadeBand(for: 420))
    }

    @Test("The panels' standard card heights are round numbers")
    func panelCardHeightsAreRound() {
        // The floating panel: the result alone, then the original above it at
        // the siblings' second step, the shelf's short box over its full one.
        #expect(ResultWindowView.minimumHeight == 250)
        #expect(ResultWindowView.sourceBoxHeight == SidePanelContentView.minBoxHeight)
        #expect(ResultWindowView.resultBoxHeight == SidePanelContentView.resultBoxHeight)
        #expect(ResultWindowView.minimumHeightWithOriginal == 420)

        // The edge panel: opens empty, grows with the input, then holds the
        // result with the input at its floor and at its cap.
        #expect(
            SidePanel.cardHeight(forBody: SidePanelContentView.panelMinBodyHeight) == 300
        )
        #expect(
            SidePanel.cardHeight(forBody: SidePanelContentView.panelMaxInputBodyHeight) == 330
        )
        #expect(
            SidePanel.cardHeight(
                forBody: SidePanelContentView.bodyHeight(
                    forBox: SidePanelContentView.panelBoxFloor,
                    result: true
                )
            ) == 550
        )
        #expect(
            SidePanel.cardHeight(forBody: SidePanelContentView.maxPanelBodyHeight) == 580
        )
    }

    @Test("A drag down on the shelf's grip grows the card, up shrinks it")
    func shelfGripDrags() {
        #expect(ShelfHeightStep.compact.dragged(.down, canTranslate: true) == .medium)
        #expect(ShelfHeightStep.medium.dragged(.down, canTranslate: true) == .full)
        #expect(ShelfHeightStep.full.dragged(.down, canTranslate: true) == nil)
        #expect(ShelfHeightStep.medium.dragged(.up, canTranslate: true) == .compact)
        #expect(ShelfHeightStep.full.dragged(.up, canTranslate: true) == .medium)
        #expect(ShelfHeightStep.compact.dragged(.up, canTranslate: true) == nil)
        // An empty box has nothing to show, so pulling the card open does
        // nothing; pulling it shut still works.
        #expect(ShelfHeightStep.compact.dragged(.down, canTranslate: false) == nil)
        #expect(ShelfHeightStep.medium.dragged(.down, canTranslate: false) == nil)
        #expect(ShelfHeightStep.medium.dragged(.up, canTranslate: false) == .compact)
    }

    @Test("The shelf's grip travels as far up as down")
    func shelfGripPullIsEven() {
        let range = SidePanelContentView.shelfGripPullRange
        #expect(range.lowerBound == -SidePanelContentView.shelfGripLift)
        #expect(range.upperBound == SidePanelContentView.shelfGripLift)
        #expect(range.contains(0))
    }

    @Test("Return in the shelf translates and opens the result")
    func shelfReturnTranslates() throws {
        let model = TranslateModel()
        let hosting = NSHostingView(
            rootView: TranslateWidget(model: model)
                .padding(8)
                .frame(width: 440, height: ShelfHeightStep.compact.height)
        )
        hosting.frame = CGRect(x: 0, y: 0, width: 440, height: ShelfHeightStep.compact.height)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        hosting.layoutSubtreeIfNeeded()

        let editor = try #require(
            Self.textView(in: hosting),
            "the shelf mounted no editor"
        )
        model.input = "The rain in Spain falls mainly on the plain."
        window.makeFirstResponder(editor)
        let returnKey = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        ))
        editor.keyDown(with: returnKey)
        // The run starts on the spot; the card's second step is asked for in
        // the same call, so a queued press cannot leave it shut.
        #expect(model.status == .translating)
        model.clearInput()
        window.orderOut(nil)
    }

    @Test("Clearing the text puts the shelf's card back to its opening height")
    func shelfClearCollapses() async throws {
        let model = TranslateModel()
        model.beginPreview(
            source: "en",
            target: "th",
            text: "The rain in Spain falls mainly on the plain.",
            translated: "ฝนตกในสเปนส่วนใหญ่บนที่ราบ"
        )
        let log = ShelfStepLog()
        let hosting = NSHostingView(
            rootView: TranslateWidget(
                model: model,
                shelfStep: .full,
                onShelfStep: { log.steps.append($0) }
            )
            .padding(8)
            .frame(width: 440, height: ShelfHeightStep.full.height)
        )
        hosting.frame = CGRect(x: 0, y: 0, width: 440, height: ShelfHeightStep.full.height)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        try await Task.sleep(for: .milliseconds(300))
        hosting.layoutSubtreeIfNeeded()

        model.clearInput()
        // The cleared box lands first; the shrink follows a beat later.
        for _ in 0..<40 where log.steps.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(log.steps == [.compact])
        window.orderOut(nil)
    }

    @Test("The shelf's second and third steps give the result its room")
    func shelfStepsShowResult() throws {
        let model = TranslateModel()
        model.beginPreview(
            source: "en",
            target: "th",
            text: "The rain in Spain falls mainly on the plain.",
            translated: "ฝนตกในสเปนส่วนใหญ่บนที่ราบ"
        )
        for (step, height, name) in [
            (ShelfHeightStep.compact, ShelfHeightStep.compact.height, "shelf-step-1-result"),
            (.medium, ShelfHeightStep.medium.height, "shelf-step-2"),
            (.full, ShelfHeightStep.full.height, "shelf-step-3")
        ] {
            let shot = try Self.draw(
                TranslateWidget(model: model, shelfStep: step)
                    .padding(8)
                    .frame(width: 440, height: height)
                    .background(Color.black),
                size: CGSize(width: 440, height: height),
                named: name
            )
            #expect(shot > 0, "the shelf's \(name) card drew nothing")
        }

        // A solo island card spends no corner inset; the boxes take the extra
        // height and the footer stays on the card's bottom edge.
        let island = try Self.draw(
            TranslateWidget(model: model, shelfStep: .full)
                .frame(width: 440, height: ShelfHeightStep.full.height)
                .background(Color.black),
            size: CGSize(width: 440, height: ShelfHeightStep.full.height),
            named: "shelf-step-3-island"
        )
        #expect(island > 0, "the solo island shelf card drew nothing")
    }

    @Test("The language menu offers downloaded languages and the current one")
    func languageMenuOffersDownloaded() {
        let all = LanguageTools.options(for: ["en", "th", "ja"])
        let offered = LanguageMenu.offered(all, installed: ["en", "ja"], current: "th")
        #expect(Set(offered.map(\.id)) == Set(["en", "ja", "th"]))
        #expect(offered.count == 3)
        #expect(LanguageMenu.offered(all, installed: nil, current: "th").count == all.count)
    }

    @Test("The expanded panel shrinks and grows around its text box")
    func sidePanelFollowsInputHeight() async throws {
        let model = TranslateModel()
        var heights: [CGFloat] = []
        let hosting = NSHostingView(
            rootView: SidePanelContentView(
                model: model,
                chip: SidePanelChipState(),
                boxFloor: SidePanelContentView.panelBoxFloor,
                onBodyHeight: { height, _ in heights.append(height) }
            )
        )
        hosting.frame = CGRect(
            origin: .zero,
            size: CGSize(
                width: SidePanel.expandedWidth - SidePanelContentView.inset * 2,
                height: SidePanelContentView.panelMaxInputBodyHeight
            )
        )
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(300))

        // The editor reports its own measured height; the card is small, not capped.
        #expect(
            (heights.last ?? 0) >= SidePanelContentView.panelMinBodyHeight
                && (heights.last ?? 0) < SidePanelContentView.panelMaxInputBodyHeight,
            "an empty box should leave the panel at its smallest"
        )

        model.input = Array(repeating: "The rain in Spain falls mainly on the plain.", count: 10)
            .joined(separator: "\n")
        // The height arrives on the next main-queue turn, so poll instead of
        // trusting one fixed sleep.
        // The suite draws heavy views in parallel and can hold the main run
        // loop for seconds, so give the height callback room before calling it
        // short.
        let deadline = Date().addingTimeInterval(30)
        while (heights.last ?? 0) < SidePanelContentView.panelMaxInputBodyHeight, Date() < deadline {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(
            heights.last == SidePanelContentView.panelMaxInputBodyHeight,
            "long text should stop the card at the box cap, not grow past it"
        )
        window.orderOut(nil)
    }

    @Test("The grip has a large invisible drag target")
    func gripHasLargeInvisibleTarget() {
        #expect(SidePanelContentView.gripHitSize.width == SidePanelContentView.gripWidth)
        #expect(SidePanelContentView.gripHitSize.height == SidePanelContentView.gripStrip)
        #expect(
            SidePanelContentView.gripHitSize.height >= SidePanelContentView.gripDepth + 12,
            "the tab's drag target is barely bigger than the tab"
        )
    }

    @Test("The floating panel blooms on a radius from its point")
    func panelBloomsFromItsPoint() {
        let card = NSRect(
            x: 0,
            y: 0,
            width: 460,
            height: ResultWindowView.minimumHeightWithOriginal
        )
        let point = CGPoint(x: 120, y: 300)

        let dot = TranslationPanel.bloomRect(card: card, around: point, at: 0)
        #expect(dot.height == TranslationPanel.bloomDot, "the open does not start on the dot")
        #expect(
            abs(dot.width / dot.height - card.width / card.height) < 0.001,
            "the card stretched instead of scaling on a radius"
        )
        #expect(TranslationPanel.bloomRect(card: card, around: point, at: 1) == card)

        // One factor on both axes, anchored on the point: the card's middle
        // travels along the line out of the bloom point.
        let over = TranslationPanel.bloomRect(card: card, around: point, at: 1.08)
        let factor = over.width / card.width
        #expect(over.width > card.width && over.height > card.height, "the open never overshoots")
        #expect(abs((over.midY - point.y) - (card.midY - point.y) * factor) < 0.001)

        // A fold that dips below the dot stops on it rather than through it.
        let under = TranslationPanel.bloomRect(card: card, around: point, at: -0.08)
        #expect(under.size == dot.size, "the fold shrinks past the dot")

        #expect(TranslationPanel.bloomFade(0) == 0)
        #expect(TranslationPanel.bloomFade(0.45) == 0)
        #expect(TranslationPanel.bloomFade(1) == 1)

        // The edge panel's curve, so both surfaces bloom in the same beat.
        let samples = SidePanel.revealSamples(frames: 120)
        #expect(samples.first == 0, "the bloom does not start on the dot")
        #expect(samples.last == 1, "the bloom never settles")
        #expect(samples.max() ?? 0 > 1.02, "the bloom lost its overshoot")

        // The fold is the edge panel's fold curve: monotone, and quicker than
        // the open, so a close never puffs out on its way in.
        let fold = SidePanel.foldSamples(frames: 120)
        #expect(fold.first == 1)
        #expect(fold.last == 0, "the fold never reaches the dot")
        #expect(fold.allSatisfy { $0 <= 1 }, "the fold puffs out before it shrinks")
    }

    @Test("The floating panel's chip reaches its controls")
    func floatingPanelChipReachesControls() async throws {
        let chip = SidePanelChipState()
        let hosting = NSHostingView(
            rootView: ResultWindowView(
                model: TranslateModel(),
                translated: "The rain in Spain falls mainly on the plain.",
                source: "ฝนในสเปนตกหลักบนที่ราบ",
                sourceName: "Thai",
                pinned: false,
                showsOriginal: true,
                backdrop: .hostGlassOnBlack,
                onCopy: {},
                onClose: {},
                onPin: {},
                chipState: chip
            )
        )
        hosting.frame = CGRect(
            x: 0,
            y: 0,
            width: 460,
            height: ResultWindowView.minimumHeightWithOriginal
        )
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting

        let expected: [SidePanelChipTarget] = [.source, .target, .copy, .more, .engine]
        let deadline = Date().addingTimeInterval(30)
        while !expected.allSatisfy({ chip.frames[$0] != nil }), Date() < deadline {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }
        for target in expected {
            let frame = chip.frames[target]
            #expect(frame != nil, "the panel's chip cannot reach \(target)")
            #expect(
                frame?.width ?? 0 > 0 && frame?.height ?? 0 > 0,
                "the panel's chip has no room over \(target)"
            )
        }

        chip.target = .copy
        try await Task.sleep(for: .milliseconds(200))
        #expect(chip.covers(.copy), "the chip does not cover the copy control")
        hosting.layoutSubtreeIfNeeded()
        if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try FileManager.default.createDirectory(
                    at: Self.folder,
                    withIntermediateDirectories: true
                )
                try data.write(to: Self.folder.appendingPathComponent("panel-chip-copy.png"))
            }
        }
        window.orderOut(nil)
    }

    /// At rest the tab is behind the card's face and only its bar shows, so the
    /// rise has to reach the card's edge exactly, and the bar has to grow when
    /// the handle comes out.
    @Test("The drag handle rests inside the card and grows out of it")
    func gripRestsHidden() {
        #expect(
            SidePanelContentView.gripRise
                == SidePanelContentView.gripDepth - SidePanelContentView.gripTuck
                + SidePanelContentView.gripHide,
            "the hidden tab would still hang below the card"
        )
        // The stem is the only part buried when the handle shows: the curve the
        // card reveals is whole, so its silhouette does not change as it grows.
        #expect(
            SidePanelContentView.gripDepth - SidePanelContentView.gripTuck
                == SidePanelContentView.gripCurveDepth,
            "the card covers part of the curve"
        )
        #expect(SidePanelContentView.gripRestBar.width < SidePanelContentView.gripOutBar.width)
        #expect(SidePanelContentView.gripRestBar.height < SidePanelContentView.gripOutBar.height)
        #expect(
            SidePanelContentView.gripHitSize.height >= SidePanelContentView.gripRise
                + SidePanelContentView.gripDepth / 2,
            "the resting bar is outside the hover target"
        )
    }

    /// The card's face is measured from the body, not from the window: AppKit
    /// rounds a window frame to whole points, so a face taken from the window
    /// would leave the handle a pixel off the card's bottom edge.
    @Test("The handle starts inside the card's bottom edge")
    func gripMeetsCardEdge() {
        let body = SidePanelContentView.minBodyHeight
        let tangent = SidePanelCardShape.filletRadius + SidePanelContentView.inset
            + SidePanelContentView.contentHeight(forBody: body)
            - SidePanelContentView.gripPadding
            - SidePanelContentView.gripOverlap
            - SidePanelContentView.gripCurveDepth
        let face = SidePanel.windowHeight(forBody: body) - SidePanelContentView.gripStrip
        #expect(
            face - SidePanelCardShape.filletRadius - tangent
                == SidePanelContentView.gripOverlap,
            "the handle must start inside the card, or the two edges share a pixel"
        )
    }

    /// The translate tab doubles as the result box's grip: a downward drag
    /// pulls the box out of the input 1:1, an upward one folds it away, and a
    /// further 24pt up arms the clear. The card height the window reserves
    /// holds the top, and a taller input box leaves less of that room.
    @Test("The grip pulls the result box out, folds it away and arms the clear")
    func gripPullsResultBox() {
        let box = SidePanelContentView.minBoxHeight
        let resting = SidePanelContentView.resultBoxHeight
        let cap = SidePanelContentView.maxResultHeight(forBox: box)

        #expect(
            cap == resting + SidePanelContentView.panelMaxBoxHeight - box,
            "the default input box leaves the rest of the tallest card for the result"
        )
        #expect(
            SidePanelContentView.gripHeight(start: 0, translation: 100, deadband: 6, box: box) == 94,
            "a closed box follows the pointer past the click's slop"
        )
        #expect(
            SidePanelContentView.gripHeight(start: 0, translation: 10_000, deadband: 6, box: box) == resting,
            "without a result the box stops at the resting height"
        )
        #expect(
            SidePanelContentView.gripHeight(
                start: resting,
                translation: 10_000,
                deadband: 6,
                box: box,
                full: true
            ) == resting + box,
            "a result grows by the input's height, so the card keeps its size"
        )
        #expect(
            SidePanelContentView.gripHeight(
                start: resting,
                translation: 50,
                deadband: 6,
                box: box,
                full: true
            ) == resting + 50 - 6,
            "an open result follows the pointer 1:1 until the fold"
        )
        #expect(
            SidePanelContentView.gripHeight(start: resting, translation: -100, deadband: -6, box: box)
                == resting - 100 + 6,
            "an upward drag folds the open box under the pointer"
        )
        #expect(
            SidePanelContentView.gripHeight(start: 0, translation: 6, deadband: 6, box: box) == 0,
            "the dead band keeps the box still at the threshold"
        )
        #expect(
            SidePanelContentView.gripHeight(
                start: resting,
                translation: -(resting + SidePanelContentView.gripClearPull + 10),
                deadband: -6,
                box: box
            ) <= -SidePanelContentView.gripClearPull,
            "24pt past the fold arms the clear"
        )
        #expect(
            SidePanelContentView.gripHeight(start: resting, translation: -100, deadband: -6, box: box)
                > -SidePanelContentView.gripClearPull,
            "a half fold does not clear"
        )
        #expect(
            SidePanelContentView.maxResultHeight(forBox: SidePanelContentView.panelMaxBoxHeight) == resting,
            "a full input box leaves the result at its resting height"
        )

        // Step 3: past the seam the input folds into the result, so the card
        // keeps its height while the result takes the whole face.
        #expect(
            SidePanelContentView.gripHeight(
                start: 0,
                translation: 10_000,
                deadband: 6,
                box: box,
                full: true
            ) == resting + box
        )
        #expect(SidePanelContentView.inputFold(pulled: resting, box: box, full: true) == 0)
        #expect(
            SidePanelContentView.inputFold(pulled: resting + box / 2, box: box, full: true)
                == 0.5
        )
        #expect(SidePanelContentView.inputFold(pulled: resting + box, box: box, full: true) == 1)
        #expect(
            SidePanelContentView.inputFold(pulled: resting + box, box: box, full: false) == 0,
            "step 3 needs a result to show"
        )
        #expect(
            SidePanelContentView.bodyHeight(forBox: 0, result: true, resultHeight: resting + box)
                == SidePanelContentView.bodyHeight(
                    forBox: box,
                    result: true,
                    resultHeight: resting
                ),
            "the folded result fills the card without growing it"
        )

        // The drag doubles as Return: the end of step 2 asks for the
        // translation once, when there is text and nothing to read yet.
        #expect(
            SidePanelContentView.startsTranslation(
                pulled: resting,
                hasInput: true,
                hasOutput: false,
                isTranslating: false
            )
        )
        #expect(
            !SidePanelContentView.startsTranslation(
                pulled: resting - 1,
                hasInput: true,
                hasOutput: false,
                isTranslating: false
            ),
            "the pull starts translating only at the end of step 2"
        )
        #expect(
            !SidePanelContentView.startsTranslation(
                pulled: resting,
                hasInput: false,
                hasOutput: false,
                isTranslating: false
            ),
            "an empty box has nothing to translate"
        )
        #expect(
            !SidePanelContentView.startsTranslation(
                pulled: resting,
                hasInput: true,
                hasOutput: true,
                isTranslating: false
            ),
            "a box that already reads is only resized"
        )
        #expect(
            !SidePanelContentView.startsTranslation(
                pulled: resting,
                hasInput: true,
                hasOutput: false,
                isTranslating: true
            ),
            "a run in flight is not restarted"
        )

        // The window body carries only the pulled slice, and the seam under
        // the input stays put, so the card edge tracks the pointer and the box
        // grows downward instead of sliding.
        let full = SidePanelContentView.bodyHeight(
            forBox: box,
            result: true,
            resultHeight: resting
        )
        let pulled = SidePanelContentView.bodyHeight(
            forBox: box,
            result: true,
            resultHeight: resting,
            resultReveal: 94 / resting
        )
        #expect(abs((full - pulled) - (resting - 94)) < 0.001)

        // A stowed box marks nothing, so a pointer over where its download sat
        // cannot draw the button back above the box's own clip.
        #expect(!SidePanelContentView.marksChip(reveal: 0))
        #expect(!SidePanelContentView.marksChip(reveal: 0.9))
        #expect(SidePanelContentView.marksChip(reveal: 1))
    }

    /// The chip slides over every control in the panel, so every control has
    /// to report where it sits.
    @Test("The side panel's chip marks every control")
    func sidePanelChipMarksEveryControl() async throws {
        let model = TranslateModel()
        model.input = "The rain in Spain falls mainly on the plain."
        model.beginPreview(
            source: "en",
            target: "th",
            text: "The rain in Spain falls mainly on the plain.",
            translated: "ฝนตกในสเปนส่วนใหญ่บนที่ราบ"
        )
        let chip = SidePanelChipState()
        let hosting = NSHostingView(
            rootView: SidePanelContentView(
                model: model,
                chip: chip,
                boxHeight: SidePanelContentView.minBoxHeight
            )
        )
        hosting.frame = CGRect(
            origin: .zero,
            size: CGSize(
                width: SidePanel.expandedWidth - SidePanelContentView.inset * 2,
                height: SidePanelContentView.maxPanelBodyHeight
            )
        )
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hosting

        // The rows only exist while the menu is open; the download pill only
        // while the language pack is missing. Both are checked apart.
        let expected: [SidePanelChipTarget] = [
            .source, .target, .swap, .more, .engine,
            .input, .result, .copy, .paste, .clear
        ]
        let deadline = Date().addingTimeInterval(30)
        while !expected.allSatisfy({ chip.frames[$0] != nil }), Date() < deadline {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }

        for target in expected {
            let frame = chip.frames[target]
            #expect(frame != nil, "the chip cannot reach \(target)")
            #expect(
                frame?.width ?? 0 > 0 && frame?.height ?? 0 > 0,
                "the chip has no room over \(target)"
            )
        }

        // The language row keeps the rim the more disc keeps around its mark;
        // the swap disc takes its mark edge to edge, so the effect matches the
        // disc's own glass.
        let rim = PanelFooterMetrics.chipInset * 2
        #expect(chip.frames[.source]?.height == LanguageMenu.pillRowHeight - rim)
        #expect(chip.frames[.target]?.height == LanguageMenu.pillRowHeight - rim)
        #expect(chip.frames[.swap]?.height == SidePanelContentView.buttonDiameter)

        // The pocket's tangent is the red line: each mark runs to it on the
        // disc's side and keeps 3pt inside the capsule's end, so the mark's
        // rim is the same 3pt all round even where the pocket's circle bulges
        // into the half.
        let pocketMidX = try #require(chip.frames[.swap]?.midX)
        let redLine = SidePanelContentView.discRadius
        let half = SidePanelContentView.rowHalf
        let markWidth = half - PanelFooterMetrics.chipInset
        let source = try #require(chip.frames[.source])
        let target = try #require(chip.frames[.target])
        #expect(abs(source.maxX - (pocketMidX - redLine)) < 0.5, "the source mark does not end on the red line")
        #expect(abs(target.minX - (pocketMidX + redLine)) < 0.5, "the target mark does not start on the red line")
        #expect(abs(source.width - markWidth) < 0.5, "the source mark is not 3pt inside the capsule's end")
        #expect(abs(target.width - markWidth) < 0.5, "the target mark is not 3pt inside the capsule's end")
        #expect(abs(source.width - target.width) < 0.5, "the halves are not equal")
        // The label fills the mark's box, so the chip's ink sits where the
        // label rests instead of 1.5pt off it.
        #expect(abs(source.minX - (pocketMidX - redLine - markWidth)) < 0.5)
        #expect(abs(target.maxX - (pocketMidX + redLine + markWidth)) < 0.5)

        model.isToolbarExpanded = true
        // The menu's transition has to settle before its rows report the
        // frames they keep, clear of the disc.
        try await Task.sleep(for: .milliseconds(600))
        let menuDeadline = Date().addingTimeInterval(30)
        while chip.frames[.menuSettings] == nil, Date() < menuDeadline {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }
        for target in PanelMoreMenu.targets {
            let frame = chip.frames[target]
            #expect(frame != nil, "the chip cannot reach \(target)")
            #expect(
                frame?.width ?? 0 > 0 && frame?.height ?? 0 > 0,
                "the chip has no room over \(target)"
            )
        }

        // The more disc keeps the footer's bottom left; the engine chip sits
        // beside it.
        let more = try #require(chip.frames[.more])
        let engine = try #require(chip.frames[.engine])
        let input = try #require(chip.frames[.input])
        #expect(more.minX < engine.minX, "the more disc is not on the card's left")
        #expect(more.maxY > input.maxY, "the more disc is not below the boxes")
        #expect(engine.minX > more.maxX, "the engine chip is not beside the more disc")
        #expect(engine.midY > input.maxY, "the engine chip is not below the boxes")
        // The chip's glass is the disc's own glass, not a smaller mark inside it.
        #expect(
            more.width == PanelFooterMetrics.disc && more.height == PanelFooterMetrics.disc,
            "the chip does not match the more disc's size"
        )
        // The open menu starts above the disc, so the disc and its turning
        // dots stay in sight.
        let settings = try #require(chip.frames[.menuSettings])
        #expect(settings.maxY <= more.minY, "the open menu still covers the more disc")
        window.orderOut(nil)
    }

    /// The chip covers the control's own glass edge to edge, so the mark never
    /// reads as a smaller button; its ink lifts and dips with the menu rows.
    @Test("The chip covers the control and dips on press")
    func chipCoversControl() {
        let chip = SidePanelChipState()
        chip.frames[.more] = CGRect(x: 10, y: 20, width: 80, height: 36)
        #expect(chip.chipRect(for: .more) == chip.frames[.more])
        #expect(chip.inkScale == SidePanelChipState.hoverScale)

        chip.pressed = true
        #expect(chip.chipRect(for: .more) == chip.frames[.more])
        #expect(chip.inkScale == SidePanelChipState.pressScale)
    }

    @Test("The chip reaches toward its destination like a liquid drop")
    func liquidChipReachesTowardDestination() {
        let frame = CGRect(x: 20, y: 20, width: 44, height: 44)
        let resting = LiquidChipShape(
            rect: frame,
            destination: CGPoint(x: frame.midX, y: frame.midY)
        ).path(in: .zero).boundingRect
        #expect(resting == frame)

        let right = LiquidChipShape(rect: frame, destination: CGPoint(x: 200, y: frame.midY))
            .path(in: .zero).boundingRect
        #expect(right.minX == frame.minX)
        #expect(right.maxX > frame.maxX)

        let left = LiquidChipShape(rect: frame, destination: CGPoint(x: -100, y: frame.midY))
            .path(in: .zero).boundingRect
        #expect(left.minX < frame.minX)
        #expect(left.maxX == frame.maxX)
    }

    /// Leaving every control fades the glass over the one it last marked
    /// instead of letting it collapse toward the panel's top-left corner.
    @Test("The chip fades over its last control")
    func chipKeepsItsRestingFrame() {
        let chip = SidePanelChipState()
        let frame = CGRect(x: 10, y: 20, width: 80, height: 36)
        chip.frames[.more] = frame

        #expect(chip.rect(resting: nil) == nil)
        chip.target = .more
        #expect(chip.rect(resting: nil) == frame)

        chip.target = nil
        #expect(chip.rect(resting: frame) == frame)
    }

    /// A box takes a wash in its own silhouette, not the sliding glass: macOS 26
    /// glass cannot clip a shape that has a hole. A menu row takes the wash as
    /// well, because a second glass over the menu hides the row's words. The
    /// frame still tracks every control, so the mark travels either way.
    @Test("A box and a menu row are marked with a wash")
    func boxMarkIsAWash() {
        let chip = SidePanelChipState()
        let control = CGRect(x: 10, y: 20, width: 80, height: 36)
        let box = CGRect(x: 0, y: 60, width: 425, height: 92)
        let row = CGRect(x: 5, y: 100, width: 92, height: 24)
        chip.frames[.more] = control
        chip.frames[.input] = box
        chip.frames[.menuPin] = row

        chip.target = .more
        #expect(chip.rect(resting: nil) == control)
        #expect(!chip.marksWithWash(.more))

        chip.target = .input
        #expect(chip.rect(resting: control) == box)
        #expect(chip.marksWithWash(.input))

        chip.target = .menuPin
        #expect(chip.rect(resting: box) == row)
        #expect(chip.marksWithWash(.menuPin), "a menu row already sits on glass")
        #expect(!chip.marksWithWash(.paste))
    }

    /// A control keeps its own ink while the chip has no frame to draw over it.
    /// Both copies used to hide together, which left the engine pill and the
    /// more disc blank after a quick drag republished an empty frame set.
    @Test("A covered control keeps its ink without a chip frame")
    func coveredControlKeepsInkWithoutFrame() {
        let chip = SidePanelChipState()
        chip.target = .engine
        #expect(!chip.covers(.engine))

        chip.frames[.engine] = CGRect(x: 308, y: 144, width: 117, height: 22)
        #expect(chip.covers(.engine))
        #expect(!chip.covers(.more))
        #expect(!chip.covers(nil))
    }

    /// The mark fades where the pointer left it instead of collapsing back to
    /// the panel's corner, so leaving a control never sweeps the glass across
    /// the panel.
    @Test("The mark stays where the pointer left it")
    func chipFadesInPlace() {
        let chip = SidePanelChipState()
        let control = CGRect(x: 10, y: 20, width: 80, height: 36)
        chip.frames[.more] = control

        chip.target = .more
        chip.target = nil
        #expect(chip.rect(resting: nil) == control)
    }

    /// Crossing from a language pill to the swap disc must not pass through a
    /// hole between them: the chip would blink out and back in.
    @Test("The swap seam is one target from pill to pill")
    func swapSeamIsOneTarget() {
        let frames: [SidePanelChipTarget: CGRect] = [
            .source: CGRect(x: 77.5, y: 0, width: 103, height: 38),
            .target: CGRect(x: 244.5, y: 0, width: 103, height: 38),
            .swap: CGRect(x: 190.5, y: 16, width: 44, height: 44),
            .input: CGRect(x: 0, y: 44, width: 425, height: 92)
        ]
        // The 4pt gap between the left pill and the disc.
        #expect(SidePanelContentView.target(at: CGPoint(x: 182, y: 5), frames: frames) == .swap)
        #expect(SidePanelContentView.target(at: CGPoint(x: 182, y: 60), frames: frames) == .swap)
        // Below the seam the box keeps the pointer.
        #expect(SidePanelContentView.target(at: CGPoint(x: 182, y: 80), frames: frames) == .input)
        // A point on no control stays unmarked.
        #expect(SidePanelContentView.target(at: CGPoint(x: 400, y: 5), frames: frames) == nil)
    }

    /// Step 3 fades the language row out but leaves its frames in the
    /// preference. The hit test must skip them, or the chip draws the row back
    /// on the result when the pointer passes its old place.
    @Test("A faded language row takes no mark")
    func fadedHeaderTakesNoMark() {
        let frames: [SidePanelChipTarget: CGRect] = [
            .source: CGRect(x: 0, y: 0, width: 100, height: 34),
            .swap: CGRect(x: 100, y: 0, width: 44, height: 44),
            .target: CGRect(x: 144, y: 0, width: 100, height: 34),
            .result: CGRect(x: 0, y: 0, width: 425, height: 300)
        ]
        let point = CGPoint(x: 120, y: 20)
        #expect(SidePanelContentView.target(at: point, frames: frames) == .swap)
        #expect(
            SidePanelContentView.target(at: point, frames: frames, marksHeader: false)
                == .result
        )
    }

    /// The open menu sits above the more disc. If their hit regions meet, the
    /// chip must mark the row, not the disc below it.
    @Test("The open menu takes the more disc's mark")
    func openMenuCoversMoreDisc() {
        let frames: [SidePanelChipTarget: CGRect] = [
            .more: CGRect(x: 16, y: 16, width: 34, height: 34),
            .menuSettings: CGRect(x: 16, y: 16, width: 98, height: 30)
        ]
        let point = CGPoint(x: 33, y: 30)
        #expect(SidePanelContentView.target(at: point, frames: frames) == .menuSettings)
    }

    @Test("The more menu stacks capture, select, pin and settings")
    func moreMenuOrder() {
        #expect(
            PanelMoreMenu.targets == [.menuCapture, .menuSelect, .menuPin, .menuSettings]
        )
    }

    /// The air between two controls is 8pt. The chip must keep a target there,
    /// or it fades out and back in on every pass from one control to its
    /// neighbour.
    @Test("The gap between two controls keeps the chip lit")
    func gapsBetweenControlsStayMarked() {
        let frames: [SidePanelChipTarget: CGRect] = [
            .more: CGRect(x: 8, y: 316, width: 28, height: 28),
            .engine: CGRect(x: 44, y: 316, width: 28, height: 28),
            .input: CGRect(x: 0, y: 44, width: 425, height: 92),
            .result: CGRect(x: 0, y: 142, width: 425, height: 166)
        ]
        // Dead centre of the 8pt gap between the two footer controls.
        #expect(SidePanelContentView.target(at: CGPoint(x: 40, y: 330), frames: frames) != nil)
        // The 6pt gap between the boxes.
        #expect(SidePanelContentView.target(at: CGPoint(x: 200, y: 139), frames: frames) != nil)
        // Inside no control and out of reach of every edge.
        #expect(SidePanelContentView.target(at: CGPoint(x: 200, y: 330), frames: frames) == nil)
    }

    /// The panel must accept main-window status.
    ///
    /// ``DroppyPanelActivation`` — which the host installs and every droplet
    /// panel calls — makes the panel key *and main*. A borderless window says
    /// no to `canBecomeMain` by default, and AppKit throws
    /// `NSInternalInconsistencyException` when asked to make it main anyway;
    /// the host treats that as a corrupt main thread and terminates. A test
    /// cannot call `begin()` outside Droppy (it is `nil` there), so the
    /// invariant it depends on is checked directly.
    @Test("The panel accepts main-window status")
    func thePanelCanBecomeMain() {
        #expect(TranslationPanel.shared.canBecomeKey)
        #expect(TranslationPanel.shared.canBecomeMain)
    }

    @Test("The floating panel grows with its result, up to its cap")
    func floatingPanelCardHeights() {
        let width = SidePanel.expandedWidth
        let short = "The rain in Spain falls mainly on the plain."
        let long = Array(repeating: short, count: 24).joined(separator: " ")
        let huge = Array(repeating: short, count: 120).joined(separator: " ")
        let source = "ฝนในสเปนตกหลักบนที่ราบ"

        func height(_ translated: String, _ source: String) -> CGFloat {
            ResultWindowView.cardHeight(
                forWidth: width,
                translated: translated,
                source: source,
                showsOriginal: !source.isEmpty
            )
        }

        #expect(height(short, "") == ResultWindowView.minimumHeight)
        #expect(height(short, source) == ResultWindowView.minimumHeightWithOriginal)

        let longBare = height(long, "")
        #expect(longBare > ResultWindowView.minimumHeight)
        #expect(longBare < ResultWindowView.maximumHeight)
        #expect(height(huge, "") == ResultWindowView.maximumHeight)

        // The original takes its share before the result, never past the cap.
        let longSource = height(long, source)
        #expect(longSource > longBare)
        #expect(longSource <= ResultWindowView.maximumHeight)
        #expect(height(huge, source) == ResultWindowView.maximumHeight)
    }

    @Test("A floating panel's long result scrolls under a capped source")
    func floatingPanelScrollsLongResults() throws {
        let short = "The rain in Spain falls mainly on the plain."
        let huge = Array(repeating: short, count: 120).joined(separator: " ")
        let source = Array(
            repeating: "ฝนในสเปนตกหลักบนที่ราบ",
            count: 12
        ).joined(separator: " ")
        let width = SidePanel.expandedWidth
        let height = ResultWindowView.cardHeight(
            forWidth: width,
            translated: huge,
            source: source,
            showsOriginal: true
        )
        #expect(height == ResultWindowView.maximumHeight)

        let hosting = NSHostingView(
            rootView: ResultWindowView(
                model: TranslateModel(),
                translated: huge,
                source: source,
                sourceName: "Thai",
                pinned: false,
                showsOriginal: true,
                onCopy: {},
                onClose: {},
                onPin: {}
            )
        )
        hosting.frame = CGRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        hosting.layoutSubtreeIfNeeded()

        let scrolls = Self.scrolls(in: hosting)
        #expect(scrolls.count == 2, "the panel needs a source and a result scroll view")
        for scroll in scrolls {
            #expect(scroll.contentView is VerticalOnlyClipView, "the panel can scroll sideways")
            #expect(!scroll.hasHorizontalScroller)
        }
        // The source comes first in the card.
        let sourceScroll = try #require(scrolls.first)
        let resultScroll = try #require(scrolls.last)
        // The tile now keeps the fade's air inside itself, so the cap is the
        // text's room under that air, not the tile's frame.
        #expect(
            sourceScroll.frame.height - PanelTileText.verticalAir * 2
                <= ResultWindowView.sourceTextCap + 0.5,
            "the original took the result's room"
        )
        #expect(
            (resultScroll.documentView?.frame.height ?? 0) > resultScroll.contentSize.height,
            "the long result has nothing to scroll"
        )
        #expect(resultScroll.hasVerticalScroller, "the long result lost its knob")
        window.orderOut(nil)
    }

    @Test("A window-drawn card leaves its content transparent")
    func windowSurfaceSitsBehindTheContent() throws {
        let size = CGSize(width: SidePanel.expandedWidth, height: ResultWindowView.minimumHeight)
        func alpha(_ backdrop: PanelBackdrop) throws -> CGFloat {
            let view = ResultWindowView(
                model: TranslateModel(),
                translated: "The rain in Spain falls mainly on the plain.",
                source: "ฝนในสเปนตกหลักบนที่ราบ",
                sourceName: "Thai",
                pinned: false,
                showsOriginal: true,
                backdrop: backdrop,
                onCopy: {},
                onClose: {},
                onPin: {}
            )
            let rep = try Self.bitmap(view, size: size)
            // Just inside the card's left edge, where the content has no ink.
            return rep.colorAt(x: 2, y: Int(size.height / 2))?.alphaComponent ?? -1
        }
        #expect(try alpha(.windowSurface) == 0, "the content still paints a card over the window's glass")
        #expect(try alpha(.hostGlassOnBlack) > 0.9, "the settings picture lost its card")
    }

    @Test("The side panel's result opens at the top and scrolls down")
    func sidePanelResultStartsAtTop() throws {
        let model = TranslateModel()
        model.beginPreview(
            source: "en",
            target: "th",
            text: "The rain in Spain falls mainly on the plain.",
            translated: Array(
                repeating: "ฝนตกในสเปนส่วนใหญ่บนที่ราบ",
                count: 40
            ).joined(separator: " ")
        )
        let hosting = NSHostingView(
            rootView: SidePanelContentView(
                model: model,
                chip: SidePanelChipState(),
                boxFloor: SidePanelContentView.panelBoxFloor
            )
        )
        hosting.frame = CGRect(
            x: 0,
            y: 0,
            width: SidePanel.expandedWidth - SidePanelContentView.inset * 2,
            height: 495
        )
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        hosting.layoutSubtreeIfNeeded()

        let scroll = try #require(Self.scrolls(in: hosting).first)
        #expect(scroll.contentView is VerticalOnlyClipView, "the result can scroll sideways")
        #expect(!scroll.hasHorizontalScroller)
        #expect(scroll.hasVerticalScroller, "the long result lost its knob")
        #expect(
            (scroll.documentView?.frame.height ?? 0) > scroll.contentSize.height,
            "the long result has nothing to scroll"
        )
        #expect(scroll.contentView.bounds.origin.y == 0, "the result opened below its first line")

        scroll.contentView.scroll(to: NSPoint(x: 0, y: 100))
        scroll.reflectScrolledClipView(scroll.contentView)
        hosting.layoutSubtreeIfNeeded()
        #expect(abs(scroll.contentView.bounds.origin.y - 100) < 0.5, "a layout pass undid the scroll")
        window.orderOut(nil)
    }

    /// The output scroll views under a view, in the order they are drawn.
    private static func scrolls(in view: NSView) -> [InsetScrollView] {
        if let scroll = view as? InsetScrollView { return [scroll] }
        return view.subviews.flatMap { scrolls(in: $0) }
    }

    /// The editor the shelf mounted, wherever SwiftUI put it in the host view.
    private static func textView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        for subview in view.subviews {
            if let found = textView(in: subview) { return found }
        }
        return nil
    }

    /// Draws a view in a window and writes it out as a PNG.
    ///
    /// - Returns: the size of the picture in bytes.
    private static func draw(_ view: NSView, size: CGSize, named name: String) throws -> Int {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = view
        // The window is never ordered in front: the picture is taken from the
        // view itself, so nothing flashes on the screen while the tests run.
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        view.layoutSubtreeIfNeeded()

        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            Issue.record("no bitmap for \(name)")
            return 0
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            Issue.record("no PNG for \(name)")
            return 0
        }
        let url = Self.folder.appendingPathComponent("\(name).png")
        try data.write(to: url)
        window.orderOut(nil)
        return data.count
    }

    /// Draws a view in a window and writes it out as a PNG.
    ///
    /// - Returns: the size of the picture in bytes.
    private static func draw(_ view: some View, size: CGSize, named name: String) throws -> Int {
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let rep = try bitmap(view, size: size)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            Issue.record("no PNG for \(name)")
            return 0
        }
        let url = Self.folder.appendingPathComponent("\(name).png")
        try data.write(to: url)
        return data.count
    }

    /// Draws a view into a bitmap, outside any visible window.
    private static func bitmap(_ view: some View, size: CGSize) throws -> NSBitmapImageRep {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hosting
        // The window is never ordered in front: the picture is taken from the
        // view itself, so nothing flashes on the screen while the tests run.

        // One run loop turn: the material and the buttons need a pass.
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.orderOut(nil)
        return rep
    }
}

/// Records the card heights the shelf asks the host for.
private final class ShelfStepLog {
    var steps: [ShelfHeightStep] = []
}

/// The pressed edge tab: the black card plus its content, laid out the way
/// ``SidePanel`` lays it out.
@MainActor
private final class SidePanelExpandedPreview: NSView {
    override var isFlipped: Bool { true }

    init(
        model: TranslateModel,
        boxHeight: CGFloat = SidePanelContentView.maxBoxHeight,
        boxFloor: CGFloat = SidePanelContentView.minBoxHeight,
        fold: CGFloat = 0
    ) {
        super.init(
            frame: CGRect(
                origin: .zero,
                size: CGSize(
                    width: SidePanel.expandedWidth,
                    height: SidePanel.windowHeight(
                        forBody: SidePanelContentView.bodyHeight(
                            forBox: boxHeight * (1 - fold),
                            result: SidePanelContentView.showsResult(for: model),
                            resultHeight: SidePanelContentView.resultBoxHeight
                                + boxHeight * fold
                        )
                    )
                )
            )
        )
        let hosting = NSHostingView(
            rootView: SidePanelContentView(
                model: model,
                chip: SidePanelChipState(),
                boxHeight: boxHeight,
                boxFloor: boxFloor,
                fold: fold
            )
        )
        hosting.appearance = NSAppearance(named: .darkAqua)
        addSubview(hosting)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        guard let hosting = subviews.first else { return }
        let inset = SidePanelContentView.inset
        let body = bounds.height - SidePanelCardShape.filletRadius * 2 - SidePanelContentView.gripStrip
        hosting.frame = NSRect(
            x: inset,
            y: SidePanelCardShape.filletRadius + inset,
            width: bounds.width - inset * 2,
            height: SidePanelContentView.contentHeight(forBody: body)
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        let card = NSRect(
            x: bounds.minX,
            y: bounds.minY,
            width: bounds.width,
            height: bounds.height - SidePanelContentView.gripStrip
        )
        NSBezierPath(cgPath: SidePanelCardShape().path(in: card).cgPath).fill()
    }
}
