import DroppyKit
import SwiftUI

/// The controls the edge panel's sliding chip can mark.
enum SidePanelChipTarget: Hashable, CaseIterable {
    case source, target, swap, more, engine
    /// The discs inside the boxes: copy, paste and clear, plus the download
    /// pill in the result's empty state.
    case download, copy, paste, clear
    /// The rows of the open more menu. The panel's chip marks the row itself.
    case menuCapture, menuSelect, menuPin, menuSettings
    /// The two boxes. Their frames contain the discs above, so they are tested
    /// last, and the chip takes the box's own silhouette.
    case input, result
}

extension SidePanelChipTarget {
    /// A box's mark takes the box's own silhouette, not a capsule.
    var isBox: Bool { self == .input || self == .result }

    /// A control of the language row, which step 3 fades out. Its frame stays
    /// in the preference after the fade, so the hit test must skip it by hand.
    var isHeader: Bool {
        switch self {
        case .source, .target, .swap: return true
        default: return false
        }
    }

    /// A row of the open more menu.
    var isMenu: Bool {
        switch self {
        case .menuCapture, .menuSelect, .menuPin, .menuSettings: return true
        default: return false
        }
    }
}

/// The chip's shared state: the control under the pointer, whether it is held
/// down, and where every control's ink sits.
///
/// One piece of glass slides over the whole panel, so a marked control draws
/// no hover wash of its own and the chip draws the control's ink again, above
/// the glass.
@MainActor
final class SidePanelChipState: ObservableObject {
    /// The control under the pointer; nil hides the chip.
    @Published var target: SidePanelChipTarget? {
        didSet {
            guard let target else { return }
            lastTarget = target
        }
    }
    /// The last control the chip marked, so it can fade over that frame and
    /// keep its corner after the pointer leaves.
    @Published private(set) var lastTarget: SidePanelChipTarget?
    /// True while the pointer holds the marked control.
    @Published var pressed = false
    /// Each control's frame, in the panel's coordinate space.
    @Published var frames: [SidePanelChipTarget: CGRect] = [:]

    /// The space the frames are measured in.
    static let space = "sidePanelChip"

    /// The lift a marked control's ink takes under the pointer.
    static let hoverScale: CGFloat = 1.1
    /// The dip it takes while it is held.
    static let pressScale: CGFloat = 0.96

    /// The frame the chip marks a control at, published by the control. Most
    /// controls report their own frame; the more disc reports the smaller
    /// chip it keeps inside its glass.
    func chipRect(for target: SidePanelChipTarget) -> CGRect? {
        frames[target]
    }

    /// The scale the chip's ink takes: the hover lift, or the press dip while
    /// the control is held. The glass keeps the control's frame, so a marked
    /// button reads like the menu rows: the ink moves, the mark stays.
    var inkScale: CGFloat {
        pressed ? Self.pressScale : Self.hoverScale
    }

    /// The frame the mark takes: the marked control's, or the one it last
    /// covered. The mark travels between the two, so it slides from control to
    /// control instead of blinking at each one.
    func rect(resting: CGRect?) -> CGRect? {
        if let target { return chipRect(for: target) ?? resting }
        if let lastTarget, let rect = chipRect(for: lastTarget) { return rect }
        return resting
    }

    /// A box's mark is a wash in the box's silhouette. macOS 26 glass cannot
    /// clip a shape that has a hole, so glass over a box draws a rainbow bar.
    /// A menu row takes the wash too: it already sits on the menu's own glass,
    /// and a second glass over it hides the row's words.
    func marksWithWash(_ target: SidePanelChipTarget?) -> Bool {
        guard let target else { return false }
        return target.isBox || target.isMenu
    }

    func isBox(_ target: SidePanelChipTarget?) -> Bool {
        target?.isBox ?? false
    }

    func isMenu(_ target: SidePanelChipTarget?) -> Bool {
        target?.isMenu ?? false
    }

    /// True when the chip covers this control, so the chip draws its ink.
    func covers(_ target: SidePanelChipTarget?) -> Bool {
        guard let target, self.target == target else { return false }
        // Without a frame the chip has nothing to draw over, so the control
        // keeps its own ink instead of both copies going missing.
        return frames[target] != nil
    }
}

struct LiquidChipFrame: VectorArithmetic {
    var x, y, width, height, bloom: Double

    init(x: Double, y: Double, width: Double, height: Double, bloom: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.bloom = bloom
    }

