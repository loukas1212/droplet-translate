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

@MainActor
class CursorAwareTextView: NSTextView {
    override func resetCursorRects() {
        guard !ArrowCursorRegions.isActive,
              let rect = textCursorRect(in: self, topInset: 44, bottomInset: 44) else { return }
        addCursorRect(rect, cursor: .iBeam)
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

/// The kit's clock, so Reduce Motion gets the host's calm curve, not a spring.
struct HoverGrowStyle: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? 1.15 : 1)
            .animation(DroppyAnimation.hoverScale, value: hovering)
            .onHover { hovering = $0 }
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
            .modifier(HoverGrowStyle())
            .arrowCursorRegion()
    }
    func translatePill() -> some View {
        modifier(TranslatePillStyle())
            .modifier(HoverGrowStyle())
            .arrowCursorRegion()
    }
    func translateIconPill(height: CGFloat, width: CGFloat? = nil) -> some View {
        modifier(TranslateIconPillStyle(height: height, width: width))
            .modifier(HoverGrowStyle())
            .arrowCursorRegion()
    }
}

