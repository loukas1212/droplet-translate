import AppKit
import Testing
@testable import Translate

/// The input box grows with its text; the clip must not ride that growth.
@Suite("Input clip")
@MainActor
struct InputClipTests {
    @Test("The caret does not scroll the clip while the text fits the cap")
    func caretKeepsTop() {
        let (scroll, window) = makeScrollView(text: Array(repeating: "line", count: 8).joined(separator: "\n"))
        defer { window.orderOut(nil) }
        let clip = scroll.contentView
        let textView = scroll.documentView as! NSTextView
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
        #expect(clip.bounds.origin.y == 0)
        #expect(scroll.fitsContent)
    }

    @Test("Text past the cap still scrolls the caret into view")
    func caretScrollsPastCap() {
        let (scroll, window) = makeScrollView(text: Array(repeating: "line", count: 40).joined(separator: "\n"))
        defer { window.orderOut(nil) }
        let clip = scroll.contentView
        let textView = scroll.documentView as! NSTextView
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
        #expect(!scroll.fitsContent)
        #expect(clip.bounds.origin.y > 0)
    }

    private func makeScrollView(text: String) -> (InputScrollView, NSWindow) {
        let scroll = InputScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 92))
        scroll.textInsets = (44, 44)
        scroll.scrollsWhenTallerThan = 228
        scroll.contentView = NSClipView()
        let textView = ScrollableNSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 0))
        textView.isRichText = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 0, height: 44)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineBreakMode = .byCharWrapping
        textView.string = text
        scroll.documentView = textView
        let window = NSWindow(
            contentRect: scroll.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = scroll
        window.orderFrontRegardless()
        scroll.layout()
        return (scroll, window)
    }
}
