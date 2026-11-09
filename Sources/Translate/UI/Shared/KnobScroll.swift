import AppKit
import DroppyKit
import SwiftUI

/// Draws only the knob, fading it when idle; dragging and clicking still work
/// at any opacity. Shared by the input and result boxes.
final class KnobOnlyScroller: NSScroller {
    private let idleAlpha: CGFloat = 0.15
    private let fadeDelay: Duration = .milliseconds(900)

    private var fadeTask: Task<Void, Never>?
    private var isDragging = false
    private var isAwake = false
    private var hoverArea: NSTrackingArea?

    /// Checked on demand: a remembered "hovering" flag goes stale when the
    /// layout moves under a still mouse, since no mouseExited arrives.
    private var isPointerInside: Bool {
        guard let window else { return false }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return bounds.contains(point)
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
    }

    // MARK: Scroll detection

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        NotificationCenter.default.removeObserver(
            self, name: NSView.boundsDidChangeNotification, object: nil)
        guard let clip = (superview as? NSScrollView)?.contentView else { return }
        clip.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contentScrolled),
            name: NSView.boundsDidChangeNotification,
            object: clip)
        isAwake = false
        alphaValue = idleAlpha
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { scheduleFade() }
    }

    @objc private func contentScrolled() {
        wake()
    }

    // MARK: Hover / drag

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        wake()
    }

    override func mouseExited(with event: NSEvent) {
        scheduleFade()
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        wake()
        super.mouseDown(with: event)   // returns when the drag ends
        isDragging = false
        scheduleFade()
    }

    // MARK: Fade

    private func wake() {
        fadeTask?.cancel()
        // A live scroll wakes the knob on every frame; animating from 1 to 1
        // that often stacks animations and makes the knob flicker.
        if !isAwake {
            isAwake = true
            setAlpha(1)
        }
        scheduleFade()
    }

    /// Waits, then fades only if the pointer is really away. A missed
    /// `mouseExited` is caught by checking again instead of trusting one event.
    private func scheduleFade() {
        fadeTask?.cancel()
        fadeTask = Task { @MainActor [weak self, fadeDelay] in
            while !Task.isCancelled {
                try? await Task.sleep(for: fadeDelay)
                guard !Task.isCancelled, let self else { return }
                if !self.isPointerInside && !self.isDragging {
                    self.isAwake = false
                    self.setAlpha(self.idleAlpha)
                    return
                }
            }
        }
    }

    private func setAlpha(_ value: CGFloat) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            self.animator().alphaValue = value
        }
    }
}

/// Keeps a text view from scrolling sideways. Text wraps by character, so a
/// horizontal offset only makes the words jump when the viewport resizes.
final class VerticalOnlyClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var bounds = super.constrainBoundsRect(proposedBounds)
        bounds.origin.x = 0
        return bounds
    }
}

/// Shortens the vertical scroller at the top and bottom so the knob stops
/// before overlay buttons. The text area itself is untouched.
final class InsetScrollView: NSScrollView {
    var scrollerTopInset: CGFloat = 0 {
        didSet { if oldValue != scrollerTopInset { tile() } }
    }
    var scrollerBottomInset: CGFloat = 0 {
        didSet { if oldValue != scrollerBottomInset { tile() } }
    }
    /// False when a host controls the knob's visibility; the shared output views
    /// let the scroll view show it only while there is overflow.
    var managesKnobVisibility = true

    override func tile() {
        super.tile()
        guard let scroller = verticalScroller, !scroller.isHidden else { return }
        var frame = scroller.frame
        let total = scrollerTopInset + scrollerBottomInset
        guard total > 0, frame.height > total + 20 else { return }
        // Not flipped: origin.y is the bottom edge, so shift up by the bottom inset.
        frame.origin.y += isFlipped ? scrollerTopInset : scrollerBottomInset
        frame.size.height -= total
        scroller.frame = frame
    }

    override func reflectScrolledClipView(_ cView: NSClipView) {
        super.reflectScrolledClipView(cView)
        if let documentView, let window {
            window.invalidateCursorRects(for: documentView)
        }
    }