    init(_ rect: CGRect, bloom: CGFloat = 1) {
        self.init(
            x: Double(rect.minX),
            y: Double(rect.minY),
            width: Double(rect.width),
            height: Double(rect.height),
            bloom: Double(bloom)
        )
    }

    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    static let zero = LiquidChipFrame(x: 0, y: 0, width: 0, height: 0, bloom: 0)

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(
            x: lhs.x + rhs.x,
            y: lhs.y + rhs.y,
            width: lhs.width + rhs.width,
            height: lhs.height + rhs.height,
            bloom: lhs.bloom + rhs.bloom
        )
    }

    static func - (lhs: Self, rhs: Self) -> Self {
        Self(
            x: lhs.x - rhs.x,
            y: lhs.y - rhs.y,
            width: lhs.width - rhs.width,
            height: lhs.height - rhs.height,
            bloom: lhs.bloom - rhs.bloom
        )
    }

    static func += (lhs: inout Self, rhs: Self) { lhs = lhs + rhs }
    static func -= (lhs: inout Self, rhs: Self) { lhs = lhs - rhs }

    mutating func scale(by rhs: Double) {
        x *= rhs
        y *= rhs
        width *= rhs
        height *= rhs
        bloom *= rhs
    }

    var magnitudeSquared: Double {
        x * x + y * y + width * width + height * height + bloom * bloom
    }
}

/// A capsule that reaches toward its destination while it travels between controls.
struct LiquidChipShape: Shape {
    var frame: LiquidChipFrame
    var destination: CGPoint

    init(rect: CGRect, destination: CGPoint, bloom: CGFloat = 1) {
        frame = LiquidChipFrame(rect, bloom: bloom)
        self.destination = destination
    }

    var animatableData: LiquidChipFrame {
        get { frame }
        set { frame = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var current = frame.rect
        let centre = CGPoint(x: current.midX, y: current.midY)
        current = CGRect(
            x: centre.x - current.width * frame.bloom / 2,
            y: centre.y - current.height * frame.bloom / 2,
            width: current.width * frame.bloom,
            height: current.height * frame.bloom
        )
        let dx = destination.x - current.midX
        let dy = destination.y - current.midY
        let stretch = min(hypot(dx, dy) * 0.2, 18)
        if abs(dx) >= abs(dy) {
            if dx < 0 { current.origin.x -= stretch }
            current.size.width += stretch
        } else {
            if dy < 0 { current.origin.y -= stretch }
            current.size.height += stretch
        }
        return Capsule(style: .continuous).path(in: current)
    }
}

/// Where the controls the chip can mark sit, published by the controls
/// themselves.
struct SidePanelChipFrameKey: PreferenceKey {
    static var defaultValue: [SidePanelChipTarget: CGRect] { [:] }

    static func reduce(value: inout Value, nextValue: () -> Value) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Reports where a marked control sits, so the chip can cover it. `inset`
    /// pulls the mark inside the control's rim, as the boxes' hover chrome is.
    func chipTarget(_ target: SidePanelChipTarget?, inset: CGFloat = 0) -> some View {
        chipTarget(
            target,
            insets: EdgeInsets(top: inset, leading: inset, bottom: inset, trailing: inset)
        )
    }

    /// The same, with each side pulled in by its own amount: the language row's
    /// halves keep 3pt on the capsule's end and run to the pocket's tangent,
    /// where the pocket's curve leaves the same 3pt.
    func chipTarget(_ target: SidePanelChipTarget?, insets: EdgeInsets) -> some View {
        background {
            GeometryReader { proxy in
                let rect = proxy.frame(in: .named(SidePanelChipState.space))
                let marked = CGRect(
                    x: rect.minX + insets.leading,
                    y: rect.minY + insets.top,
                    width: max(0, rect.width - insets.leading - insets.trailing),
                    height: max(0, rect.height - insets.top - insets.bottom)
                )
                Color.clear.preference(
                    key: SidePanelChipFrameKey.self,
                    value: target.map { [$0: marked] } ?? [:]
                )
            }
        }
    }
}

extension View {
    /// Hides a control's own ink while the chip draws the same ink above its
    /// glass. Both copies run on the chip's clock, so they cross-fade instead
    /// of swapping the moment the pointer moves.
    func chipHidesInk(_ covered: Bool) -> some View {
        opacity(covered ? 0 : 1)
            .animation(DroppyAnimation.state, value: covered)
    }
}

/// The chip's state, for the controls that share it.
private struct SidePanelChipKey: EnvironmentKey {
    static var defaultValue: SidePanelChipState? { nil }
}

extension EnvironmentValues {
    /// The panel's chip; nil where the panel does not draw one.
    var sidePanelChip: SidePanelChipState? {
        get { self[SidePanelChipKey.self] }
        set { self[SidePanelChipKey.self] = newValue }
    }
}
