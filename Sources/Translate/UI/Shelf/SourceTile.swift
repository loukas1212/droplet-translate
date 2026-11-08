import AppKit
import DroppyKit
import SwiftUI

/// The input half of the shelf. It wraps by character where `TextEditor` wraps
/// by word, so unspaced Thai does not grow sideways.
@MainActor
private struct ScrollableTextEditor: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void
    /// Room above the first line; the placeholder follows the same inset.
    var topInset: CGFloat = 44
    /// Room below the last line, so overlay controls never sit on the text.
    var bottomInset: CGFloat = 44
    /// Reports the height the text needs, insets included, so a host can size
    /// the box to its content before it starts scrolling.
    var onHeightChange: ((CGFloat) -> Void)?
    /// The height above which the box scrolls. A host that animates its box
    /// to the text's height sets this to the box's cap, so the knob never
    /// flashes while the box is still growing into the text.
    var scrollsWhenTallerThan: CGFloat?
    /// The edge panel types larger than the shelf.
    var fontSize: CGFloat = 13

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = InputScrollView()
        scrollView.textInsets = (topInset, bottomInset)
        scrollView.scrollsWhenTallerThan = scrollsWhenTallerThan
        // Strong: the coordinator only forwards, and keeps itself alive for the
        // text view's weak delegate slot.
        let coordinator = context.coordinator
        scrollView.contentHeightDidChange = { height in
            coordinator.onHeightChange?(height)
        }
        scrollView.contentView = VerticalOnlyClipView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.verticalScroller = KnobOnlyScroller()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.verticalScrollElasticity = .allowed
        scrollView.horizontalScrollElasticity = .none

        let textView = ScrollableNSTextView(frame: NSRect(x: 0, y: 0, width: 380, height: 0))
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.font = .systemFont(ofSize: fontSize)
        textView.textColor = PanelTileText.ink
        textView.insertionPointColor = PanelTileText.ink

        // The edge panel trims the top inset so a short box does not push its
        // line down. The 5pt leading indent lets the container track width.
        textView.textContainerInset = NSSize(width: 0, height: topInset)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineBreakMode = .byCharWrapping

        let paragraph = NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = 5
        paragraph.headIndent = 5
        paragraph.lineBreakMode = .byCharWrapping
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: PanelTileText.ink,
            .paragraphStyle: paragraph
        ]
        textView.string = text
        textView.applyCardTextShadow()

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onHeightChange = onHeightChange
        guard let textView = scrollView.documentView as? ScrollableNSTextView else { return }
        if textView.string != text {
            textView.string = text
            textView.applyCardTextShadow()
            scrollView.needsLayout = true
            let end = NSRange(location: text.utf16.count, length: 0)
            textView.setSelectedRange(end)
            textView.scrollRangeToVisible(end)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void
        var onHeightChange: ((CGFloat) -> Void)?
        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
        }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let candidate = tv.string
            guard candidate.count <= TranslateModel.maxInputLength else {
                // Put the old text back and keep the caret, so typing at the
                // limit simply stops.
                let accepted = text.wrappedValue
                tv.string = accepted
                let end = NSRange(location: accepted.utf16.count, length: 0)
                tv.setSelectedRange(end)
                return
            }
            text.wrappedValue = candidate
            // The box grows from a layout pass; typing must trigger one.
            tv.enclosingScrollView?.needsLayout = true
        }
    }
}

final class ScrollableNSTextView: CursorAwareTextView {
    override func scrollRangeToVisible(_ range: NSRange) {
        // The caret is already on screen while the text fits the box's cap, and
        // scrolling it into view rides the box's growth: the words bob.
        if let scroll = enclosingScrollView as? InputScrollView, scroll.fitsContent { return }
        super.scrollRangeToVisible(range)
    }

    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 36 || event.keyCode == 76),
           !event.modifierFlags.contains(.shift) {
            (delegate as? ScrollableTextEditor.Coordinator)?.onSubmit()
            return
        }
        super.keyDown(with: event)
    }
}

/// Forces the text view and its container to the viewport width, so a view
/// created with long text before it has a real size cannot scroll sideways.
final class InputScrollView: NSScrollView {
    private let scrollerTopInset: CGFloat = 38
    private let scrollerBottomInset: CGFloat = 42
    /// Empty space above and below the text, matching the container inset.
    var textInsets: (top: CGFloat, bottom: CGFloat) = (44, 44)
    /// Above this height the box scrolls; nil means the view's own height.
    var scrollsWhenTallerThan: CGFloat?
    /// Called when the text needs more or less room than the last report.
    var contentHeightDidChange: ((CGFloat) -> Void)?
    private var reportedHeight: CGFloat = -1