    override func layout() {
        super.layout()
        guard let textView = documentView as? NSTextView,
              let container = textView.textContainer,
              let layoutManager = textView.layoutManager else { return }
        let width = contentSize.width
        guard width > 0 else { return }
        if abs(textView.frame.width - width) > 0.5 {
            textView.setFrameSize(NSSize(width: width, height: textView.frame.height))
        }
        if abs(container.containerSize.width - width) > 0.5 {
            container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        }
        layoutManager.ensureLayout(for: container)
        let textHeight = layoutManager.usedRect(for: container).height
            + textView.textContainerInset.height * 2
        let documentHeight = max(contentSize.height, ceil(textHeight))
        if abs(textView.frame.height - documentHeight) > 0.5 {
            textView.setFrameSize(NSSize(width: width, height: documentHeight))
        }
        // Show the knob only when there is something to reach; on text that
        // fits, it invites a rubber-band scroll that reads as shaking.
        guard managesKnobVisibility else { return }
        let overflows = textHeight > contentSize.height + 0.5
        if hasVerticalScroller != overflows {
            // Showing the knob narrows the content and AppKit may keep an old
            // offset; a box at its top must stay there.
            let staysAtTop = contentView.bounds.origin.y <= 0.5
            hasVerticalScroller = overflows
            if staysAtTop, contentView.bounds.origin.y != 0 {
                contentView.scroll(to: .zero)
            }
        }
        if !overflows, contentView.bounds.origin.y != 0 {
            contentView.scroll(to: .zero)
        }
    }
}

/// A vertically scrollable result with character-level wrapping for unbroken scripts.
@MainActor
struct TranslationOutputScrollView: NSViewRepresentable {
    let text: String
    let resetToken: String
    let scrollerTopInset: CGFloat
    let scrollerBottomInset: CGFloat
    /// Room above and below the text; the edge panel's result box trims it.
    var textInset: CGFloat = 44
    /// The edge panel's result box reads larger than the shelf's.
    var fontSize: CGFloat = 13

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = InsetScrollView()
        scrollView.scrollerTopInset = scrollerTopInset
        scrollView.scrollerBottomInset = scrollerBottomInset
        scrollView.contentView = VerticalOnlyClipView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.verticalScroller = KnobOnlyScroller()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.verticalScrollElasticity = .allowed
        scrollView.horizontalScrollElasticity = .none
        scrollView.contentView.postsBoundsChangedNotifications = true

        let textView = OutputTextView(frame: NSRect(x: 0, y: 0, width: 380, height: 0))
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 0, height: textInset)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineBreakMode = .byWordWrapping
        let paragraph = NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = 5
        paragraph.headIndent = 5
        paragraph.lineBreakMode = .byWordWrapping
        textView.defaultParagraphStyle = paragraph
        textView.font = .systemFont(ofSize: fontSize)
        textView.textColor = PanelTileText.ink
        textView.string = text
        textView.applyCardTextShadow()
        context.coordinator.lastText = text
        context.coordinator.lastResetToken = resetToken
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if let inset = scrollView as? InsetScrollView {
            inset.scrollerTopInset = scrollerTopInset
            inset.scrollerBottomInset = scrollerBottomInset
        }
        if context.coordinator.lastResetToken != resetToken {
            context.coordinator.lastResetToken = resetToken
            textView.string = text
            textView.applyCardTextShadow()
            context.coordinator.lastText = text
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        } else if context.coordinator.lastText != text {
            let oldLength = (context.coordinator.lastText ?? "").utf16.count
            if text.utf16.count >= oldLength, text.hasPrefix(context.coordinator.lastText ?? "") {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: textView.font ?? .systemFont(ofSize: 13),
                    .foregroundColor: textView.textColor ?? .labelColor,
                    .shadow: CardTextShadow.nsShadow
                ]
                textView.textStorage?.append(NSAttributedString(
                    string: String(text.dropFirst((context.coordinator.lastText ?? "").count)),
                    attributes: attributes
                ))
            } else {
                textView.string = text
                textView.applyCardTextShadow()
            }
            context.coordinator.lastText = text
            scrollView.needsLayout = true
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        var lastText: String?
        var lastResetToken = ""
    }
}

private final class OutputTextView: CursorAwareTextView {}
