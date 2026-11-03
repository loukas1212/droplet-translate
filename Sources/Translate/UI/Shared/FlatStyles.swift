import DroppyKit
import SwiftUI
import AppKit

@MainActor
private enum ArrowCursorRegions {
    private static var active = Set<UUID>()

    static var isActive: Bool { !active.isEmpty }

    @discardableResult
    static func set(_ id: UUID, active isActive: Bool) -> Bool {
        let wasActive = !active.isEmpty
        if isActive {
            active.insert(id)
        } else {
            active.remove(id)
        }
        return wasActive != !active.isEmpty
    }
}

/// The input box's editor on a droplet panel: the first editable text view,
/// since the menus' labels are not editable. Both panels put the caret in it
/// when they open for typing.
@MainActor
func firstEditor(in view: NSView) -> NSTextView? {
    if let text = view as? NSTextView, text.isEditable { return text }
    for subview in view.subviews {
        if let found = firstEditor(in: subview) { return found }
    }
    return nil
}

@MainActor
class CursorAwareTextView: NSTextView {
    /// The floating panel's boxes are text, not the card's face: a press on the
    /// words selects them, and a press in the air around them places the caret
    /// or does nothing. The panel drags from its own face, outside the boxes,
    /// so the text view keeps its normal tracking here.
    override func mouseDown(with event: NSEvent) {
        guard window is TranslationPanel else { return super.mouseDown(with: event) }
        let point = convert(event.locationInWindow, from: nil)
        guard !isOnGlyph(at: point) else { return super.mouseDown(with: event) }
        // A click in the air still has to reach the editor: place the caret
        // there and leave the selection alone.
        guard isEditable else { return }
        window?.makeFirstResponder(self)
        setSelectedRange(NSRange(location: characterIndexForInsertion(at: point), length: 0))
    }

    /// Whether `point`, in this view's coordinates, lands on a line of words.
    func isOnGlyph(at point: NSPoint) -> Bool {
        guard !string.isEmpty, let layoutManager, let container = textContainer else {
            return false
        }
        layoutManager.ensureLayout(for: container)
        let origin = textContainerOrigin
        let inContainer = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        let glyph = layoutManager.glyphIndex(for: inContainer, in: container)
        guard glyph < layoutManager.numberOfGlyphs else { return false }
        // The line's used rect, not the glyph's: a newline's bounding rect
        // reaches the end of its line, which would make the line's trailing
        // air read as text.
        return layoutManager
            .lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
            .contains(inContainer)
    }

    override func resetCursorRects() {
        guard !ArrowCursorRegions.isActive else { return }
        guard window is TranslationPanel else {
            guard let rect = textCursorRect(in: self, topInset: 44, bottomInset: 44) else { return }
            addCursorRect(rect, cursor: .iBeam)
            return
        }
        // Only the words take the I-beam; the air around them is the card's,
        // and an I-beam there would promise a selection the press does not make.
        guard let layoutManager, let container = textContainer, !string.isEmpty else { return }
        layoutManager.ensureLayout(for: container)
        let origin = textContainerOrigin
        layoutManager.enumerateLineFragments(
            forGlyphRange: NSRange(location: 0, length: layoutManager.numberOfGlyphs)
        ) { _, used, _, _, _ in
            let rect = used.offsetBy(dx: origin.x, dy: origin.y)
                .intersection(self.visibleRect)
            guard !rect.isEmpty else { return }
            self.addCursorRect(rect, cursor: .iBeam)
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        guard !ArrowCursorRegions.isActive else { NSCursor.arrow.set(); return }
        super.cursorUpdate(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        guard !ArrowCursorRegions.isActive else { NSCursor.arrow.set(); return }
        super.mouseMoved(with: event)
    }
}

@MainActor
private struct ArrowCursorRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> ArrowCursorRegionView { ArrowCursorRegionView() }
    func updateNSView(_ nsView: ArrowCursorRegionView, context: Context) {}
}

@MainActor
private final class ArrowCursorRegionView: NSView {
    private let regionID = UUID()
    private var trackingArea: NSTrackingArea?
    private var isActive = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .cursorUpdate, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
        updatePointer(at: window?.mouseLocationOutsideOfEventStream)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updatePointer(at: window?.mouseLocationOutsideOfEventStream)
    }

    override func layout() {
        super.layout()
        updatePointer(at: window?.mouseLocationOutsideOfEventStream)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func cursorUpdate(with event: NSEvent) {
        updatePointer(at: event.locationInWindow)
    }

    override func mouseEntered(with event: NSEvent) {
        updatePointer(at: event.locationInWindow)
    }

    override func mouseMoved(with event: NSEvent) {
        updatePointer(at: event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        updatePointer(at: event.locationInWindow)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func updatePointer(at windowPoint: NSPoint?) {
        guard let windowPoint, window != nil else {
            setActive(false)
            return
        }
        let inside = bounds.contains(convert(windowPoint, from: nil))
        setActive(inside)
        if inside { NSCursor.arrow.set() }
    }

    private func setActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
        guard ArrowCursorRegions.set(regionID, active: active),
              let contentView = window?.contentView else { return }
        invalidateTextCursorRects(in: contentView)
    }

    private func invalidateTextCursorRects(in view: NSView) {
        if let textView = view as? CursorAwareTextView, let window {
            window.invalidateCursorRects(for: textView)
        }
        view.subviews.forEach(invalidateTextCursorRects(in:))
    }
}

/// `buttonStyle` inside another `ButtonStyle.makeBody` never applies, so the
/// kit's Liquid Glass chrome is applied with plain modifiers instead.
struct TranslateCircleStyle: ViewModifier {
    var diameter: CGFloat

    func body(content: Content) -> some View {
        content
            .buttonStyle(DroppyCircleButtonStyle(size: diameter))
    }
}

struct TranslatePillStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .buttonStyle(DroppyQuietButtonStyle(size: .small))
    }
}

struct TranslateIconPillStyle: ViewModifier {
    var height: CGFloat
    var width: CGFloat?

    func body(content: Content) -> some View {
        content
            .buttonStyle(DroppyQuietButtonStyle(size: .small))
            .frame(width: width, height: height)
            .clipShape(Capsule())
    }
}

extension View {
    func arrowCursorRegion() -> some View {
        background {
            ArrowCursorRegion()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
        }
    }

    func translateCircle(diameter: CGFloat) -> some View {
        modifier(TranslateCircleStyle(diameter: diameter))
            .arrowCursorRegion()
    }
    func translatePill() -> some View {
        modifier(TranslatePillStyle())
            .arrowCursorRegion()
    }
    func translateIconPill(height: CGFloat, width: CGFloat? = nil) -> some View {
        modifier(TranslateIconPillStyle(height: height, width: width))
            .arrowCursorRegion()
    }
}