    /// True while the text fits the height the box is allowed to take, so the
    /// caret needs no scroll to stay in view. Measured from the layout, not the
    /// document frame: typing scrolls before the next layout pass resizes it.
    var fitsContent: Bool {
        guard let textView = documentView as? NSTextView,
              let container = textView.textContainer,
              let layoutManager = textView.layoutManager else { return true }
        layoutManager.ensureLayout(for: container)
        let textHeight = layoutManager.usedRect(for: container).height
            + textInsets.top + textInsets.bottom
        return textHeight <= (scrollsWhenTallerThan ?? contentSize.height) + 0.5
    }

    override func tile() {
        super.tile()
        guard let scroller = verticalScroller, !scroller.isHidden else { return }
        var frame = scroller.frame
        let total = scrollerTopInset + scrollerBottomInset
        guard frame.height > total + 20 else { return }
        // Not flipped: origin.y is the bottom edge, so shift up by the bottom inset.
        frame.origin.y += isFlipped ? scrollerTopInset : scrollerBottomInset
        frame.size.height -= total
        scroller.frame = frame
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
            container.containerSize = NSSize(width: width,
                                             height: CGFloat.greatestFiniteMagnitude)
        }
        layoutManager.ensureLayout(for: container)
        let textHeight = ceil(
            layoutManager.usedRect(for: container).height
                + textInsets.top + textInsets.bottom
        )
        let documentHeight = max(contentSize.height, textHeight)
        if abs(textView.frame.height - documentHeight) > 0.5 {
            textView.setFrameSize(NSSize(width: width, height: documentHeight))
        }
        // A knob only when there is something to scroll to. While a host
        // animates the box, the cap decides, not the half-grown frame.
        let overflowHeight = scrollsWhenTallerThan ?? contentSize.height
        let overflows = textHeight > overflowHeight + 0.5
        if hasVerticalScroller != overflows {
            hasVerticalScroller = overflows
        }
        // The caret is scrolled into view on every new line, but while the text
        // fits, that rides the box's growth and bobs the words; pin it to the top.
        if !overflows, contentView.bounds.origin.y != 0 {
            contentView.scroll(to: .zero)
        }
        if reportedHeight != textHeight {
            reportedHeight = textHeight
            let report = contentHeightDidChange
            DispatchQueue.main.async { report?(textHeight) }
        }
    }

    override func reflectScrolledClipView(_ cView: NSClipView) {
        super.reflectScrolledClipView(cView)
        if let documentView, let window {
            window.invalidateCursorRects(for: documentView)
        }
    }
}

@MainActor
func textCursorRect(in view: NSView, topInset: CGFloat, bottomInset: CGFloat) -> NSRect? {
    var rect = view.visibleRect
    guard rect.height > topInset + bottomInset else { return nil }
    rect.origin.y += view.isFlipped ? topInset : bottomInset
    rect.size.height -= topInset + bottomInset
    assert(view.visibleRect.contains(rect), "I-beam cursor rect must stay inside the visible text area")
    return rect
}

/// The input half of the shelf: language pill, editor, and the clear and paste
/// controls.
struct SourceTile: View {
    @ObservedObject var model: TranslateModel
    /// The shelf keeps the swap pocket on the bottom seam; the edge panel cuts
    /// its own pocket into the header and this box.
    var notch: SeamNotchShape.Edge? = .bottom
    /// The edge panel lifts the language into a header above the tile.
    var showsLanguageMenu = true
    /// The edge panel asks for its own tile radius; the shelf keeps the shared one.
    var tileCornerRadius: CGFloat?
    /// The edge panel trims the empty top of the box; the shelf keeps 44.
    var editorTopInset: CGFloat = 44
    var editorBottomInset: CGFloat = 44
    /// Return's action. The shelf raises its card so the result is visible;
    /// the panel falls back to translating in place.
    var onSubmit: (() -> Void)?
    /// The edge panel sizes its box from this; the shelf keeps a fixed frame.
    var onEditorHeight: ((CGFloat) -> Void)?
    /// The edge panel draws its own paste and clear discs inside the box, so
    /// the shelf's inline row is off.
    var showsInlineTools = true
    /// The edge panel's box is larger than the shelf tile.
    var bodyFontSize: CGFloat = 13
    /// The shelf keeps its short box; the edge panel lets it reach its cap.
    var maxEditorHeight: CGFloat = 180
    /// The height the box scrolls above. The edge panel animates its box, so
    /// it names the cap; the shelf leaves it to the box's own frame.
    var scrollerCap: CGFloat?
    /// The edge panel lights the box with the same hover capsule as its
    /// language row; the shelf keeps the plain tile.
    var hoverChrome = false
    /// The control the edge panel's chip marks this box as.
    var chipTarget: SidePanelChipTarget?
    /// The edge panel's swap pocket, so the chip's hover wash leaves the disc
    /// clear.
    var pocketCut: SidePanelBoxCut?

    @State private var hovering = false
    @Environment(\.sidePanelChip) private var chip

    var body: some View {
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                ScrollableTextEditor(
                    text: $model.input,
                    onSubmit: onSubmit ?? model.translate,
                    topInset: editorTopInset,
                    bottomInset: editorBottomInset,
                    onHeightChange: onEditorHeight,
                    scrollsWhenTallerThan: scrollerCap,
                    fontSize: bodyFontSize
                )
                .frame(minHeight: 44)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
                if model.input.isEmpty {
                    // The prompt sits where the first typed line lands: the same
                    // top inset and leading indent the editor gives the text.
                    Text(L10n.tr("placeholder"))
                        .font(.system(size: bodyFontSize))
                        .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                        .cardTextShadow()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.leading, 5)
                        .padding(.top, editorTopInset)
                        .allowsHitTesting(false)
                }
            }
            // Compact by design: the input stays short so the output gets the
            // bigger share of the shelf.
            .frame(maxWidth: .infinity, minHeight: 52, maxHeight: maxEditorHeight)
            .clipped()
            // Soft fade at the edges, as every box does.
            .panelTileEdgeFade()
            .clipShape(
                SeamNotchShape(
                    edge: notch,
                    cornerRadius: tileCornerRadius ?? TileMetrics.cornerRadius
                )
            )

            if showsLanguageMenu {
                HStack(spacing: 6) {
                    LanguageMenu(
                        model: model,
                        selection: $model.sourceID,
                        includesAuto: true,
                        label: sourceLabel(for: model),
                        availableIDs: model.installedSourceIDs
                    )
                    Spacer(minLength: 6)
                }
                .padding(.top, DroppySpacing.sm)
                .zIndex(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The same margin as every box: the text view's 5pt indent makes the
        // first glyph start 13pt from the rim.
        .padding(.horizontal, PanelTileText.sideInset)
        .tileHoverChrome(
            hoverChrome && chip == nil && hovering,
            cornerRadius: tileCornerRadius ?? TileMetrics.cornerRadius,
            pocket: pocketCut
        )
        .chipTarget(chipTarget)
        .overlay(alignment: .bottomLeading) {
            if showsInlineTools {
                HStack(alignment: .bottom, spacing: DroppySpacing.sm) {
                    TileIconButton(symbol: "clipboard.fill", a11yKey: "a11y.paste", diameter: 24) {
                        model.pasteInput()
                    }
                    .disabled(!model.canPaste)
                    Spacer(minLength: DroppySpacing.sm)
                }
                .frame(height: 24, alignment: .bottom)
                .padding(.leading, DroppySpacing.sm)
                .padding(.bottom, DroppySpacing.sm)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showsInlineTools, model.canTranslate {
                submitButton
                    .transition(.opacity)
                    .padding(.trailing, DroppySpacing.sm)
                    .padding(.bottom, DroppySpacing.sm)
            }
        }
        .animation(DroppyAnimation.state, value: model.canTranslate)
        .onHover { hovering = $0 }
    }

    private var submitButton: some View {
        Button { model.translate() } label: {
            Group {
                if model.status == .translating {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(1.3)
                        .frame(width: 22, height: 22)
                } else {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 20, weight: .bold))
                        .frame(width: 22, height: 22)
                }
            }
            .frame(width: 44, height: 34)
        }
        .font(.system(size: 12, weight: .semibold))
        .buttonStyle(DroppyGlassButtonStyle(shape: AnyShape(Capsule())))
        .arrowCursorRegion()
        .a11y("a11y.translate")
    }
}
